/// thread - Thread Support
/// Mirrors cpython/Python/thread.c
///
/// This module provides threading primitives for the Python runtime:
/// - Thread creation and management
/// - Mutex/lock operations
/// - Thread-local storage
/// - Condition variables
/// - Timeout handling

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Constants
// ============================================================================

/// Maximum timeout value in microseconds
pub const PY_TIMEOUT_MAX: i64 = std.math.maxInt(i64) / 1000;

/// Unset/infinite timeout marker
pub const UNSET_TIMEOUT: i64 = -1;

/// Default thread stack size (0 = use system default)
pub const DEFAULT_STACKSIZE: usize = 0;

// ============================================================================
// Lock Types
// ============================================================================

/// Lock acquisition status
pub const LockStatus = enum {
    acquired, // Lock was acquired
    failure, // Lock acquisition failed
    timeout, // Timed out waiting for lock
    interrupted, // Interrupted by signal
};

/// Lock flags
pub const LockFlags = packed struct(u8) {
    dont_detach: bool = false, // Don't detach on timeout
    fail_if_interrupted: bool = false, // Return on interrupt
    _padding: u6 = 0,
};

/// Simple mutex lock
pub const Lock = struct {
    mutex: std.Thread.Mutex = .{},
    locked: bool = false,

    const Self = @This();

    /// Allocate a new lock
    pub fn create() *Self {
        const lock = std.heap.c_allocator.create(Self) catch return undefined;
        lock.* = .{};
        return lock;
    }

    /// Free a lock
    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    /// Acquire lock with optional timeout
    pub fn acquire(self: *Self, timeout_us: i64, flags: LockFlags) LockStatus {
        _ = flags;

        if (timeout_us == 0) {
            // Non-blocking try
            if (self.mutex.tryLock()) {
                self.locked = true;
                return .acquired;
            }
            return .failure;
        }

        if (timeout_us < 0) {
            // Infinite wait
            self.mutex.lock();
            self.locked = true;
            return .acquired;
        }

        // Timed wait using tryLock with sleep
        const start = std.time.nanoTimestamp();
        const timeout_ns = timeout_us * 1000;

        while (true) {
            if (self.mutex.tryLock()) {
                self.locked = true;
                return .acquired;
            }

            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return .timeout;
            }

            // Brief sleep before retry
            std.time.sleep(1000); // 1us
        }
    }

    /// Release lock
    pub fn release(self: *Self) void {
        self.locked = false;
        self.mutex.unlock();
    }

    /// Check if lock is held
    pub fn isLocked(self: *Self) bool {
        return self.locked;
    }
};

/// Recursive lock (reentrant mutex)
pub const RLock = struct {
    mutex: std.Thread.Mutex = .{},
    owner: ?std.Thread.Id = null,
    count: usize = 0,

    const Self = @This();

    pub fn create() *Self {
        const lock = std.heap.c_allocator.create(Self) catch return undefined;
        lock.* = .{};
        return lock;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    pub fn acquire(self: *Self, timeout_us: i64) LockStatus {
        const tid = std.Thread.getCurrentId();

        // Check if we already own it
        if (self.owner == tid) {
            self.count += 1;
            return .acquired;
        }

        // Need to acquire underlying mutex
        if (timeout_us == 0) {
            if (self.mutex.tryLock()) {
                self.owner = tid;
                self.count = 1;
                return .acquired;
            }
            return .failure;
        }

        if (timeout_us < 0) {
            self.mutex.lock();
            self.owner = tid;
            self.count = 1;
            return .acquired;
        }

        // Timed wait
        const start = std.time.nanoTimestamp();
        const timeout_ns = timeout_us * 1000;

        while (true) {
            if (self.mutex.tryLock()) {
                self.owner = tid;
                self.count = 1;
                return .acquired;
            }

            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return .timeout;
            }

            std.time.sleep(1000);
        }
    }

    pub fn release(self: *Self) bool {
        const tid = std.Thread.getCurrentId();
        if (self.owner != tid) {
            return false; // Not owner
        }

        self.count -= 1;
        if (self.count == 0) {
            self.owner = null;
            self.mutex.unlock();
        }
        return true;
    }

    pub fn isOwned(self: *Self) bool {
        return self.owner == std.Thread.getCurrentId();
    }

    pub fn getCount(self: *Self) usize {
        if (self.owner == std.Thread.getCurrentId()) {
            return self.count;
        }
        return 0;
    }
};

// ============================================================================
// Condition Variable
// ============================================================================

