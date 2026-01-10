/// Python asyncio module implementation
/// Based on CPython's asyncio module structure
///
/// This is the main entry point that re-exports from submodules.
/// See: cpython/Lib/asyncio/__init__.py
const std = @import("std");

// ============================================================================
// Core Infrastructure (used by submodules)
// ============================================================================

/// Future state constants (CPython: asyncio.base_futures)
pub const FutureState = enum {
    pending,
    cancelled,
    finished,
};

/// Generic Future type
/// CPython: asyncio.Future
pub fn Future(comptime T: type) type {
    return struct {
        state: FutureState = .pending,
        result: ?T = null,
        exception: ?anyerror = null,
        callbacks: std.ArrayList(Callback) = .{},
        allocator: std.mem.Allocator,
        _asyncio_future_blocking: bool = false,

        const Self = @This();
        pub const ResultType = T;
        pub const Callback = *const fn (*Self) void;

        pub fn init(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            self.* = .{ .allocator = allocator };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.callbacks.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        pub fn done(self: *const Self) bool {
            return self.state != .pending;
        }

        pub fn cancelled(self: *const Self) bool {
            return self.state == .cancelled;
        }

        pub fn isReady(self: *const Self) bool {
            return self.state == .finished and self.result != null;
        }

        pub fn getResult(self: *const Self) !T {
            if (self.state == .cancelled) return error.Cancelled;
            if (self.exception) |e| return e;
            return self.result orelse error.InvalidState;
        }

        pub fn tryGet(self: *const Self) ?T {
            return self.result;
        }

        pub fn setResult(self: *Self, value: T) void {
            if (self.state != .pending) return;
            self.result = value;
            self.state = .finished;
            self.scheduleCallbacks();
        }

        pub fn resolve(self: *Self, value: T) void {
            self.setResult(value);
        }

        pub fn setException(self: *Self, exc: anyerror) void {
            if (self.state != .pending) return;
            self.exception = exc;
            self.state = .finished;
            self.scheduleCallbacks();
        }

        pub fn reject(self: *Self, exc: anyerror) void {
            self.setException(exc);
        }

        pub fn cancel(self: *Self) bool {
            if (self.state != .pending) return false;
            self.state = .cancelled;
            self.scheduleCallbacks();
            return true;
        }

        pub fn addDoneCallback(self: *Self, callback: Callback) !void {
            if (self.done()) {
                callback(self);
            } else {
                try self.callbacks.append(self.allocator, callback);
            }
        }

        fn scheduleCallbacks(self: *Self) void {
            for (self.callbacks.items) |cb| {
                cb(self);
            }
            self.callbacks.clearRetainingCapacity();
        }
    };
}

/// Task state (CPython: asyncio.Task states)
pub const TaskState = enum {
    pending,
    running,
    done,
    cancelled,
};

/// Task wrapping a coroutine
/// CPython: asyncio.Task
pub const Task = struct {
    id: usize,
    state: TaskState = .pending,
    name: ?[]const u8 = null,
    context: ?*anyopaque = null,
    callback: *const fn (*anyopaque) anyerror!void,
    callback_ctx: *anyopaque,

    pub fn init(id: usize, callback: *const fn (*anyopaque) anyerror!void, ctx: *anyopaque) Task {
        return .{
            .id = id,
            .callback = callback,
            .callback_ctx = ctx,
        };
    }

    pub fn done(self: *const Task) bool {
        return self.state == .done or self.state == .cancelled;
    }

    pub fn cancelled(self: *const Task) bool {
        return self.state == .cancelled;
    }

    pub fn cancel(self: *Task) bool {
        if (self.done()) return false;
        self.state = .cancelled;
        return true;
    }

    pub fn setName(self: *Task, name: []const u8) void {
        self.name = name;
    }

    pub fn getName(self: *const Task) ?[]const u8 {
        return self.name;
    }
};

// ============================================================================
// Synchronization Primitives (CPython: asyncio.locks)
// ============================================================================

/// Async Lock (mutex)
/// CPython: asyncio.Lock
pub const Lock = struct {
    locked_flag: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Lock {
        return .{ .allocator = allocator };
    }

    pub fn locked(self: *const Lock) bool {
        return self.locked_flag;
    }

    pub fn acquire(self: *Lock) void {
        // In real async, would yield until lock available
        while (self.locked_flag) {
            std.Thread.yield() catch {};
        }
        self.locked_flag = true;
    }

    pub fn release(self: *Lock) void {
        self.locked_flag = false;
    }
};

/// Async Event
/// CPython: asyncio.Event
pub const Event = struct {
    is_set_flag: bool = false,

    pub fn init() Event {
        return .{};
    }

    pub fn isSet(self: *const Event) bool {
        return self.is_set_flag;
    }

    pub fn set(self: *Event) void {
        self.is_set_flag = true;
    }

    pub fn clear(self: *Event) void {
        self.is_set_flag = false;
    }

    pub fn wait(self: *Event) void {
        while (!self.is_set_flag) {
            std.Thread.yield() catch {};
        }
    }
};

/// Async Semaphore
/// CPython: asyncio.Semaphore
pub const Semaphore = struct {
    value: i32,
    initial_value: i32,

    pub fn init(value: i32) Semaphore {
        return .{ .value = value, .initial_value = value };
    }

    pub fn acquire(self: *Semaphore) void {
        while (self.value <= 0) {
            std.Thread.yield() catch {};
        }
        self.value -= 1;
    }

    pub fn release(self: *Semaphore) void {
        self.value += 1;
    }

    pub fn locked(self: *const Semaphore) bool {
        return self.value <= 0;
    }
};

/// Bounded Semaphore
/// CPython: asyncio.BoundedSemaphore
pub const BoundedSemaphore = struct {
    sem: Semaphore,

    pub fn init(value: i32) BoundedSemaphore {
        return .{ .sem = Semaphore.init(value) };
    }

    pub fn acquire(self: *BoundedSemaphore) void {
        self.sem.acquire();
    }

    pub fn release(self: *BoundedSemaphore) !void {
        if (self.sem.value >= self.sem.initial_value) {
            return error.ValueError;
        }
        self.sem.release();
    }
};

/// Condition variable
/// CPython: asyncio.Condition
pub const Condition = struct {
    lock: Lock,
    waiters: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Condition {
        return .{ .lock = Lock.init(allocator) };
    }

    pub fn acquire(self: *Condition) void {
        self.lock.acquire();
    }

    pub fn release(self: *Condition) void {
        self.lock.release();
    }

    pub fn locked(self: *const Condition) bool {
        return self.lock.locked();
    }

    pub fn wait(self: *Condition) void {
        self.waiters += 1;
        self.lock.release();
        // Would wait for notification
        std.Thread.yield() catch {};
        self.lock.acquire();
        self.waiters -= 1;
    }

    pub fn notify(self: *Condition, n: usize) void {
        _ = self;
        _ = n;
        // Would notify waiters
    }

    pub fn notifyAll(self: *Condition) void {
        self.notify(self.waiters);
    }
};

/// Barrier
/// CPython: asyncio.Barrier
pub const Barrier = struct {
    parties: usize,
    count: usize = 0,
    broken: bool = false,

    pub fn init(parties: usize) Barrier {
        return .{ .parties = parties };
    }

    pub fn wait(self: *Barrier) !usize {
        if (self.broken) return error.BrokenBarrier;
        self.count += 1;
        const index = self.count;
        while (self.count < self.parties and !self.broken) {
            std.Thread.yield() catch {};
        }
        if (self.broken) return error.BrokenBarrier;
        return index - 1;
    }

    pub fn reset(self: *Barrier) void {
        self.count = 0;
        self.broken = false;
    }

    pub fn abort(self: *Barrier) void {
        self.broken = true;
    }
};

// ============================================================================
// Queue Types (CPython: asyncio.queues)
// ============================================================================

/// Async Queue
/// CPython: asyncio.Queue
pub fn Queue(comptime T: type) type {
    return struct {
        items: std.ArrayList(T) = .{},
        maxsize: usize,
        allocator: std.mem.Allocator,
        unfinished_tasks: usize = 0,
        is_shutdown: bool = false,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                .maxsize = maxsize,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        pub fn put(self: *Self, item: T) !void {
            if (self.is_shutdown) return error.QueueShutDown;
            while (self.full()) {
                std.Thread.yield() catch {};
            }
            try self.putNowait(item);
        }

        pub fn putNowait(self: *Self, item: T) !void {
            if (self.is_shutdown) return error.QueueShutDown;
            if (self.full()) return error.QueueFull;
            try self.items.append(self.allocator, item);
            self.unfinished_tasks += 1;
        }

        pub fn get(self: *Self) !T {
            while (self.empty() and !self.is_shutdown) {
                std.Thread.yield() catch {};
            }
            return self.getNowait();
        }

        pub fn getNowait(self: *Self) !T {
            if (self.empty()) return error.QueueEmpty;
            return self.items.orderedRemove(0);
        }

        pub fn taskDone(self: *Self) void {
            if (self.unfinished_tasks > 0) {
                self.unfinished_tasks -= 1;
            }
        }

        pub fn qsize(self: *const Self) usize {
            return self.items.items.len;
        }

        pub fn empty(self: *const Self) bool {
            return self.items.items.len == 0;
        }

        pub fn full(self: *const Self) bool {
            return self.maxsize > 0 and self.items.items.len >= self.maxsize;
        }

        pub fn shutdown(self: *Self, immediate: bool) void {
            self.is_shutdown = true;
            if (immediate) {
                self.items.clearRetainingCapacity();
            }
        }
    };
}

/// Priority Queue
/// CPython: asyncio.PriorityQueue
pub fn PriorityQueue(comptime T: type) type {
    return struct {
        queue: Queue(T),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{ .queue = Queue(T).init(allocator, maxsize) };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        pub fn put(self: *Self, item: T) !void {
            try self.queue.put(item);
            // Would sort by priority
        }

        pub fn get(self: *Self) !T {
            return self.queue.get();
        }

        pub fn qsize(self: *const Self) usize {
            return self.queue.qsize();
        }

        pub fn empty(self: *const Self) bool {
            return self.queue.empty();
        }
    };
}

/// LIFO Queue (Stack)
/// CPython: asyncio.LifoQueue
pub fn LifoQueue(comptime T: type) type {
    return struct {
        queue: Queue(T),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{ .queue = Queue(T).init(allocator, maxsize) };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        pub fn put(self: *Self, item: T) !void {
            try self.queue.put(item);
        }

        pub fn get(self: *Self) !T {
            if (self.queue.empty()) return error.QueueEmpty;
            return self.queue.items.pop();
        }

        pub fn qsize(self: *const Self) usize {
            return self.queue.qsize();
        }

        pub fn empty(self: *const Self) bool {
            return self.queue.empty();
        }
    };
}

// ============================================================================
// Wait Constants (CPython: asyncio.tasks)
// ============================================================================

pub const FIRST_COMPLETED: i32 = 0;
pub const FIRST_EXCEPTION: i32 = 1;
pub const ALL_COMPLETED: i32 = 2;

// ============================================================================
// Core Functions (CPython: asyncio module-level)
// ============================================================================

/// asyncio.sleep(seconds) - Sleep without blocking
/// CPython: asyncio.sleep
pub fn sleep(_: std.mem.Allocator, seconds: f64) !void {
    const ns = @as(u64, @intFromFloat(seconds * 1_000_000_000));
    std.Thread.sleep(ns);
}

/// asyncio.run(coro) - Run coroutine until complete
/// CPython: asyncio.run
/// Note: Simplified - real impl needs proper event loop
pub fn run(allocator: std.mem.Allocator, comptime coro: anytype) !@typeInfo(@TypeOf(coro)).@"fn".return_type.? {
    _ = allocator;
    return coro();
}

/// Create a task from coroutine
/// CPython: asyncio.create_task
pub fn createTask(allocator: std.mem.Allocator, comptime coro: anytype) !*Task {
    _ = coro;
    const task = try allocator.create(Task);
    task.* = Task.init(0, struct {
        fn cb(_: *anyopaque) anyerror!void {}
    }.cb, @ptrFromInt(0));
    return task;
}

/// Get currently running loop
/// CPython: asyncio.get_running_loop
pub fn getRunningLoop() ?*anyopaque {
    return null; // No global loop in this simplified impl
}

/// Get event loop
/// CPython: asyncio.get_event_loop
pub fn getEventLoop() ?*anyopaque {
    return null;
}

/// Shutdown the asyncio system
pub fn shutdown() void {
    // Cleanup if needed
}

// ============================================================================
// Type Checking Functions (CPython: asyncio.coroutines, asyncio.futures)
// ============================================================================

/// Check if value is a coroutine
/// CPython: asyncio.iscoroutine
pub fn iscoroutine(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .@"fn") {
        return info.@"fn".is_generic or info.@"fn".return_type != null;
    }
    return false;
}

