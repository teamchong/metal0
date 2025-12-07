//! Python 'threading' module - Thread-based parallelism
//!
//! Provides higher-level threading interface built on top of std.Thread.
//!
//! Mirrors: CPython Lib/threading.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default stack size (0 = use system default)
pub const STACK_SIZE = 0;

/// Timeout sentinel value
pub const TIMEOUT_MAX: f64 = std.math.floatMax(f64);

// ============================================================================
// Thread - A class representing a thread of control
// ============================================================================

/// A class that represents a thread of control
pub const Thread = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    daemon: bool,
    ident: ?std.Thread.Id,
    native_id: ?std.Thread.Id,
    started: bool,
    stopped: bool,
    thread: ?std.Thread,
    target: ?*const fn () void,

    /// Thread-local exception info (simplified)
    exc_info: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .daemon = false,
            .ident = null,
            .native_id = null,
            .started = false,
            .stopped = false,
            .thread = null,
            .target = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Start the thread's activity
    pub fn start(self: *Self) !void {
        if (self.started) return error.ThreadAlreadyStarted;

        self.started = true;
        self.thread = try std.Thread.spawn(.{}, threadRunner, .{self});
        self.ident = self.thread.?.getCurrentId();
        self.native_id = self.ident;
    }

    fn threadRunner(thread_obj: *Self) void {
        if (thread_obj.target) |target| {
            target();
        } else {
            thread_obj.run();
        }
        thread_obj.stopped = true;
    }

    /// Method representing the thread's activity (override in subclass)
    pub fn run(self: *Self) void {
        _ = self;
        // Default implementation does nothing
    }

    /// Wait until the thread terminates
    pub fn join(self: *Self, timeout: ?f64) !void {
        if (!self.started) return error.ThreadNotStarted;

        if (timeout) |t| {
            // Timed join (simplified - just sleep and check)
            const ns = @as(u64, @intFromFloat(t * std.time.ns_per_s));
            _ = ns;
            // For simplicity, just do blocking join
        }

        if (self.thread) |*t| {
            t.join();
            self.thread = null;
        }
    }

    /// Return whether the thread is alive
    pub fn isAlive(self: *Self) bool {
        return self.started and !self.stopped;
    }

    /// Return the thread's name
    pub fn getName(self: *Self) []const u8 {
        return self.name;
    }

    /// Set the thread's name
    pub fn setName(self: *Self, name: []const u8) void {
        self.name = name;
    }

    /// Return whether this is a daemon thread
    pub fn isDaemon(self: *Self) bool {
        return self.daemon;
    }

    /// Set whether this is a daemon thread
    pub fn setDaemon(self: *Self, daemon: bool) void {
        if (self.started) return; // Cannot change after start
        self.daemon = daemon;
    }
};

// ============================================================================
// Lock - Primitive lock
// ============================================================================

/// A factory function that returns a new primitive lock object
pub const Lock = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    locked: bool,

    pub fn init() Self {
        return .{
            .mutex = .{},
            .locked = false,
        };
    }

    /// Acquire the lock
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        _ = timeout; // Simplified - ignore timeout

        if (blocking) {
            self.mutex.lock();
            self.locked = true;
            return true;
        } else {
            if (self.mutex.tryLock()) {
                self.locked = true;
                return true;
            }
            return false;
        }
    }

    /// Release the lock
    pub fn release(self: *Self) void {
        self.locked = false;
        self.mutex.unlock();
    }

    /// Check if lock is held
    pub fn isLocked(self: *Self) bool {
        return self.locked;
    }

    /// Check if lock is held (alias)
    pub fn locked_status(self: *Self) bool {
        return self.locked;
    }
};

// ============================================================================
// RLock - Reentrant lock
// ============================================================================