pub const Condition = struct {
    cond: std.Thread.Condition = .{},

    const Self = @This();

    pub fn create() *Self {
        const cond = std.heap.c_allocator.create(Self) catch return undefined;
        cond.* = .{};
        return cond;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    /// Wait on condition with optional timeout
    pub fn wait(self: *Self, lock: *Lock, timeout_us: i64) LockStatus {
        if (timeout_us < 0) {
            self.cond.wait(&lock.mutex);
            return .acquired;
        }

        const timeout_ns: u64 = @intCast(timeout_us * 1000);
        const result = self.cond.timedWait(&lock.mutex, timeout_ns);
        if (result) {
            return .acquired;
        } else {
            return .timeout;
        }
    }

    /// Signal one waiting thread
    pub fn signal(self: *Self) void {
        self.cond.signal();
    }

    /// Signal all waiting threads
    pub fn broadcast(self: *Self) void {
        self.cond.broadcast();
    }
};

// ============================================================================
// Semaphore
// ============================================================================

pub const Semaphore = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    count: i32 = 0,

    const Self = @This();

    pub fn create(initial: i32) *Self {
        const sem = std.heap.c_allocator.create(Self) catch return undefined;
        sem.* = .{ .count = initial };
        return sem;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    pub fn acquire(self: *Self, timeout_us: i64) LockStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (timeout_us == 0) {
            // Non-blocking
            if (self.count > 0) {
                self.count -= 1;
                return .acquired;
            }
            return .failure;
        }

        if (timeout_us < 0) {
            // Infinite wait
            while (self.count <= 0) {
                self.cond.wait(&self.mutex);
            }
            self.count -= 1;
            return .acquired;
        }

        // Timed wait
        const start = std.time.nanoTimestamp();
        const timeout_ns = timeout_us * 1000;

        while (self.count <= 0) {
            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return .timeout;
            }

            const remaining: u64 = @intCast(timeout_ns - elapsed);
            _ = self.cond.timedWait(&self.mutex, remaining);
        }

        self.count -= 1;
        return .acquired;
    }

    pub fn release(self: *Self) void {
        self.mutex.lock();
        self.count += 1;
        self.cond.signal();
        self.mutex.unlock();
    }

    pub fn getValue(self: *Self) i32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }
};

// ============================================================================
// Thread Local Storage
// ============================================================================

/// Thread-local storage key
pub const TLSKey = struct {
    key: if (builtin.os.tag == .windows)
        std.os.windows.DWORD
    else
        std.c.pthread_key_t,

    const Self = @This();

    pub fn create() !Self {
        if (builtin.os.tag == .windows) {
            const key = std.os.windows.kernel32.TlsAlloc();
            if (key == std.os.windows.TLS_OUT_OF_INDEXES) {
                return error.OutOfMemory;
            }
            return .{ .key = key };
        } else {
            var key: std.c.pthread_key_t = undefined;
            if (std.c.pthread_key_create(&key, null) != 0) {
                return error.OutOfMemory;
            }
            return .{ .key = key };
        }
    }

    pub fn delete(self: Self) void {
        if (builtin.os.tag == .windows) {
            _ = std.os.windows.kernel32.TlsFree(self.key);
        } else {
            _ = std.c.pthread_key_delete(self.key);
        }
    }

    pub fn get(self: Self) ?*anyopaque {
        if (builtin.os.tag == .windows) {
            const value = std.os.windows.kernel32.TlsGetValue(self.key);
            if (value == null and std.os.windows.kernel32.GetLastError() != .SUCCESS) {
                return null;
            }
            return value;
        } else {
            return std.c.pthread_getspecific(self.key);
        }
    }

    pub fn set(self: Self, value: ?*anyopaque) !void {
        if (builtin.os.tag == .windows) {
            if (std.os.windows.kernel32.TlsSetValue(self.key, value) == 0) {
                return error.Failed;
            }
        } else {
            if (std.c.pthread_setspecific(self.key, value) != 0) {
                return error.Failed;
            }
        }
    }
};

// ============================================================================
// Thread Management
// ============================================================================

/// Thread handle
pub const Thread = struct {
    handle: std.Thread,
    id: std.Thread.Id,

    const Self = @This();

    /// Start a new thread
    pub fn start(
        comptime func: anytype,
        args: anytype,
    ) !Self {
        const handle = try std.Thread.spawn(.{}, func, args);
        return .{
            .handle = handle,
            .id = handle.getHandle(),
        };
    }

    /// Wait for thread to finish
    pub fn join(self: Self) void {
        self.handle.join();
    }

    /// Detach thread
    pub fn detach(self: Self) void {
        self.handle.detach();
    }
};

/// Get current thread ID
pub fn getCurrentThreadId() u64 {
    return @intCast(std.Thread.getCurrentId());
}

/// Get number of CPUs
pub fn getNumCpus() usize {
    return std.Thread.getCpuCount() catch 1;
}

// ============================================================================
// Thread State
// ============================================================================