/// Check if value is a coroutine function
/// CPython: asyncio.iscoroutinefunction
pub fn iscoroutinefunction(comptime T: type) bool {
    return iscoroutine(T);
}

/// Check if value is a Future
/// CPython: asyncio.isfuture
pub fn isfuture(comptime T: type) bool {
    return @hasField(T, "state") and @hasField(T, "result") and @hasDecl(T, "done");
}

/// Check if value is awaitable
/// CPython: inspect.isawaitable
pub fn isawaitable(comptime T: type) bool {
    return isfuture(T) or iscoroutine(T) or @hasDecl(T, "__await__");
}

// ============================================================================
// Exceptions (CPython: asyncio.exceptions)
// ============================================================================

pub const CancelledError = error.Cancelled;
pub const InvalidStateError = error.InvalidState;
pub const TimeoutError = error.Timeout;
pub const QueueEmpty = error.QueueEmpty;
pub const QueueFull = error.QueueFull;
pub const QueueShutDown = error.QueueShutDown;
pub const BrokenBarrierError = error.BrokenBarrier;
pub const SendfileNotAvailableError = error.SendfileNotAvailable;

// ============================================================================
// Tests
// ============================================================================

test "Future basic" {
    const allocator = std.testing.allocator;
    const IntFuture = Future(i64);
    const fut = try IntFuture.init(allocator);
    defer fut.deinit();

    try std.testing.expect(!fut.done());
    fut.setResult(42);
    try std.testing.expect(fut.done());
    try std.testing.expectEqual(@as(i64, 42), try fut.getResult());
}