/// A reentrant lock
pub const RLock = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    owner: ?std.Thread.Id,
    count: usize,

    pub fn init() Self {
        return .{
            .mutex = .{},
            .owner = null,
            .count = 0,
        };
    }

    /// Acquire the lock
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        _ = timeout;

        const current = std.Thread.getCurrentId();

        if (self.owner == current) {
            self.count += 1;
            return true;
        }

        if (blocking) {
            self.mutex.lock();
            self.owner = current;
            self.count = 1;
            return true;
        } else {
            if (self.mutex.tryLock()) {
                self.owner = current;
                self.count = 1;
                return true;
            }
            return false;
        }
    }

    /// Release the lock
    pub fn release(self: *Self) !void {
        const current = std.Thread.getCurrentId();
        if (self.owner != current) return error.NotOwner;

        self.count -= 1;
        if (self.count == 0) {
            self.owner = null;
            self.mutex.unlock();
        }
    }

    /// Check if lock is owned by current thread
    pub fn isOwned(self: *Self) bool {
        return self.owner == std.Thread.getCurrentId();
    }
};

// ============================================================================
// Condition - Condition variable
// ============================================================================

/// A condition variable
pub const Condition = struct {
    const Self = @This();

    lock: *Lock,
    waiters: std.ArrayList(*std.Thread.Condition),
    allocator: std.mem.Allocator,
    internal_cond: std.Thread.Condition,

    pub fn init(allocator: std.mem.Allocator, lock: ?*Lock) !Self {
        const l = lock orelse blk: {
            const new_lock = try allocator.create(Lock);
            new_lock.* = Lock.init();
            break :blk new_lock;
        };

        return .{
            .allocator = allocator,
            .lock = l,
            .waiters = std.ArrayList(*std.Thread.Condition).init(allocator),
            .internal_cond = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.waiters.deinit();
    }

    /// Acquire the underlying lock
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        return self.lock.acquire(blocking, timeout);
    }

    /// Release the underlying lock
    pub fn release(self: *Self) void {
        self.lock.release();
    }

    /// Wait until notified
    pub fn wait(self: *Self, timeout: ?f64) bool {
        _ = timeout;
        self.internal_cond.wait(&self.lock.mutex);
        return true;
    }

    /// Wait until a predicate becomes true
    pub fn waitFor(self: *Self, predicate: *const fn () bool, timeout: ?f64) bool {
        _ = timeout;
        while (!predicate()) {
            self.internal_cond.wait(&self.lock.mutex);
        }
        return true;
    }

    /// Wake up one waiting thread
    pub fn notify(self: *Self) void {
        self.internal_cond.signal();
    }

    /// Wake up all waiting threads
    pub fn notifyAll(self: *Self) void {
        self.internal_cond.broadcast();
    }
};

// ============================================================================
// Semaphore - Counting semaphore
// ============================================================================

/// A semaphore
pub const Semaphore = struct {
    const Self = @This();

    value: i32,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init(value: i32) Self {
        return .{
            .value = value,
            .mutex = .{},
            .cond = .{},
        };
    }

    /// Acquire the semaphore
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        _ = timeout;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (blocking) {
            while (self.value <= 0) {
                self.cond.wait(&self.mutex);
            }
            self.value -= 1;
            return true;
        } else {
            if (self.value > 0) {
                self.value -= 1;
                return true;
            }
            return false;
        }
    }

    /// Release the semaphore
    pub fn release(self: *Self, n: i32) void {
        self.mutex.lock();
        self.value += n;
        if (n == 1) {
            self.cond.signal();
        } else {
            self.cond.broadcast();
        }
        self.mutex.unlock();
    }

    /// Return the current value
    pub fn getValue(self: *Self) i32 {
        return self.value;
    }
};

// ============================================================================
// BoundedSemaphore - Bounded counting semaphore
// ============================================================================

/// A bounded semaphore that raises error if released too many times
pub const BoundedSemaphore = struct {
    const Self = @This();

    sem: Semaphore,
    initial_value: i32,

    pub fn init(value: i32) Self {
        return .{
            .sem = Semaphore.init(value),
            .initial_value = value,
        };
    }

    /// Acquire the semaphore
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        return self.sem.acquire(blocking, timeout);
    }

    /// Release the semaphore
    pub fn release(self: *Self) !void {
        if (self.sem.value >= self.initial_value) {
            return error.BoundedSemaphoreOverflow;
        }
        self.sem.release(1);
    }
};

