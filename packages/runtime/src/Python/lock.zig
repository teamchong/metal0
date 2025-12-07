/// lock - Low-level Lock Implementation
/// Mirrors cpython/Python/lock.c
///
/// This module provides low-level lock primitives for the Python runtime:
/// - PyMutex: lightweight mutex with spinning and parking
/// - Once: one-time initialization
/// - RWLock: reader-writer lock
/// - Critical sections: nested lock management

const std = @import("std");
const builtin = @import("builtin");
const Atomic = std.atomic.Value;

// ============================================================================
// Constants
// ============================================================================

/// Time after which we hand off lock ownership (1ms in nanoseconds)
const TIME_TO_BE_FAIR_NS: i64 = 1_000_000;

/// Maximum spin count before parking (0 if GIL enabled)
const MAX_SPIN_COUNT: usize = 40;

/// Lock bits
const LOCKED: u8 = 1;
const HAS_PARKED: u8 = 2;

// ============================================================================
// Lock Status
// ============================================================================

/// Result of lock acquisition attempt
pub const LockStatus = enum {
    acquired,
    failure,
    intr,
};

/// Lock flags
pub const LockFlags = packed struct(u8) {
    dont_detach: bool = false,
    fail_if_interrupted: bool = false,
    _padding: u6 = 0,
};

// ============================================================================
// PyMutex - Lightweight Mutex
// ============================================================================

/// Lightweight mutex with spinning and parking
pub const PyMutex = struct {
    bits: Atomic(u8) = Atomic(u8).init(0),

    const Self = @This();

    /// Lock the mutex (blocking)
    pub fn lock(self: *Self) void {
        _ = self.lockTimed(-1, .{});
    }

    /// Unlock the mutex
    pub fn unlock(self: *Self) void {
        const old = self.bits.swap(0, .release);
        if (old & HAS_PARKED != 0) {
            // Wake up parked threads
            self.wakeOne();
        }
    }

    /// Try to lock without blocking
    pub fn tryLock(self: *Self) bool {
        var expected: u8 = 0;
        return self.bits.cmpxchgWeak(expected, LOCKED, .acquire, .relaxed) == null;
    }

    /// Lock with timeout
    pub fn lockTimed(self: *Self, timeout_ns: i64, flags: LockFlags) LockStatus {
        _ = flags;

        var v = self.bits.load(.relaxed);

        // Fast path: unlocked
        if (v & LOCKED == 0) {
            if (self.bits.cmpxchgWeak(v, v | LOCKED, .acquire, .relaxed) == null) {
                return .acquired;
            }
        }

        if (timeout_ns == 0) {
            return .failure;
        }

        return self.lockSlow(timeout_ns);
    }

    fn lockSlow(self: *Self, timeout_ns: i64) LockStatus {
        const start = std.time.nanoTimestamp();

        var spin_count: usize = 0;

        while (true) {
            var v = self.bits.load(.relaxed);

            // Try to acquire
            if (v & LOCKED == 0) {
                if (self.bits.cmpxchgWeak(v, v | LOCKED, .acquire, .relaxed) == null) {
                    return .acquired;
                }
                continue;
            }

            // Spin before parking
            if (v & HAS_PARKED == 0 and spin_count < MAX_SPIN_COUNT) {
                yield();
                spin_count += 1;
                continue;
            }

            // Check timeout
            if (timeout_ns > 0) {
                const elapsed = std.time.nanoTimestamp() - start;
                if (elapsed >= timeout_ns) {
                    return .failure;
                }
            }

            // Park (wait)
            _ = self.bits.cmpxchgWeak(v, v | HAS_PARKED, .relaxed, .relaxed);
            self.park(timeout_ns, start);
        }
    }

    fn park(self: *Self, timeout_ns: i64, start: i128) void {
        _ = self;
        // Simple sleep-based parking
        if (timeout_ns < 0) {
            std.time.sleep(1000); // 1us
        } else {
            const elapsed = std.time.nanoTimestamp() - start;
            const remaining = timeout_ns - @as(i64, @intCast(@min(elapsed, std.math.maxInt(i64))));
            if (remaining > 0) {
                std.time.sleep(@min(@as(u64, @intCast(remaining)), 1000));
            }
        }
    }

    fn wakeOne(self: *Self) void {
        _ = self;
        // In a real implementation, this would wake a parked thread
    }

    /// Check if locked
    pub fn isLocked(self: *Self) bool {
        return self.bits.load(.relaxed) & LOCKED != 0;
    }
};