test "Lock basic" {
    const allocator = std.testing.allocator;
    var lock = Lock.init(allocator);
    try std.testing.expect(!lock.locked());
    lock.acquire();
    try std.testing.expect(lock.locked());
    lock.release();
    try std.testing.expect(!lock.locked());
}

test "Event basic" {
    var event = Event.init();
    try std.testing.expect(!event.isSet());
    event.set();
    try std.testing.expect(event.isSet());
    event.clear();
    try std.testing.expect(!event.isSet());
}

test "Queue basic" {
    const allocator = std.testing.allocator;
    var queue = Queue(i32).init(allocator, 10);
    defer queue.deinit();

    try std.testing.expect(queue.empty());
    try queue.putNowait(1);
    try queue.putNowait(2);
    try std.testing.expectEqual(@as(usize, 2), queue.qsize());
    try std.testing.expectEqual(@as(i32, 1), try queue.getNowait());
    try std.testing.expectEqual(@as(i32, 2), try queue.getNowait());
    try std.testing.expect(queue.empty());
}

test "sleep" {
    const start = std.time.milliTimestamp();
    try sleep(std.testing.allocator, 0.01);
    const elapsed = std.time.milliTimestamp() - start;
    try std.testing.expect(elapsed >= 10);
}

test "isfuture" {
    const IntFuture = Future(i64);
    try std.testing.expect(isfuture(IntFuture));
    try std.testing.expect(!isfuture(i64));
}