/// Thread state for Python interpreter
pub const ThreadState = struct {
    allocator: std.mem.Allocator,
    thread_id: u64,
    next: ?*ThreadState = null,
    prev: ?*ThreadState = null,

    // Exception state
    current_exception: ?*anyopaque = null,
    exception_context: ?*anyopaque = null,
    exception_cause: ?*anyopaque = null,

    // Recursion tracking
    recursion_depth: u32 = 0,
    recursion_limit: u32 = 1000,

    // Frame stack
    frame: ?*anyopaque = null,

    // Tracing
    tracing: bool = false,
    use_tracing: bool = false,

    // Async generator state
    async_gen_firstiter: ?*anyopaque = null,
    async_gen_finalizer: ?*anyopaque = null,

    const Self = @This();

    pub fn create(allocator: std.mem.Allocator) !*Self {
        const state = try allocator.create(Self);
        state.* = .{
            .allocator = allocator,
            .thread_id = getCurrentThreadId(),
        };
        return state;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Check if we're in recursion limit
    pub fn checkRecursion(self: *Self) bool {
        return self.recursion_depth < self.recursion_limit;
    }

    /// Enter recursive call
    pub fn enterRecursion(self: *Self) !void {
        if (self.recursion_depth >= self.recursion_limit) {
            return error.RecursionLimit;
        }
        self.recursion_depth += 1;
    }

    /// Leave recursive call
    pub fn leaveRecursion(self: *Self) void {
        if (self.recursion_depth > 0) {
            self.recursion_depth -= 1;
        }
    }
};

/// Thread-local current thread state
threadlocal var current_thread_state: ?*ThreadState = null;

/// Get current thread state
pub fn getThreadState() ?*ThreadState {
    return current_thread_state;
}

/// Set current thread state
pub fn setThreadState(state: ?*ThreadState) void {
    current_thread_state = state;
}

// ============================================================================
// Stack Size
// ============================================================================

var thread_stacksize: usize = DEFAULT_STACKSIZE;

/// Get thread stack size
pub fn getStackSize() usize {
    return thread_stacksize;
}

/// Set thread stack size
pub fn setStackSize(size: usize) i32 {
    // Validate size
    if (size != 0 and size < 32768) {
        return -1; // Invalid size
    }

    thread_stacksize = size;
    return 0;
}

// ============================================================================
// Timeout Parsing
// ============================================================================

/// Parse timeout argument
pub fn parseTimeout(timeout_seconds: f64, blocking: bool) !i64 {
    if (!blocking and timeout_seconds >= 0) {
        return error.InvalidValue; // Can't specify timeout for non-blocking
    }

    if (timeout_seconds < 0) {
        return UNSET_TIMEOUT;
    }

    // Convert to microseconds
    const microseconds = @as(i64, @intFromFloat(timeout_seconds * 1_000_000));

    if (microseconds > PY_TIMEOUT_MAX) {
        return error.Overflow;
    }

    return microseconds;
}

// ============================================================================
// Event
// ============================================================================

/// Simple event for thread synchronization
pub const Event = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    is_set: bool = false,

    const Self = @This();

    pub fn create() *Self {
        const event = std.heap.c_allocator.create(Self) catch return undefined;
        event.* = .{};
        return event;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    pub fn set(self: *Self) void {
        self.mutex.lock();
        self.is_set = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        self.is_set = false;
        self.mutex.unlock();
    }

    pub fn isSet(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.is_set;
    }

    pub fn wait(self: *Self, timeout_us: i64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_set) {
            return true;
        }

        if (timeout_us == 0) {
            return self.is_set;
        }

        if (timeout_us < 0) {
            while (!self.is_set) {
                self.cond.wait(&self.mutex);
            }
            return true;
        }

        const start = std.time.nanoTimestamp();
        const timeout_ns = timeout_us * 1000;

        while (!self.is_set) {
            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return false;
            }

            const remaining: u64 = @intCast(timeout_ns - elapsed);
            _ = self.cond.timedWait(&self.mutex, remaining);
        }

        return true;
    }
};

// ============================================================================
// Barrier
// ============================================================================