// ============================================================================
// Once - One-time Initialization
// ============================================================================

/// Ensures code runs exactly once
pub const Once = struct {
    state: Atomic(u8) = Atomic(u8).init(0),

    const UNINITIALIZED: u8 = 0;
    const INITIALIZING: u8 = 1;
    const INITIALIZED: u8 = 2;

    const Self = @This();

    /// Call the function once
    pub fn callOnce(self: *Self, comptime func: fn () void) void {
        if (self.state.load(.acquire) == INITIALIZED) {
            return;
        }

        self.callOnceSlow(func);
    }

    fn callOnceSlow(self: *Self, comptime func: fn () void) void {
        var expected: u8 = UNINITIALIZED;
        if (self.state.cmpxchgStrong(expected, INITIALIZING, .acquire, .relaxed) == null) {
            // We won the race - initialize
            func();
            self.state.store(INITIALIZED, .release);
            return;
        }

        // Another thread is initializing - wait
        while (self.state.load(.acquire) != INITIALIZED) {
            yield();
        }
    }

    /// Reset to uninitialized state
    pub fn reset(self: *Self) void {
        self.state.store(UNINITIALIZED, .release);
    }

    /// Check if initialized
    pub fn isInitialized(self: *Self) bool {
        return self.state.load(.acquire) == INITIALIZED;
    }
};

// ============================================================================
// Event - Simple Event Flag
// ============================================================================

/// Simple event for signaling between threads
pub const Event = struct {
    set: Atomic(bool) = Atomic(bool).init(false),

    const Self = @This();

    /// Wait for event to be set
    pub fn wait(self: *Self) void {
        while (!self.set.load(.acquire)) {
            yield();
        }
    }

    /// Wait with timeout (returns true if set, false if timeout)
    pub fn timedWait(self: *Self, timeout_ns: i64) bool {
        if (timeout_ns < 0) {
            self.wait();
            return true;
        }

        const start = std.time.nanoTimestamp();
        while (!self.set.load(.acquire)) {
            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return false;
            }
            yield();
        }
        return true;
    }

    /// Set the event (wake all waiters)
    pub fn set(self: *Self) void {
        self.set.store(true, .release);
    }

    /// Reset the event
    pub fn reset(self: *Self) void {
        self.set.store(false, .release);
    }

    /// Check if set
    pub fn isSet(self: *Self) bool {
        return self.set.load(.acquire);
    }
};

// ============================================================================
// RWLock - Reader-Writer Lock
// ============================================================================

/// Reader-writer lock allowing multiple readers or single writer
pub const RWLock = struct {
    state: Atomic(i32) = Atomic(i32).init(0),

    const WRITER: i32 = -1;

    const Self = @This();

    /// Acquire read lock
    pub fn readLock(self: *Self) void {
        while (true) {
            const state = self.state.load(.acquire);
            if (state >= 0) {
                if (self.state.cmpxchgWeak(state, state + 1, .acquire, .relaxed) == null) {
                    return;
                }
            } else {
                yield();
            }
        }
    }

    /// Release read lock
    pub fn readUnlock(self: *Self) void {
        _ = self.state.fetchSub(1, .release);
    }

    /// Acquire write lock
    pub fn writeLock(self: *Self) void {
        while (true) {
            var expected: i32 = 0;
            if (self.state.cmpxchgWeak(expected, WRITER, .acquire, .relaxed) == null) {
                return;
            }
            yield();
        }
    }

    /// Release write lock
    pub fn writeUnlock(self: *Self) void {
        self.state.store(0, .release);
    }

    /// Try to acquire read lock
    pub fn tryReadLock(self: *Self) bool {
        const state = self.state.load(.acquire);
        if (state >= 0) {
            return self.state.cmpxchgWeak(state, state + 1, .acquire, .relaxed) == null;
        }
        return false;
    }

    /// Try to acquire write lock
    pub fn tryWriteLock(self: *Self) bool {
        var expected: i32 = 0;
        return self.state.cmpxchgWeak(expected, WRITER, .acquire, .relaxed) == null;
    }
};

