/// pymutex - Lightweight Mutex Implementation
/// Provides PyMutex with spinning and parking support

const std = @import("std");
const Atomic = std.atomic.Value;
const helpers = @import("helpers.zig");

// Re-export from helpers
const LOCKED = helpers.LOCKED;
const HAS_PARKED = helpers.HAS_PARKED;
const MAX_SPIN_COUNT = helpers.MAX_SPIN_COUNT;

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
                helpers.yield();
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
        // Use futex to wake a parked thread (Linux) or broadcast condition (portable)
        // This uses Zig's std.Thread.Futex for cross-platform thread waking
        const wake_addr: *const Atomic(u32) = @ptrCast(&self.bits);
        std.Thread.Futex.wake(wake_addr, 1);
    }

    /// Check if locked
    pub fn isLocked(self: *Self) bool {
        return self.bits.load(.relaxed) & LOCKED != 0;
    }
};

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