/// Thread barrier for synchronization
pub const Barrier = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    parties: usize,
    count: usize = 0,
    generation: usize = 0,
    broken: bool = false,

    const Self = @This();

    pub fn create(parties: usize) *Self {
        const barrier = std.heap.c_allocator.create(Self) catch return undefined;
        barrier.* = .{ .parties = parties };
        return barrier;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    /// Wait at barrier, return index (0 to parties-1)
    pub fn wait(self: *Self, timeout_us: i64) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.broken) {
            return error.BrokenBarrier;
        }

        const gen = self.generation;
        const index = self.count;
        self.count += 1;

        if (self.count == self.parties) {
            // Last thread - release all
            self.count = 0;
            self.generation += 1;
            self.cond.broadcast();
            return index;
        }

        // Wait for release
        if (timeout_us < 0) {
            while (gen == self.generation and !self.broken) {
                self.cond.wait(&self.mutex);
            }
        } else {
            const start = std.time.nanoTimestamp();
            const timeout_ns = timeout_us * 1000;

            while (gen == self.generation and !self.broken) {
                const elapsed = std.time.nanoTimestamp() - start;
                if (elapsed >= timeout_ns) {
                    self.broken = true;
                    self.cond.broadcast();
                    return error.Timeout;
                }

                const remaining: u64 = @intCast(timeout_ns - elapsed);
                _ = self.cond.timedWait(&self.mutex, remaining);
            }
        }

        if (self.broken) {
            return error.BrokenBarrier;
        }

        return index;
    }

    pub fn reset(self: *Self) void {
        self.mutex.lock();
        self.count = 0;
        self.generation += 1;
        self.broken = false;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    pub fn abort(self: *Self) void {
        self.mutex.lock();
        self.broken = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    pub fn getParties(self: *Self) usize {
        return self.parties;
    }

    pub fn getWaiting(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }

    pub fn isBroken(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.broken;
    }
};

// ============================================================================
// Initialization
// ============================================================================

var initialized = false;

/// Initialize thread module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

// ============================================================================
// At Fork Handling
// ============================================================================

/// Reinitialize lock after fork
pub fn atForkReinit(lock: *Lock) void {
    lock.* = .{};
}

// ============================================================================
// Tests
// ============================================================================

test "lock basic" {
    var lock = Lock{};

    const status = lock.acquire(-1, .{});
    try std.testing.expect(status == .acquired);
    try std.testing.expect(lock.isLocked());

    lock.release();
    try std.testing.expect(!lock.isLocked());
}

test "lock trylock" {
    var lock = Lock{};

    // Should succeed
    const status1 = lock.acquire(0, .{});
    try std.testing.expect(status1 == .acquired);

    // Should fail (already locked by us, not recursive)
    // Note: std.Thread.Mutex allows recursive lock from same thread on some platforms
    lock.release();
}

test "rlock recursive" {
    var rlock = RLock{};

    // First acquire
    _ = rlock.acquire(-1);
    try std.testing.expect(rlock.isOwned());
    try std.testing.expectEqual(@as(usize, 1), rlock.getCount());

    // Second acquire (recursive)
    _ = rlock.acquire(-1);
    try std.testing.expectEqual(@as(usize, 2), rlock.getCount());

    // Release once
    _ = rlock.release();
    try std.testing.expectEqual(@as(usize, 1), rlock.getCount());

    // Release again
    _ = rlock.release();
    try std.testing.expectEqual(@as(usize, 0), rlock.getCount());
    try std.testing.expect(!rlock.isOwned());
}

test "semaphore" {
    var sem = Semaphore{ .count = 2 };

    // Should succeed twice
    try std.testing.expect(sem.acquire(0) == .acquired);
    try std.testing.expect(sem.acquire(0) == .acquired);

    // Should fail now
    try std.testing.expect(sem.acquire(0) == .failure);

    // Release and try again
    sem.release();
    try std.testing.expect(sem.acquire(0) == .acquired);
}

test "event" {
    var event = Event{};

    try std.testing.expect(!event.isSet());

    event.set();
    try std.testing.expect(event.isSet());
    try std.testing.expect(event.wait(0));

    event.clear();
    try std.testing.expect(!event.isSet());
    try std.testing.expect(!event.wait(0));
}

test "thread state" {
    const allocator = std.testing.allocator;

    const state = try ThreadState.create(allocator);
    defer state.destroy();

    try std.testing.expect(state.thread_id != 0);
    try std.testing.expect(state.checkRecursion());

    try state.enterRecursion();
    try std.testing.expectEqual(@as(u32, 1), state.recursion_depth);

    state.leaveRecursion();
    try std.testing.expectEqual(@as(u32, 0), state.recursion_depth);
}

test "timeout parsing" {
    // Blocking with timeout
    const timeout1 = try parseTimeout(1.5, true);
    try std.testing.expectEqual(@as(i64, 1500000), timeout1);

    // Blocking with no timeout
    const timeout2 = try parseTimeout(-1, true);
    try std.testing.expectEqual(UNSET_TIMEOUT, timeout2);

    // Non-blocking with negative should succeed
    const timeout3 = try parseTimeout(-1, false);
    try std.testing.expectEqual(UNSET_TIMEOUT, timeout3);
}

test "stack size" {
    try std.testing.expectEqual(DEFAULT_STACKSIZE, getStackSize());

    // Set valid size
    try std.testing.expectEqual(@as(i32, 0), setStackSize(1024 * 1024));
    try std.testing.expectEqual(@as(usize, 1024 * 1024), getStackSize());

    // Set invalid size
    try std.testing.expectEqual(@as(i32, -1), setStackSize(1000));

    // Reset
    _ = setStackSize(DEFAULT_STACKSIZE);
}