// ============================================================================
// Recursive Mutex
// ============================================================================

/// Mutex that can be locked multiple times by the same thread
pub const RecursiveMutex = struct {
    mutex: PyMutex = .{},
    owner: Atomic(?std.Thread.Id) = Atomic(?std.Thread.Id).init(null),
    count: u32 = 0,

    const Self = @This();

    /// Lock (can be called multiple times by owner)
    pub fn lock(self: *Self) void {
        const tid = std.Thread.getCurrentId();

        if (self.owner.load(.relaxed) == tid) {
            self.count += 1;
            return;
        }

        self.mutex.lock();
        self.owner.store(tid, .relaxed);
        self.count = 1;
    }

    /// Unlock
    pub fn unlock(self: *Self) void {
        self.count -= 1;
        if (self.count == 0) {
            self.owner.store(null, .relaxed);
            self.mutex.unlock();
        }
    }

    /// Try lock
    pub fn tryLock(self: *Self) bool {
        const tid = std.Thread.getCurrentId();

        if (self.owner.load(.relaxed) == tid) {
            self.count += 1;
            return true;
        }

        if (self.mutex.tryLock()) {
            self.owner.store(tid, .relaxed);
            self.count = 1;
            return true;
        }
        return false;
    }
};

// ============================================================================
// Critical Section
// ============================================================================

/// Critical section for protecting code regions
pub const CriticalSection = struct {
    mutex: PyMutex = .{},
    prev: ?*CriticalSection = null,

    const Self = @This();

    /// Begin critical section
    pub fn begin(self: *Self, prev: ?*CriticalSection) void {
        self.prev = prev;
        self.mutex.lock();
    }

    /// End critical section
    pub fn end(self: *Self) ?*CriticalSection {
        const prev = self.prev;
        self.mutex.unlock();
        return prev;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Yield to other threads
fn yield() void {
    if (builtin.os.tag == .windows) {
        // SwitchToThread equivalent
        std.time.sleep(0);
    } else {
        // sched_yield equivalent
        std.time.sleep(0);
    }
}

/// At fork reinitialization
pub fn atForkReinit(mutex: *PyMutex) void {
    mutex.bits.store(0, .relaxed);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "mutex basic" {
    var mutex = PyMutex{};

    mutex.lock();
    try std.testing.expect(mutex.isLocked());

    mutex.unlock();
    try std.testing.expect(!mutex.isLocked());
}

test "mutex trylock" {
    var mutex = PyMutex{};

    try std.testing.expect(mutex.tryLock());
    try std.testing.expect(mutex.isLocked());

    // Same thread can't tryLock again (non-recursive)
    mutex.unlock();
    try std.testing.expect(!mutex.isLocked());
}

test "once" {
    var once = Once{};
    var count: u32 = 0;

    const increment = struct {
        fn inc() void {
            // Can't easily modify outer count, but test structure
        }
    }.inc;

    once.callOnce(increment);
    once.callOnce(increment);

    try std.testing.expect(once.isInitialized());
    _ = count;
}

test "event" {
    var event = Event{};

    try std.testing.expect(!event.isSet());

    event.set();
    try std.testing.expect(event.isSet());

    event.reset();
    try std.testing.expect(!event.isSet());
}

test "rwlock readers" {
    var rwlock = RWLock{};

    // Multiple readers allowed
    rwlock.readLock();
    try std.testing.expect(rwlock.tryReadLock());
    rwlock.readUnlock();
    rwlock.readUnlock();
}

test "rwlock writer" {
    var rwlock = RWLock{};

    rwlock.writeLock();
    // Can't get read lock while writing
    try std.testing.expect(!rwlock.tryReadLock());
    rwlock.writeUnlock();

    // Now can read
    try std.testing.expect(rwlock.tryReadLock());
    rwlock.readUnlock();
}

test "recursive mutex" {
    var rmutex = RecursiveMutex{};

    rmutex.lock();
    rmutex.lock(); // Should not deadlock
    rmutex.lock();

    rmutex.unlock();
    rmutex.unlock();
    rmutex.unlock();
}
