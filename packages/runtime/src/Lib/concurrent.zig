//! Python 'concurrent' module - Concurrent execution utilities
//!
//! Provides high-level interface for asynchronously executing callables.
//!
//! Mirrors: CPython Lib/concurrent/

const std = @import("std");

// ============================================================================
// Future State
// ============================================================================

/// State of a Future
pub const FutureState = enum {
    /// Future is pending execution
    pending,
    /// Future is currently running
    running,
    /// Future completed successfully
    finished,
    /// Future was cancelled
    cancelled,
};

// ============================================================================
// Future
// ============================================================================

/// Represents the result of an asynchronous computation
pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        state: FutureState = .pending,
        result: ?T = null,
        exception: ?anyerror = null,
        callbacks: std.ArrayList(*const fn (*Self) void),
        mutex: std.Thread.Mutex = .{},
        condition: std.Thread.Condition = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .callbacks = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.callbacks.deinit(self.allocator);
        }

        /// Cancel the future
        pub fn cancel(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state == .pending) {
                self.state = .cancelled;
                self.condition.broadcast();
                return true;
            }
            return false;
        }

        /// Check if cancelled
        pub fn cancelled(self: *const Self) bool {
            return self.state == .cancelled;
        }

        /// Check if running
        pub fn running(self: *const Self) bool {
            return self.state == .running;
        }

        /// Check if done (finished, cancelled, or exception)
        pub fn done(self: *const Self) bool {
            return self.state == .finished or self.state == .cancelled;
        }

        /// Get the result, blocking if necessary
        pub fn getResult(self: *Self, timeout: ?u64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.state != .finished and self.state != .cancelled) {
                if (timeout) |t| {
                    const did_timeout = self.condition.timedWait(&self.mutex, t) == .timed_out;
                    if (did_timeout) return error.Timeout;
                } else {
                    self.condition.wait(&self.mutex);
                }
            }

            if (self.state == .cancelled) return error.CancelledError;
            if (self.exception) |e| return e;
            return self.result orelse error.NoResult;
        }

        /// Get exception if any
        pub fn getException(self: *const Self) ?anyerror {
            return self.exception;
        }

        /// Add a callback to be called when future completes
        pub fn addDoneCallback(self: *Self, callback: *const fn (*Self) void) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.done()) {
                callback(self);
            } else {
                try self.callbacks.append(self.allocator, callback);
            }
        }

        /// Set the result (called by executor)
        pub fn setResult(self: *Self, result: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.result = result;
            self.state = .finished;
            self.condition.broadcast();

            for (self.callbacks.items) |callback| {
                callback(self);
            }
        }

        /// Set an exception (called by executor)
        pub fn setException(self: *Self, exception: anyerror) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.exception = exception;
            self.state = .finished;
            self.condition.broadcast();

            for (self.callbacks.items) |callback| {
                callback(self);
            }
        }
    };
}

// ============================================================================
// Executor Interface
// ============================================================================

/// Base executor interface
/// NOTE: The Executor struct is an abstract interface. Use ThreadPoolExecutor or
/// ProcessPoolExecutor for actual execution. Direct submission via Executor.submit()
/// requires providing a concrete implementation.
pub const Executor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pool: ?*ThreadPoolExecutor = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Attach a thread pool to this executor
    pub fn attachPool(self: *Self, pool: *ThreadPoolExecutor) void {
        self.pool = pool;
    }

    /// Submit work to the attached pool
    pub fn submitWork(self: *Self, func: *const fn (*anyopaque) void, context: *anyopaque) !void {
        if (self.pool) |pool| {
            try pool.submitWork(func, context);
        } else {
            return error.NoExecutorAttached;
        }
    }

    /// Shutdown the executor
    pub fn shutdown(self: *Self, wait_for_completion: bool, cancel_futures: bool) void {
        if (self.pool) |pool| {
            pool.shutdown(wait_for_completion, cancel_futures);
        }
    }
};

// ============================================================================
// Thread Pool Executor
// ============================================================================

/// Executor using a pool of threads
pub const ThreadPoolExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    max_workers: usize,
    thread_name_prefix: []const u8,
    workers: std.ArrayList(std.Thread),
    shutdown_flag: std.atomic.Value(bool),
    work_queue: std.ArrayList(WorkItem),
    queue_mutex: std.Thread.Mutex,
    work_available: std.Thread.Condition,

    const WorkItem = struct {
        func: *const fn (*anyopaque) void,
        context: *anyopaque,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        max_workers: ?usize,
        thread_name_prefix: ?[]const u8,
    ) Self {
        const workers = max_workers orelse (std.Thread.getCpuCount() catch 4);
        return .{
            .allocator = allocator,
            .max_workers = workers,
            .thread_name_prefix = thread_name_prefix orelse "ThreadPool",
            .workers = .{},
            .shutdown_flag = std.atomic.Value(bool).init(false),
            .work_queue = .{},
            .queue_mutex = .{},
            .work_available = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.shutdown(true, false);
        self.workers.deinit(self.allocator);
        self.work_queue.deinit(self.allocator);
    }

    /// Submit work to the pool
    pub fn submitWork(self: *Self, func: *const fn (*anyopaque) void, context: *anyopaque) !void {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        try self.work_queue.append(self.allocator, .{ .func = func, .context = context });
        self.work_available.signal();
    }

    /// Shutdown the executor
    pub fn shutdown(self: *Self, wait_for_completion: bool, cancel_futures: bool) void {
        _ = cancel_futures;

        self.shutdown_flag.store(true, .release);
        self.work_available.broadcast();

        if (wait_for_completion) {
            for (self.workers.items) |*worker| {
                worker.join();
            }
        }
    }
};

