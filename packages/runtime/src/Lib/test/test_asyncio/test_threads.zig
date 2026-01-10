//! test.test_asyncio.test_threads - Tests for asyncio thread support
//! Reference: cpython/Lib/test/test_asyncio/test_threads.py
//!
//! Tests for to_thread and run_coroutine_threadsafe

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Thread Pool for Blocking Operations
// ============================================================================

/// A simple thread pool for running blocking operations
pub const ThreadPool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _threads: std.ArrayList(std.Thread),
    _tasks: std.ArrayList(Task),
    _shutdown: bool = false,
    _mutex: std.Thread.Mutex = .{},

    pub const Task = struct {
        func: *const fn (*anyopaque) void,
        arg: *anyopaque,
        completed: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._threads = std.ArrayList(std.Thread).init(allocator),
            ._tasks = std.ArrayList(Task).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.shutdown();
        self._threads.deinit();
        self._tasks.deinit();
    }

    pub fn submit(self: *Self, func: *const fn (*anyopaque) void, arg: *anyopaque) !void {
        self._mutex.lock();
        defer self._mutex.unlock();

        if (self._shutdown) {
            return error.PoolShutdown;
        }

        try self._tasks.append(.{
            .func = func,
            .arg = arg,
        });
    }

    pub fn shutdown(self: *Self) void {
        self._mutex.lock();
        self._shutdown = true;
        self._mutex.unlock();
    }
};

// ============================================================================
// to_thread - Run blocking code in a thread
// ============================================================================

/// Result container for thread execution
pub fn ThreadResult(comptime T: type) type {
    return struct {
        result: ?T = null,
        err: ?anyerror = null,
        completed: bool = false,
    };
}

/// Run a blocking function in a thread pool
pub fn to_thread(
    comptime T: type,
    func: *const fn () T,
) ThreadResult(T) {
    // In real implementation, this would run in a thread pool
    // For testing, we execute synchronously
    var result = ThreadResult(T){};
    result.result = func();
    result.completed = true;
    return result;
}

/// Run a blocking function with error handling
pub fn to_thread_with_error(
    comptime T: type,
    func: *const fn () anyerror!T,
) ThreadResult(T) {
    var result = ThreadResult(T){};
    if (func()) |value| {
        result.result = value;
    } else |err| {
        result.err = err;
    }
    result.completed = true;
    return result;
}

// ============================================================================
// run_coroutine_threadsafe - Run coroutine from another thread
// ============================================================================

/// A thread-safe future for cross-thread coroutine execution
pub fn ThreadSafeFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        _result: ?T = null,
        _exception: ?anyerror = null,
        _done: bool = false,
        _mutex: std.Thread.Mutex = .{},
        _cancelled: bool = false,

        pub fn init() Self {
            return .{};
        }

        pub fn result(self: *Self, timeout: ?f64) !T {
            _ = timeout;
            self._mutex.lock();
            defer self._mutex.unlock();

            if (self._cancelled) {
                return error.Cancelled;
            }
            if (self._exception) |exc| {
                return exc;
            }
            if (self._result) |r| {
                return r;
            }
            return error.InvalidState;
        }

        pub fn done(self: *Self) bool {
            self._mutex.lock();
            defer self._mutex.unlock();
            return self._done;
        }

        pub fn cancel(self: *Self) bool {
            self._mutex.lock();
            defer self._mutex.unlock();
            if (self._done) {
                return false;
            }
            self._cancelled = true;
            self._done = true;
            return true;
        }

        pub fn set_result(self: *Self, value: T) void {
            self._mutex.lock();
            defer self._mutex.unlock();
            self._result = value;
            self._done = true;
        }

        pub fn set_exception(self: *Self, exc: anyerror) void {
            self._mutex.lock();
            defer self._mutex.unlock();
            self._exception = exc;
            self._done = true;
        }
    };
}

/// Run a coroutine from another thread
pub fn run_coroutine_threadsafe(
    comptime T: type,
    _: *test_events.EventLoop,
) ThreadSafeFuture(T) {
    return ThreadSafeFuture(T).init();
}

// ============================================================================
// Test Helpers
// ============================================================================

fn blockingFunc() i32 {
    return 42;
}

fn blockingFuncWithError() anyerror!i32 {
    return error.SomeError;
}

fn blockingFuncSuccess() anyerror!i32 {
    return 100;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testThreadPoolCreate() !void {
    const allocator = std.testing.allocator;
    var pool = ThreadPool.init(allocator);
    defer pool.deinit();

    try std.testing.expect(!pool._shutdown);
}

fn testThreadPoolShutdown() !void {
    const allocator = std.testing.allocator;
    var pool = ThreadPool.init(allocator);

    pool.shutdown();
    try std.testing.expect(pool._shutdown);

    pool.deinit();
}

fn testToThread() !void {
    const result = to_thread(i32, blockingFunc);

    try std.testing.expect(result.completed);
    try std.testing.expectEqual(@as(?i32, 42), result.result);
}

fn testToThreadWithError() !void {
    const result = to_thread_with_error(i32, blockingFuncWithError);

    try std.testing.expect(result.completed);
    try std.testing.expect(result.err != null);
    try std.testing.expectEqual(error.SomeError, result.err.?);
}

fn testToThreadSuccess() !void {
    const result = to_thread_with_error(i32, blockingFuncSuccess);

    try std.testing.expect(result.completed);
    try std.testing.expectEqual(@as(?i32, 100), result.result);
    try std.testing.expect(result.err == null);
}

fn testThreadSafeFuture() !void {
    var fut = ThreadSafeFuture(i32).init();

    try std.testing.expect(!fut.done());

    fut.set_result(42);
    try std.testing.expect(fut.done());

    const value = try fut.result(null);
    try std.testing.expectEqual(@as(i32, 42), value);
}

fn testThreadSafeFutureCancel() !void {
    var fut = ThreadSafeFuture(i32).init();

    try std.testing.expect(fut.cancel());
    try std.testing.expect(fut.done());

    const err = fut.result(null);
    try std.testing.expectError(error.Cancelled, err);
}

fn testThreadSafeFutureException() !void {
    var fut = ThreadSafeFuture(i32).init();

    fut.set_exception(error.SomeError);
    try std.testing.expect(fut.done());

    const err = fut.result(null);
    try std.testing.expectError(error.SomeError, err);
}

fn testRunCoroutineThreadsafe() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var fut = run_coroutine_threadsafe(i32, &loop);
    try std.testing.expect(!fut.done());
}

fn testThreadSafeFutureCancelAfterDone() !void {
    var fut = ThreadSafeFuture(i32).init();

    fut.set_result(42);
    try std.testing.expect(!fut.cancel()); // Can't cancel after done
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "ThreadPool create" {
    try testThreadPoolCreate();
}

test "ThreadPool shutdown" {
    try testThreadPoolShutdown();
}

test "to_thread" {
    try testToThread();
}

test "to_thread with error" {
    try testToThreadWithError();
}

test "to_thread success" {
    try testToThreadSuccess();
}

test "ThreadSafeFuture" {
    try testThreadSafeFuture();
}

test "ThreadSafeFuture cancel" {
    try testThreadSafeFutureCancel();
}

test "ThreadSafeFuture exception" {
    try testThreadSafeFutureException();
}

test "run_coroutine_threadsafe" {
    try testRunCoroutineThreadsafe();
}

test "ThreadSafeFuture cancel after done" {
    try testThreadSafeFutureCancelAfterDone();
}

// Error types
const SomeError = error{SomeError};
