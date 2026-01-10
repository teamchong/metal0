//! concurrent.futures - High-level interface for asynchronous execution
//! Reference: cpython/Lib/concurrent/futures/__init__.py
//!
//! CPython __all__: ['CancelledError', 'TimeoutError', 'BrokenExecutor',
//!                   'InvalidStateError', 'Future', 'Executor',
//!                   'wait', 'as_completed', 'ProcessPoolExecutor',
//!                   'ThreadPoolExecutor', 'FIRST_COMPLETED',
//!                   'FIRST_EXCEPTION', 'ALL_COMPLETED']
//!
//! Provides high-level interface for asynchronously executing callables.

const std = @import("std");
const concurrent = @import("../concurrent.zig");

// ============================================================================
// Re-export from parent module (DRY)
// ============================================================================

/// Future - Represents the result of an asynchronous computation
pub const Future = concurrent.Future;

/// FutureState - State of a Future
pub const FutureState = concurrent.FutureState;

/// Executor - Abstract base class for executors
pub const Executor = concurrent.Executor;

/// ThreadPoolExecutor - Executor using a pool of threads
pub const ThreadPoolExecutor = concurrent.ThreadPoolExecutor;

/// ProcessPoolExecutor - Executor using a pool of processes
pub const ProcessPoolExecutor = concurrent.ProcessPoolExecutor;

/// wait - Wait for futures to complete
pub const wait = concurrent.wait;

/// WaitResult - Result of wait()
pub const WaitResult = concurrent.WaitResult;

// ============================================================================
// Error Types (CPython exceptions)
// ============================================================================

/// CPython: class CancelledError(Exception)
/// Exception raised when a future is cancelled
pub const CancelledError = error.CancelledError;

/// CPython: class TimeoutError(Exception)
/// Exception raised when a future times out
pub const TimeoutError = error.Timeout;

/// CPython: class BrokenExecutor(RuntimeError)
/// Exception raised when an executor breaks unexpectedly
pub const BrokenExecutor = error.BrokenExecutor;

/// CPython: class InvalidStateError(Exception)
/// Exception raised when an operation is invalid for the current future state
pub const InvalidStateError = error.InvalidState;

// ============================================================================
// Wait Constants
// ============================================================================

/// CPython: FIRST_COMPLETED = 'FIRST_COMPLETED'
pub const FIRST_COMPLETED = concurrent.FIRST_COMPLETED;

/// CPython: FIRST_EXCEPTION = 'FIRST_EXCEPTION'
pub const FIRST_EXCEPTION = concurrent.FIRST_EXCEPTION;

/// CPython: ALL_COMPLETED = 'ALL_COMPLETED'
pub const ALL_COMPLETED = concurrent.ALL_COMPLETED;

// ============================================================================
// as_completed
// ============================================================================

/// Iterator result for as_completed
pub fn AsCompletedIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        futures: []const *Future(T),
        current: usize = 0,
        completed: std.ArrayList(usize),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, futures: []const *Future(T)) Self {
            return .{
                .futures = futures,
                .completed = std.ArrayList(usize).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.completed.deinit();
        }

        /// Get next completed future
        pub fn next(self: *Self) ?*Future(T) {
            while (self.current < self.futures.len) {
                const fut = self.futures[self.current];
                self.current += 1;
                if (fut.done()) {
                    return fut;
                }
            }
            return null;
        }
    };
}

/// CPython: def as_completed(fs, timeout=None)
/// Return an iterator over futures as they complete
pub fn as_completed(
    comptime T: type,
    allocator: std.mem.Allocator,
    futures: []const *Future(T),
    timeout: ?u64,
) AsCompletedIterator(T) {
    _ = timeout;
    return AsCompletedIterator(T).init(allocator, futures);
}

// ============================================================================
// DoneAndNotDoneFutures
// ============================================================================

/// CPython: DoneAndNotDoneFutures = collections.namedtuple('DoneAndNotDoneFutures', 'done not_done')
pub fn DoneAndNotDoneFutures(comptime T: type) type {
    return struct {
        done: std.ArrayList(*Future(T)),
        not_done: std.ArrayList(*Future(T)),

        pub fn deinit(self: *@This()) void {
            self.done.deinit();
            self.not_done.deinit();
        }
    };
}

/// Extended wait that returns sets of futures
pub fn waitWithSets(
    comptime T: type,
    allocator: std.mem.Allocator,
    futures: []const *Future(T),
    timeout: ?u64,
    return_when: enum { first_completed, first_exception, all_completed },
) !DoneAndNotDoneFutures(T) {
    _ = timeout;
    var result = DoneAndNotDoneFutures(T){
        .done = std.ArrayList(*Future(T)).init(allocator),
        .not_done = std.ArrayList(*Future(T)).init(allocator),
    };

    for (futures) |fut| {
        const is_done = switch (return_when) {
            .first_completed => fut.done(),
            .first_exception => fut.done() and fut.exception != null,
            .all_completed => fut.done(),
        };

        if (is_done) {
            try result.done.append(fut);
        } else {
            try result.not_done.append(fut);
        }
    }

    return result;
}

// ============================================================================
// Submodule Imports
// ============================================================================

pub const _base = @import("futures/_base.zig");
pub const thread = @import("futures/thread.zig");
pub const process = @import("futures/process.zig");
pub const interpreter = @import("futures/interpreter.zig");

// ============================================================================
// Tests
// ============================================================================

test "imports" {
    _ = _base;
    _ = thread;
    _ = process;
    _ = interpreter;
}

test "Future re-export" {
    const allocator = std.testing.allocator;
    var fut = Future(i32).init(allocator);
    defer fut.deinit();

    try std.testing.expect(fut.state == .pending);
}

test "constants" {
    try std.testing.expectEqualStrings("FIRST_COMPLETED", FIRST_COMPLETED);
    try std.testing.expectEqualStrings("FIRST_EXCEPTION", FIRST_EXCEPTION);
    try std.testing.expectEqualStrings("ALL_COMPLETED", ALL_COMPLETED);
}

test "AsCompletedIterator" {
    const allocator = std.testing.allocator;
    var fut1 = Future(i32).init(allocator);
    defer fut1.deinit();
    var fut2 = Future(i32).init(allocator);
    defer fut2.deinit();

    fut1.setResult(1);

    const futures = [_]*Future(i32){ &fut1, &fut2 };
    var iter = as_completed(i32, allocator, &futures, null);
    defer iter.deinit();

    const first = iter.next();
    try std.testing.expect(first != null);
    try std.testing.expect(first.?.done());
}
