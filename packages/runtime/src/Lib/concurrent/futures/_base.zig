//! concurrent.futures._base - Base classes for futures
//! Reference: cpython/Lib/concurrent/futures/_base.py
//!
//! CPython exports: FIRST_COMPLETED, FIRST_EXCEPTION, ALL_COMPLETED,
//!                  CancelledError, TimeoutError, InvalidStateError,
//!                  BrokenExecutor, Future, Executor, wait, as_completed,
//!                  DoneAndNotDoneFutures
//!
//! Provides base classes and utilities for the concurrent.futures module.

const std = @import("std");
const concurrent = @import("../../concurrent.zig");

// ============================================================================
// Re-export from parent (DRY)
// ============================================================================

/// Future state enum
pub const FutureState = concurrent.FutureState;

/// Generic Future type
pub const Future = concurrent.Future;

/// Base Executor
pub const Executor = concurrent.Executor;

/// wait function
pub const wait = concurrent.wait;

/// WaitResult
pub const WaitResult = concurrent.WaitResult;

// ============================================================================
// Constants
// ============================================================================

/// CPython: PENDING = 'PENDING'
pub const PENDING = "PENDING";

/// CPython: RUNNING = 'RUNNING'
pub const RUNNING = "RUNNING";

/// CPython: CANCELLED = 'CANCELLED'
pub const CANCELLED = "CANCELLED";

/// CPython: CANCELLED_AND_NOTIFIED = 'CANCELLED_AND_NOTIFIED'
pub const CANCELLED_AND_NOTIFIED = "CANCELLED_AND_NOTIFIED";

/// CPython: FINISHED = 'FINISHED'
pub const FINISHED = "FINISHED";

/// State names lookup
pub const _STATE_TO_DESCRIPTION_MAP = [_]struct { state: FutureState, name: []const u8 }{
    .{ .state = .pending, .name = "pending" },
    .{ .state = .running, .name = "running" },
    .{ .state = .cancelled, .name = "cancelled" },
    .{ .state = .finished, .name = "finished" },
};

/// CPython: FIRST_COMPLETED = 'FIRST_COMPLETED'
pub const FIRST_COMPLETED = concurrent.FIRST_COMPLETED;

/// CPython: FIRST_EXCEPTION = 'FIRST_EXCEPTION'
pub const FIRST_EXCEPTION = concurrent.FIRST_EXCEPTION;

/// CPython: ALL_COMPLETED = 'ALL_COMPLETED'
pub const ALL_COMPLETED = concurrent.ALL_COMPLETED;

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class CancelledError(Exception)
pub const CancelledError = error.CancelledError;

/// CPython: class TimeoutError(Exception)
pub const TimeoutError = error.Timeout;

/// CPython: class InvalidStateError(Exception)
pub const InvalidStateError = error.InvalidState;

/// CPython: class BrokenExecutor(RuntimeError)
pub const BrokenExecutor = error.BrokenExecutor;

// ============================================================================
// Logger
// ============================================================================

/// CPython: LOGGER = logging.getLogger("concurrent.futures")
/// In Zig, we use std.log
pub fn log(comptime format: []const u8, args: anytype) void {
    std.log.info("[concurrent.futures] " ++ format, args);
}

// ============================================================================
// Extended Future API
// ============================================================================

/// CPython: class Future
/// Extended Future with full CPython API
pub fn CPythonFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        base: Future(T),
        /// Whether to log exceptions
        log_exceptions: bool = true,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .base = Future(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }

        /// CPython: def cancel(self)
        pub fn cancel(self: *Self) bool {
            return self.base.cancel();
        }

        /// CPython: def cancelled(self)
        pub fn cancelled(self: *const Self) bool {
            return self.base.cancelled();
        }

        /// CPython: def running(self)
        pub fn running(self: *const Self) bool {
            return self.base.running();
        }

        /// CPython: def done(self)
        pub fn done(self: *const Self) bool {
            return self.base.done();
        }

        /// CPython: def result(self, timeout=None)
        pub fn result(self: *Self, timeout: ?u64) !T {
            return self.base.getResult(timeout);
        }

        /// CPython: def exception(self, timeout=None)
        pub fn exception(self: *Self, timeout: ?u64) !?anyerror {
            _ = timeout;
            return self.base.getException();
        }

        /// CPython: def add_done_callback(self, fn)
        pub fn add_done_callback(self: *Self, callback: *const fn (*Future(T)) void) !void {
            try self.base.addDoneCallback(callback);
        }

        /// CPython: def set_result(self, result)
        pub fn set_result(self: *Self, res: T) void {
            self.base.setResult(res);
        }

        /// CPython: def set_exception(self, exception)
        pub fn set_exception(self: *Self, exc: anyerror) void {
            self.base.setException(exc);
        }

        /// CPython: def set_running_or_notify_cancel(self)
        /// Mark the future as running or process any cancel notifications
        pub fn set_running_or_notify_cancel(self: *Self) bool {
            self.base.mutex.lock();
            defer self.base.mutex.unlock();

            if (self.base.state == .cancelled) {
                return false;
            }
            if (self.base.state != .pending) {
                return false;
            }
            self.base.state = .running;
            return true;
        }
    };
}

// ============================================================================
// Extended Executor API
// ============================================================================