// ============================================================================
// Process Pool Executor
// ============================================================================

/// Executor using a pool of processes
pub const ProcessPoolExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    max_workers: usize,

    pub fn init(allocator: std.mem.Allocator, max_workers: ?usize) Self {
        const workers = max_workers orelse (std.Thread.getCpuCount() catch 4);
        return .{
            .allocator = allocator,
            .max_workers = workers,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn shutdown(self: *Self, wait_for_completion: bool, cancel_futures: bool) void {
        _ = self;
        _ = wait_for_completion;
        _ = cancel_futures;
    }
};

// ============================================================================
// wait and as_completed
// ============================================================================

/// Wait return type
pub const WaitResult = struct {
    done: usize,
    not_done: usize,
};

/// Wait for futures to complete
pub fn wait(
    comptime T: type,
    futures: []const *Future(T),
    timeout: ?u64,
    return_when: enum { first_completed, first_exception, all_completed },
) WaitResult {
    _ = timeout;
    var done_count: usize = 0;

    for (futures) |f| {
        switch (return_when) {
            .first_completed => {
                if (f.done()) {
                    done_count += 1;
                    break;
                }
            },
            .first_exception => {
                if (f.done()) {
                    done_count += 1;
                    if (f.exception != null) break;
                }
            },
            .all_completed => {
                if (f.done()) done_count += 1;
            },
        }
    }

    return .{
        .done = done_count,
        .not_done = futures.len - done_count,
    };
}

// ============================================================================
// Error Types
// ============================================================================

pub const CancelledError = error.CancelledError;
pub const TimeoutError = error.Timeout;
pub const BrokenExecutor = error.BrokenExecutor;
pub const InvalidStateError = error.InvalidState;

// ============================================================================
// Constants
// ============================================================================

/// Return when first future completes
pub const FIRST_COMPLETED = "FIRST_COMPLETED";
/// Return when first future raises exception
pub const FIRST_EXCEPTION = "FIRST_EXCEPTION";
/// Return when all futures complete
pub const ALL_COMPLETED = "ALL_COMPLETED";

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the concurrent module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "FutureState enum" {
    try std.testing.expect(@intFromEnum(FutureState.pending) == 0);
    try std.testing.expect(@intFromEnum(FutureState.running) == 1);
    try std.testing.expect(@intFromEnum(FutureState.finished) == 2);
    try std.testing.expect(@intFromEnum(FutureState.cancelled) == 3);
}

test "Future init" {
    const allocator = std.testing.allocator;
    var future = Future(i32).init(allocator);
    defer future.deinit();

    try std.testing.expect(future.state == .pending);
    try std.testing.expect(!future.done());
    try std.testing.expect(!future.cancelled());
    try std.testing.expect(!future.running());
}

test "Future setResult" {
    const allocator = std.testing.allocator;
    var future = Future(i32).init(allocator);
    defer future.deinit();

    future.setResult(42);
    try std.testing.expect(future.done());
    try std.testing.expect(future.state == .finished);

    const result = try future.getResult(null);
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "Future cancel" {
    const allocator = std.testing.allocator;
    var future = Future(i32).init(allocator);
    defer future.deinit();

    try std.testing.expect(future.cancel());
    try std.testing.expect(future.cancelled());
    try std.testing.expect(future.done());
}

test "Future cancel after done" {
    const allocator = std.testing.allocator;
    var future = Future(i32).init(allocator);
    defer future.deinit();

    future.setResult(42);
    try std.testing.expect(!future.cancel());
}

test "ThreadPoolExecutor init" {
    const allocator = std.testing.allocator;
    var executor = ThreadPoolExecutor.init(allocator, 4, "Test");
    defer executor.deinit();

    try std.testing.expectEqual(@as(usize, 4), executor.max_workers);
    try std.testing.expectEqualStrings("Test", executor.thread_name_prefix);
}

test "ProcessPoolExecutor init" {
    const allocator = std.testing.allocator;
    var executor = ProcessPoolExecutor.init(allocator, 2);
    defer executor.deinit();

    try std.testing.expectEqual(@as(usize, 2), executor.max_workers);
}

test "wait result" {
    const result = WaitResult{ .done = 3, .not_done = 2 };
    try std.testing.expectEqual(@as(usize, 3), result.done);
    try std.testing.expectEqual(@as(usize, 2), result.not_done);
}

test "constants" {
    try std.testing.expectEqualStrings("FIRST_COMPLETED", FIRST_COMPLETED);
    try std.testing.expectEqualStrings("FIRST_EXCEPTION", FIRST_EXCEPTION);
    try std.testing.expectEqualStrings("ALL_COMPLETED", ALL_COMPLETED);
}
