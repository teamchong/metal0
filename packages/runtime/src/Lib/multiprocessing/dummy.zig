//! multiprocessing.dummy - Threading-based fallback for multiprocessing
//! Reference: cpython/Lib/multiprocessing/dummy/__init__.py
//!
//! CPython __all__: Same as threading module
//!
//! Provides threading-based implementations that mimic the multiprocessing API.
//! This allows code written for multiprocessing to run using threads instead.

const std = @import("std");
const connection_mod = @import("dummy/connection.zig");

// Re-export connection
pub const Connection = connection_mod.Connection;
pub const Pipe = connection_mod.Pipe;

// ============================================================================
// Threading-based Process (DummyProcess)
// ============================================================================

/// CPython: class DummyProcess(threading.Thread)
/// A thread-based "process" for the dummy module
pub const Process = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    daemon: bool,
    target: ?*const fn () void,
    thread: ?std.Thread,
    exitcode: ?i32,
    started: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        target: ?*const fn () void,
        name: ?[]const u8,
        daemon: bool,
    ) Self {
        return .{
            .allocator = allocator,
            .name = name orelse "DummyProcess",
            .daemon = daemon,
            .target = target,
            .thread = null,
            .exitcode = null,
            .started = false,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Start the thread
    pub fn start(self: *Self) !void {
        if (self.started) {
            return error.ProcessAlreadyStarted;
        }

        if (self.target) |target_fn| {
            self.thread = try std.Thread.spawn(.{}, struct {
                fn run(func: *const fn () void) void {
                    func();
                }
            }.run, .{target_fn});
        }
        self.started = true;
    }

    /// Wait for thread to finish
    pub fn join(self: *Self, timeout: ?f64) !void {
        _ = timeout;
        if (!self.started) {
            return error.ProcessNotStarted;
        }

        if (self.thread) |thread| {
            thread.join();
            self.exitcode = 0;
            self.thread = null;
        }
    }

    /// Check if thread is alive
    pub fn isAlive(self: *Self) bool {
        if (!self.started) return false;
        if (self.exitcode != null) return false;
        return self.thread != null;
    }

    /// Terminate (no-op for threads, can't really terminate)
    pub fn terminate(self: *Self) !void {
        _ = self;
        // Threads can't be terminated like processes
    }

    /// Get exit code
    pub fn getExitcode(self: *Self) ?i32 {
        return self.exitcode;
    }
};

// ============================================================================
// Threading-based Pool (ThreadPool)
// ============================================================================

/// CPython: class Pool (ThreadPool)
pub const Pool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    processes: i32,
    closed: bool,
    terminated: bool,

    pub fn init(allocator: std.mem.Allocator, processes: ?i32) Self {
        const num_processes = processes orelse @as(i32, @intCast(std.Thread.getCpuCount() catch 1));
        return .{
            .allocator = allocator,
            .processes = num_processes,
            .closed = false,
            .terminated = false,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Apply function (blocking)
    pub fn apply(self: *Self, func: *const fn () void) !void {
        if (self.closed) return error.PoolClosed;
        func();
    }

    /// Close the pool
    pub fn close(self: *Self) void {
        self.closed = true;
    }

    /// Terminate the pool
    pub fn terminate(self: *Self) void {
        self.terminated = true;
    }

    /// Join the pool
    pub fn join(self: *Self) !void {
        if (!self.closed) return error.PoolNotClosed;
    }
};

// ============================================================================
// Synchronization Primitives (re-use threading versions)
// ============================================================================

/// CPython: Lock = threading.Lock
pub const Lock = struct {
    mutex: std.Thread.Mutex,

    pub fn init() Lock {
        return .{ .mutex = .{} };
    }

    pub fn acquire(self: *Lock, block: bool, timeout: ?f64) bool {
        _ = timeout;
        if (block) {
            self.mutex.lock();
            return true;
        } else {
            return self.mutex.tryLock();
        }
    }

    pub fn release(self: *Lock) void {
        self.mutex.unlock();
    }
};

/// CPython: RLock = threading.RLock
pub const RLock = struct {
    mutex: std.Thread.Mutex,
    owner: ?std.Thread.Id,
    count: usize,

    pub fn init() RLock {
        return .{
            .mutex = .{},
            .owner = null,
            .count = 0,
        };
    }

    pub fn acquire(self: *RLock, block: bool, timeout: ?f64) bool {
        _ = timeout;
        const tid = std.Thread.getCurrentId();

        if (self.owner == tid) {
            self.count += 1;
            return true;
        }

        if (block) {
            self.mutex.lock();
        } else {
            if (!self.mutex.tryLock()) {
                return false;
            }
        }

        self.owner = tid;
        self.count = 1;
        return true;
    }

    pub fn release(self: *RLock) void {
        if (self.owner != std.Thread.getCurrentId()) {
            return;
        }

        self.count -= 1;
        if (self.count == 0) {
            self.owner = null;
            self.mutex.unlock();
        }
    }
};

/// CPython: Event = threading.Event
pub const Event = struct {
    flag: bool,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init() Event {
        return .{
            .flag = false,
            .mutex = .{},
            .cond = .{},
        };
    }

    pub fn set(self: *Event) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flag = true;
        self.cond.broadcast();
    }

    pub fn clear(self: *Event) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flag = false;
    }

    pub fn isSet(self: *Event) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.flag;
    }

    pub fn wait(self: *Event, timeout: ?f64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.flag) return true;

        if (timeout) |t| {
            const ns = @as(u64, @intFromFloat(t * 1_000_000_000));
            self.cond.timedWait(&self.mutex, ns) catch return self.flag;
        } else {
            while (!self.flag) {
                self.cond.wait(&self.mutex);
            }
        }
        return self.flag;
    }
};