/// CPython: class Executor
/// Extended Executor with context manager support
pub const CPythonExecutor = struct {
    const Self = @This();

    base: Executor,
    is_shutdown: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = Executor.init(allocator),
        };
    }

    /// CPython: def submit(self, fn, *args, **kwargs)
    /// Submit a callable to be executed
    pub fn submit(self: *Self, comptime T: type, func: *const fn () T) !*CPythonFuture(T) {
        if (self.is_shutdown) {
            return error.RuntimeError;
        }
        const fut = try self.base.allocator.create(CPythonFuture(T));
        fut.* = CPythonFuture(T).init(self.base.allocator);
        // In a real implementation, we'd queue the work
        _ = func;
        return fut;
    }

    /// CPython: def map(self, fn, *iterables, timeout=None, chunksize=1)
    /// Return an iterator equivalent to map(fn, iter)
    pub fn map(self: *Self, comptime T: type, comptime R: type, func: *const fn (T) R, items: []const T) ![]R {
        if (self.is_shutdown) {
            return error.RuntimeError;
        }
        var results = try self.base.allocator.alloc(R, items.len);
        for (items, 0..) |item, i| {
            results[i] = func(item);
        }
        return results;
    }

    /// CPython: def shutdown(self, wait=True, cancel_futures=False)
    pub fn shutdown(self: *Self, wait_for_completion: bool, cancel_futures: bool) void {
        self.is_shutdown = true;
        self.base.shutdown(wait_for_completion, cancel_futures);
    }

    /// CPython: def __enter__(self)
    pub fn __enter__(self: *Self) *Self {
        return self;
    }

    /// CPython: def __exit__(self, exc_type, exc_val, exc_tb)
    pub fn __exit__(self: *Self, _: anytype, _: anytype, _: anytype) void {
        self.shutdown(true, false);
    }
};

// ============================================================================
// _Waiter class (internal)
// ============================================================================

/// CPython: class _Waiter
/// Internal class for managing wait operations
pub fn Waiter(comptime T: type) type {
    return struct {
        const Self = @This();

        event: std.Thread.Condition = .{},
        mutex: std.Thread.Mutex = .{},
        finished_futures: std.ArrayList(*Future(T)),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .finished_futures = std.ArrayList(*Future(T)).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.finished_futures.deinit();
        }

        pub fn add_result(self: *Self, future: *Future(T)) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.finished_futures.append(future);
            self.event.signal();
        }

        pub fn add_exception(self: *Self, future: *Future(T)) !void {
            try self.add_result(future);
        }

        pub fn add_cancelled(self: *Self, future: *Future(T)) !void {
            try self.add_result(future);
        }
    };
}

// ============================================================================
// _AsCompletedWaiter class (internal)
// ============================================================================

/// CPython: class _AsCompletedWaiter(_Waiter)
/// Waiter for as_completed()
pub fn AsCompletedWaiter(comptime T: type) type {
    return struct {
        const Self = @This();

        base: Waiter(T),
        lock: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .base = Waiter(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }
    };
}

// ============================================================================
// _FirstCompletedWaiter class (internal)
// ============================================================================

/// CPython: class _FirstCompletedWaiter(_Waiter)
/// Waiter that completes when first future completes
pub fn FirstCompletedWaiter(comptime T: type) type {
    return Waiter(T);
}

// ============================================================================
// _AllCompletedWaiter class (internal)
// ============================================================================

/// CPython: class _AllCompletedWaiter(_Waiter)
/// Waiter that completes when all futures complete
pub fn AllCompletedWaiter(comptime T: type) type {
    return struct {
        const Self = @This();

        base: Waiter(T),
        num_pending_calls: usize,
        stop_on_exception: bool,

        pub fn init(allocator: std.mem.Allocator, num_pending: usize, stop_on_exception: bool) Self {
            return .{
                .base = Waiter(T).init(allocator),
                .num_pending_calls = num_pending,
                .stop_on_exception = stop_on_exception,
            };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }
    };
}

// ============================================================================
// _AcquireFutures context manager
// ============================================================================

/// CPython: class _AcquireFutures
/// Context manager for acquiring futures
pub fn AcquireFutures(comptime T: type) type {
    return struct {
        const Self = @This();

        futures: []const *Future(T),

        pub fn init(futures: []const *Future(T)) Self {
            return .{ .futures = futures };
        }

        pub fn __enter__(self: *Self) *Self {
            for (self.futures) |fut| {
                fut.mutex.lock();
            }
            return self;
        }

        pub fn __exit__(self: *Self, _: anytype, _: anytype, _: anytype) void {
            for (self.futures) |fut| {
                fut.mutex.unlock();
            }
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqualStrings("PENDING", PENDING);
    try std.testing.expectEqualStrings("RUNNING", RUNNING);
    try std.testing.expectEqualStrings("CANCELLED", CANCELLED);
    try std.testing.expectEqualStrings("FINISHED", FINISHED);
}

test "CPythonFuture init" {
    const allocator = std.testing.allocator;
    var fut = CPythonFuture(i32).init(allocator);
    defer fut.deinit();

    try std.testing.expect(!fut.done());
    try std.testing.expect(!fut.cancelled());
}

test "CPythonFuture set_running_or_notify_cancel" {
    const allocator = std.testing.allocator;
    var fut = CPythonFuture(i32).init(allocator);
    defer fut.deinit();

    try std.testing.expect(fut.set_running_or_notify_cancel());
    try std.testing.expect(fut.running());
}

test "CPythonExecutor init" {
    const allocator = std.testing.allocator;
    var executor = CPythonExecutor.init(allocator);
    try std.testing.expect(!executor.is_shutdown);
    executor.shutdown(false, false);
    try std.testing.expect(executor.is_shutdown);
}

test "Waiter init" {
    const allocator = std.testing.allocator;
    var waiter = Waiter(i32).init(allocator);
    defer waiter.deinit();
}