// ============================================================================
// Event - Thread event
// ============================================================================

/// A thread event
pub const Event = struct {
    const Self = @This();

    flag: bool,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init() Self {
        return .{
            .flag = false,
            .mutex = .{},
            .cond = .{},
        };
    }

    /// Return true if the internal flag is true
    pub fn isSet(self: *Self) bool {
        return self.flag;
    }

    /// Set the internal flag to true
    pub fn set(self: *Self) void {
        self.mutex.lock();
        self.flag = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    /// Reset the internal flag to false
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        self.flag = false;
        self.mutex.unlock();
    }

    /// Block until the internal flag is true
    pub fn wait(self: *Self, timeout: ?f64) bool {
        _ = timeout;

        self.mutex.lock();
        defer self.mutex.unlock();

        while (!self.flag) {
            self.cond.wait(&self.mutex);
        }
        return true;
    }
};

// ============================================================================
// Barrier - Synchronization barrier
// ============================================================================

/// A barrier for a fixed number of threads
pub const Barrier = struct {
    const Self = @This();

    parties: usize,
    count: usize,
    generation: usize,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    broken: bool,

    pub fn init(parties: usize) Self {
        return .{
            .parties = parties,
            .count = 0,
            .generation = 0,
            .mutex = .{},
            .cond = .{},
            .broken = false,
        };
    }

    /// Wait for all parties to reach the barrier
    pub fn wait(self: *Self, timeout: ?f64) !usize {
        _ = timeout;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.broken) return error.BrokenBarrier;

        const gen = self.generation;
        self.count += 1;
        const index = self.count;

        if (self.count == self.parties) {
            // Last thread - reset and wake all
            self.count = 0;
            self.generation += 1;
            self.cond.broadcast();
            return index - 1;
        }

        // Wait for other threads
        while (gen == self.generation and !self.broken) {
            self.cond.wait(&self.mutex);
        }

        if (self.broken) return error.BrokenBarrier;
        return index - 1;
    }

    /// Reset the barrier
    pub fn reset(self: *Self) void {
        self.mutex.lock();
        self.count = 0;
        self.generation += 1;
        self.broken = false;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    /// Put the barrier into a broken state
    pub fn abort(self: *Self) void {
        self.mutex.lock();
        self.broken = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    /// Return the number of threads required
    pub fn getParties(self: *Self) usize {
        return self.parties;
    }

    /// Return the number of threads waiting
    pub fn getWaiting(self: *Self) usize {
        return self.count;
    }

    /// Return whether the barrier is broken
    pub fn isBroken(self: *Self) bool {
        return self.broken;
    }
};

// ============================================================================
// Timer - Call a function after a delay
// ============================================================================

/// A timer that calls a function after a delay
pub const Timer = struct {
    const Self = @This();

    thread: ?std.Thread,
    function: *const fn () void,
    interval: f64,
    cancelled: bool,
    finished: bool,

    pub fn init(interval: f64, function: *const fn () void) Self {
        return .{
            .thread = null,
            .function = function,
            .interval = interval,
            .cancelled = false,
            .finished = false,
        };
    }

    /// Start the timer
    pub fn start(self: *Self) !void {
        self.thread = try std.Thread.spawn(.{}, timerRunner, .{self});
    }

    fn timerRunner(timer: *Self) void {
        const ns = @as(u64, @intFromFloat(timer.interval * std.time.ns_per_s));
        std.time.sleep(ns);

        if (!timer.cancelled) {
            timer.function();
        }
        timer.finished = true;
    }

    /// Cancel the timer
    pub fn cancel(self: *Self) void {
        self.cancelled = true;
    }

    /// Wait for the timer to complete
    pub fn join(self: *Self) void {
        if (self.thread) |*t| {
            t.join();
            self.thread = null;
        }
    }

    /// Check if the timer has finished
    pub fn isFinished(self: *Self) bool {
        return self.finished;
    }
};

// ============================================================================
// Thread-local storage
// ============================================================================

/// Thread-local storage
pub fn local(comptime T: type) type {
    return struct {
        const Storage = @This();

        data: std.Thread.LocalStorage(T),

        pub fn init() Storage {
            return .{ .data = .{} };
        }

        pub fn get(self: *Storage) ?*T {
            return self.data.get();
        }

        pub fn set(self: *Storage, value: T) void {
            self.data.set(value);
        }
    };
}

// ============================================================================
// Module Functions
// ============================================================================

/// Return the number of active threads
pub fn activeCount() usize {
    // Simplified - return 1 for main thread
    return 1;
}

/// Return the current thread
pub fn currentThread(allocator: std.mem.Allocator) !*Thread {
    const t = try allocator.create(Thread);
    t.* = Thread.init(allocator, "MainThread");
    t.started = true;
    t.ident = std.Thread.getCurrentId();
    return t;
}

/// Return the main thread
pub fn mainThread(allocator: std.mem.Allocator) !*Thread {
    return currentThread(allocator);
}

/// Return a list of all active threads
pub fn enumerate(allocator: std.mem.Allocator) ![]const *Thread {
    const threads = try allocator.alloc(*Thread, 1);
    threads[0] = try currentThread(allocator);
    return threads;
}

/// Return the thread identifier
pub fn getIdent() std.Thread.Id {
    return std.Thread.getCurrentId();
}

/// Return the native thread identifier
pub fn getNativeId() std.Thread.Id {
    return std.Thread.getCurrentId();
}

/// Set the stack size for new threads
pub fn setStackSize(size: usize) usize {
    _ = size;
    return STACK_SIZE;
}

/// Get the stack size for new threads
pub fn getStackSize() usize {
    return STACK_SIZE;
}

// ============================================================================
// Exception Types
// ============================================================================

pub const ThreadError = error{
    ThreadAlreadyStarted,
    ThreadNotStarted,
    NotOwner,
    BoundedSemaphoreOverflow,
    BrokenBarrier,
};

// ============================================================================
// Tests
// ============================================================================

test "Lock" {
    var lock = Lock.init();

    try std.testing.expect(lock.acquire(true, null));
    try std.testing.expect(lock.isLocked());
    lock.release();
    try std.testing.expect(!lock.isLocked());
}

test "Lock non-blocking" {
    var lock = Lock.init();

    try std.testing.expect(lock.acquire(false, null));
    try std.testing.expect(!lock.acquire(false, null)); // Already locked
    lock.release();
    try std.testing.expect(lock.acquire(false, null)); // Now available
    lock.release();
}

test "RLock" {
    var rlock = RLock.init();

    try std.testing.expect(rlock.acquire(true, null));
    try std.testing.expect(rlock.acquire(true, null)); // Reentrant
    try rlock.release();
    try rlock.release();
}

test "Semaphore" {
    var sem = Semaphore.init(2);

    try std.testing.expect(sem.acquire(true, null));
    try std.testing.expect(sem.acquire(true, null));
    try std.testing.expect(!sem.acquire(false, null)); // No more permits

    sem.release(1);
    try std.testing.expect(sem.acquire(false, null)); // Now available
    sem.release(2);
}

test "Event" {
    var event = Event.init();

    try std.testing.expect(!event.isSet());
    event.set();
    try std.testing.expect(event.isSet());
    event.clear();
    try std.testing.expect(!event.isSet());
}

test "Barrier" {
    var barrier = Barrier.init(2);

    try std.testing.expectEqual(@as(usize, 2), barrier.getParties());
    try std.testing.expectEqual(@as(usize, 0), barrier.getWaiting());
    try std.testing.expect(!barrier.isBroken());
}

test "Thread init" {
    const allocator = std.testing.allocator;

    var thread = Thread.init(allocator, "TestThread");
    defer thread.deinit();

    try std.testing.expectEqualStrings("TestThread", thread.getName());
    try std.testing.expect(!thread.isDaemon());
    try std.testing.expect(!thread.isAlive());
}

test "getIdent" {
    const id = getIdent();
    try std.testing.expect(id != 0);
}

test "activeCount" {
    try std.testing.expect(activeCount() >= 1);
}