/// CPython: Semaphore = threading.Semaphore
pub const Semaphore = struct {
    value: usize,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init(value: usize) Semaphore {
        return .{
            .value = value,
            .mutex = .{},
            .cond = .{},
        };
    }

    pub fn acquire(self: *Semaphore, block: bool, timeout: ?f64) bool {
        _ = timeout;
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.value == 0) {
            if (!block) return false;
            self.cond.wait(&self.mutex);
        }

        self.value -= 1;
        return true;
    }

    pub fn release(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value += 1;
        self.cond.signal();
    }
};

/// CPython: BoundedSemaphore = threading.BoundedSemaphore
pub const BoundedSemaphore = struct {
    semaphore: Semaphore,
    initial_value: usize,

    pub fn init(value: usize) BoundedSemaphore {
        return .{
            .semaphore = Semaphore.init(value),
            .initial_value = value,
        };
    }

    pub fn acquire(self: *BoundedSemaphore, block: bool, timeout: ?f64) bool {
        return self.semaphore.acquire(block, timeout);
    }

    pub fn release(self: *BoundedSemaphore) !void {
        self.semaphore.mutex.lock();
        defer self.semaphore.mutex.unlock();

        if (self.semaphore.value >= self.initial_value) {
            return error.SemaphoreOverflow;
        }

        self.semaphore.value += 1;
        self.semaphore.cond.signal();
    }
};

/// CPython: Barrier = threading.Barrier
pub const Barrier = struct {
    parties: usize,
    count: usize,
    generation: usize,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    broken: bool,

    pub fn init(parties: usize) Barrier {
        return .{
            .parties = parties,
            .count = 0,
            .generation = 0,
            .mutex = .{},
            .cond = .{},
            .broken = false,
        };
    }

    pub fn wait(self: *Barrier, timeout: ?f64) !usize {
        _ = timeout;
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.broken) return error.BrokenBarrier;

        const gen = self.generation;
        self.count += 1;
        const index = self.parties - self.count;

        if (self.count == self.parties) {
            self.generation += 1;
            self.count = 0;
            self.cond.broadcast();
            return index;
        }

        while (gen == self.generation and !self.broken) {
            self.cond.wait(&self.mutex);
        }

        if (self.broken) return error.BrokenBarrier;
        return index;
    }

    pub fn reset(self: *Barrier) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.count = 0;
        self.generation += 1;
        self.broken = false;
        self.cond.broadcast();
    }

    pub fn abort(self: *Barrier) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.broken = true;
        self.cond.broadcast();
    }
};

// ============================================================================
// Queue (thread-safe)
// ============================================================================

/// CPython: Queue = queue.Queue
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        items: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,
        maxsize: usize,

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                .items = .{},
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .maxsize = maxsize,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        pub fn put(self: *Self, item: T, block: bool, timeout: ?f64) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.maxsize > 0 and self.items.items.len >= self.maxsize) {
                if (!block) return error.QueueFull;
                if (timeout) |t| {
                    const ns: u64 = @intFromFloat(t * std.time.ns_per_s);
                    const result = self.not_full.timedWait(&self.mutex, ns);
                    if (result == .timed_out) return error.QueueFull;
                } else {
                    self.not_full.wait(&self.mutex);
                }
            }

            try self.items.append(self.allocator, item);
            self.not_empty.signal();
        }

        pub fn get(self: *Self, block: bool, timeout: ?f64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.items.items.len == 0) {
                if (!block) return error.QueueEmpty;
                if (timeout) |t| {
                    const ns: u64 = @intFromFloat(t * std.time.ns_per_s);
                    const result = self.not_empty.timedWait(&self.mutex, ns);
                    if (result == .timed_out) return error.QueueEmpty;
                } else {
                    self.not_empty.wait(&self.mutex);
                }
            }

            const item = self.items.orderedRemove(0);
            self.not_full.signal();
            return item;
        }

        pub fn empty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len == 0;
        }

        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }
    };
}

// ============================================================================
// Module-level Functions
// ============================================================================

/// CPython: current_process()
pub fn current_process() CurrentProcess {
    return CurrentProcess{};
}

pub const CurrentProcess = struct {
    pub fn name(_: CurrentProcess) []const u8 {
        return "MainThread";
    }
};

/// CPython: active_children()
pub fn active_children() []Process {
    return &[_]Process{};
}

/// CPython: cpu_count()
pub fn cpu_count() usize {
    return std.Thread.getCpuCount() catch 1;
}

// ============================================================================
// Tests
// ============================================================================

test "dummy Process" {
    const allocator = std.testing.allocator;
    var proc = Process.init(allocator, null, "TestThread", false);
    defer proc.deinit();

    try std.testing.expectEqualStrings("TestThread", proc.name);
    try std.testing.expect(!proc.daemon);
}

test "dummy Lock" {
    var lock = Lock.init();
    try std.testing.expect(lock.acquire(true, null));
    lock.release();
}

test "dummy Event" {
    var event = Event.init();
    try std.testing.expect(!event.isSet());
    event.set();
    try std.testing.expect(event.isSet());
    event.clear();
    try std.testing.expect(!event.isSet());
}
