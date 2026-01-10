//! test.test_concurrent_futures.test_future - Future object tests
//!
//! Tests for the Future class which represents the result of an asynchronous computation.
//! Provides methods to check completion status, get results, and handle exceptions.

const std = @import("std");
const testing = std.testing;

/// Error types for future operations
pub const FutureError = error{
    InvalidState,
    CancelledError,
    TimeoutError,
    AlreadyResolved,
    NotDone,
    BrokenFuture,
};

/// State of a future
pub const FutureState = enum(u8) {
    pending = 0,
    running = 1,
    cancelled = 2,
    finished_success = 3,
    finished_error = 4,

    pub fn isDone(self: FutureState) bool {
        return self == .cancelled or self == .finished_success or self == .finished_error;
    }

    pub fn isRunning(self: FutureState) bool {
        return self == .running;
    }

    pub fn isCancelled(self: FutureState) bool {
        return self == .cancelled;
    }

    pub fn isPending(self: FutureState) bool {
        return self == .pending;
    }

    pub fn hasResult(self: FutureState) bool {
        return self == .finished_success;
    }

    pub fn hasException(self: FutureState) bool {
        return self == .finished_error;
    }
};

/// Exception information stored in a future
pub const FutureException = struct {
    err: anyerror,
    message: ?[]const u8 = null,
    traceback: ?[]const u8 = null,

    pub fn init(err: anyerror) FutureException {
        return .{ .err = err };
    }

    pub fn withMessage(err: anyerror, message: []const u8) FutureException {
        return .{ .err = err, .message = message };
    }

    pub fn format(self: FutureException, allocator: std.mem.Allocator) ![]const u8 {
        if (self.message) |msg| {
            return std.fmt.allocPrint(allocator, "{s}: {s}", .{ @errorName(self.err), msg });
        }
        return std.fmt.allocPrint(allocator, "{s}", .{@errorName(self.err)});
    }
};

/// Generic callback type for done callbacks
pub fn DoneCallback(comptime T: type) type {
    return *const fn (future: *const Future(T)) void;
}

/// Generic Future type representing an asynchronous computation result
pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();

        state: FutureState = .pending,
        result_value: ?T = null,
        exception_info: ?FutureException = null,
        callbacks: std.ArrayList(DoneCallback(T)),
        allocator: std.mem.Allocator,
        creation_time: i64,
        completion_time: ?i64 = null,
        cancel_message: ?[]const u8 = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .callbacks = std.ArrayList(DoneCallback(T)).init(allocator),
                .creation_time = std.time.milliTimestamp(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.callbacks.deinit();
        }

        /// Cancel the future if it hasn't started running
        pub fn cancel(self: *Self) bool {
            return self.cancelWithMessage(null);
        }

        /// Cancel with a custom message
        pub fn cancelWithMessage(self: *Self, message: ?[]const u8) bool {
            if (self.state != .pending) {
                return false;
            }
            self.state = .cancelled;
            self.cancel_message = message;
            self.completion_time = std.time.milliTimestamp();
            self.invokeCallbacks();
            return true;
        }

        /// Check if the future was cancelled
        pub fn cancelled(self: Self) bool {
            return self.state.isCancelled();
        }

        /// Check if the future is currently running
        pub fn running(self: Self) bool {
            return self.state.isRunning();
        }

        /// Check if the future is done (completed, failed, or cancelled)
        pub fn done(self: Self) bool {
            return self.state.isDone();
        }

        /// Mark the future as running
        pub fn setRunning(self: *Self) FutureError!void {
            if (self.state != .pending) {
                return FutureError.InvalidState;
            }
            self.state = .running;
        }

        /// Set the result value
        pub fn setResult(self: *Self, value: T) FutureError!void {
            if (self.state.isDone()) {
                return FutureError.AlreadyResolved;
            }
            self.result_value = value;
            self.state = .finished_success;
            self.completion_time = std.time.milliTimestamp();
            self.invokeCallbacks();
        }

        /// Set an exception
        pub fn setException(self: *Self, err: anyerror) FutureError!void {
            return self.setExceptionInfo(FutureException.init(err));
        }

        /// Set exception with full info
        pub fn setExceptionInfo(self: *Self, exc: FutureException) FutureError!void {
            if (self.state.isDone()) {
                return FutureError.AlreadyResolved;
            }
            self.exception_info = exc;
            self.state = .finished_error;
            self.completion_time = std.time.milliTimestamp();
            self.invokeCallbacks();
        }

        /// Get the result, blocking until available (simplified - no actual blocking)
        pub fn result(self: Self) FutureError!T {
            return self.resultWithTimeout(null);
        }

        /// Get the result with optional timeout
        pub fn resultWithTimeout(self: Self, timeout_ms: ?i64) FutureError!T {
            _ = timeout_ms; // In real impl, would wait up to timeout

            if (self.state == .cancelled) {
                return FutureError.CancelledError;
            }
            if (self.state == .finished_error) {
                if (self.exception_info) |exc| {
                    return exc.err;
                }
                return FutureError.BrokenFuture;
            }
            if (self.state == .finished_success) {
                if (self.result_value) |v| {
                    return v;
                }
            }
            return FutureError.NotDone;
        }

        /// Get the exception if one was set
        pub fn exception(self: Self) ?FutureException {
            if (self.state == .finished_error) {
                return self.exception_info;
            }
            return null;
        }

        /// Get the exception error only
        pub fn exceptionError(self: Self) ?anyerror {
            if (self.exception()) |exc| {
                return exc.err;
            }
            return null;
        }

        /// Add a callback to be called when the future completes
        pub fn addDoneCallback(self: *Self, callback: DoneCallback(T)) !void {
            if (self.state.isDone()) {
                // Already done, invoke immediately
                callback(self);
            } else {
                try self.callbacks.append(callback);
            }
        }

        /// Remove a callback
        pub fn removeDoneCallback(self: *Self, callback: DoneCallback(T)) bool {
            for (self.callbacks.items, 0..) |cb, i| {
                if (cb == callback) {
                    _ = self.callbacks.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        fn invokeCallbacks(self: *Self) void {
            for (self.callbacks.items) |cb| {
                cb(self);
            }
            self.callbacks.clearRetainingCapacity();
        }

        /// Get the elapsed time since creation
        pub fn getElapsedTime(self: Self) i64 {
            const end = self.completion_time orelse std.time.milliTimestamp();
            return end - self.creation_time;
        }

        /// Get the state as a string
        pub fn getStateString(self: Self) []const u8 {
            return switch (self.state) {
                .pending => "PENDING",
                .running => "RUNNING",
                .cancelled => "CANCELLED",
                .finished_success => "FINISHED",
                .finished_error => "FINISHED",
            };
        }
    };
}

/// A completed future that already has a result
pub fn CompletedFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn result(self: Self) T {
            return self.value;
        }

        pub fn done(_: Self) bool {
            return true;
        }

        pub fn cancelled(_: Self) bool {
            return false;
        }

        pub fn running(_: Self) bool {
            return false;
        }
    };
}

/// A future that represents a cancelled operation
pub fn CancelledFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        message: ?[]const u8 = null,

        pub fn init() Self {
            return .{};
        }

        pub fn initWithMessage(msg: []const u8) Self {
            return .{ .message = msg };
        }

        pub fn result(_: Self) FutureError!T {
            return FutureError.CancelledError;
        }

        pub fn done(_: Self) bool {
            return true;
        }

        pub fn cancelled(_: Self) bool {
            return true;
        }

        pub fn running(_: Self) bool {
            return false;
        }
    };
}

/// A future that represents a failed operation
pub fn FailedFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        exc: FutureException,

        pub fn init(err: anyerror) Self {
            return .{ .exc = FutureException.init(err) };
        }

        pub fn initWithMessage(err: anyerror, message: []const u8) Self {
            return .{ .exc = FutureException.withMessage(err, message) };
        }

        pub fn result(self: Self) anyerror {
            return self.exc.err;
        }

        pub fn exception(self: Self) FutureException {
            return self.exc;
        }

        pub fn done(_: Self) bool {
            return true;
        }

        pub fn cancelled(_: Self) bool {
            return false;
        }

        pub fn running(_: Self) bool {
            return false;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "future_init_state" {
    var f = Future(i32).init(testing.allocator);
    defer f.deinit();

    try testing.expectEqual(FutureState.pending, f.state);
    try testing.expect(!f.done());
    try testing.expect(!f.running());
    try testing.expect(!f.cancelled());
    try testing.expectEqualStrings("PENDING", f.getStateString());
}

test "future_set_running" {
    var f = Future(i32).init(testing.allocator);
    defer f.deinit();

    try f.setRunning();
    try testing.expectEqual(FutureState.running, f.state);
    try testing.expect(f.running());
    try testing.expect(!f.done());
    try testing.expectEqualStrings("RUNNING", f.getStateString());

    // Cannot set running again
    try testing.expectError(FutureError.InvalidState, f.setRunning());
}

test "future_cancel" {
    var f = Future(i32).init(testing.allocator);
    defer f.deinit();

    try testing.expect(f.cancel());
    try testing.expect(f.cancelled());
    try testing.expect(f.done());
    try testing.expectEqualStrings("CANCELLED", f.getStateString());

    // Cannot cancel again
    try testing.expect(!f.cancel());

    // Result should error
    try testing.expectError(FutureError.CancelledError, f.result());
}

test "future_cancel_with_message" {
    var f = Future(i32).init(testing.allocator);
    defer f.deinit();

    try testing.expect(f.cancelWithMessage("User requested cancellation"));
    try testing.expect(f.cancelled());
    try testing.expectEqualStrings("User requested cancellation", f.cancel_message.?);
}

test "future_set_result" {
    var f = Future(i32).init(testing.allocator);
    defer f.deinit();

    try f.setResult(42);
    try testing.expect(f.done());
    try testing.expect(!f.cancelled());
    try testing.expectEqual(@as(i32, 42), try f.result());

    // Cannot set result again
    try testing.expectError(FutureError.AlreadyResolved, f.setResult(100));
}

test "future_set_exception" {
    var f = Future(i32).init(testing.allocator);
    defer f.deinit();

    try f.setException(error.SomeError);
    try testing.expect(f.done());
    try testing.expect(f.exception() != null);
    try testing.expectEqual(error.SomeError, f.exceptionError().?);

    // Result should return the error
    try testing.expectError(error.SomeError, f.result());
}

test "future_exception_info" {
    var f = Future(i32).init(testing.allocator);
    defer f.deinit();

    const exc = FutureException.withMessage(error.ValueError, "Invalid argument");
    try f.setExceptionInfo(exc);

    const retrieved = f.exception().?;
    try testing.expectEqual(error.ValueError, retrieved.err);
    try testing.expectEqualStrings("Invalid argument", retrieved.message.?);
}

test "future_elapsed_time" {
    var f = Future(i32).init(testing.allocator);
    defer f.deinit();

    std.time.sleep(10 * std.time.ns_per_ms);

    const elapsed1 = f.getElapsedTime();
    try testing.expect(elapsed1 >= 10);

    try f.setResult(42);

    const elapsed2 = f.getElapsedTime();
    try testing.expect(elapsed2 >= elapsed1);

    // After completion, elapsed time should be fixed
    std.time.sleep(10 * std.time.ns_per_ms);
    const elapsed3 = f.getElapsedTime();
    try testing.expectEqual(elapsed2, elapsed3);
}

test "completed_future" {
    const cf = CompletedFuture(i32).init(99);

    try testing.expect(cf.done());
    try testing.expect(!cf.cancelled());
    try testing.expect(!cf.running());
    try testing.expectEqual(@as(i32, 99), cf.result());
}

test "cancelled_future" {
    const cf = CancelledFuture(i32).init();

    try testing.expect(cf.done());
    try testing.expect(cf.cancelled());
    try testing.expect(!cf.running());
    try testing.expectError(FutureError.CancelledError, cf.result());
}

test "failed_future" {
    const ff = FailedFuture(i32).init(error.OperationFailed);

    try testing.expect(ff.done());
    try testing.expect(!ff.cancelled());
    try testing.expect(!ff.running());
    try testing.expectEqual(error.OperationFailed, ff.result());
}

test "future_state_transitions" {
    // pending -> running -> finished
    var f1 = Future(i32).init(testing.allocator);
    defer f1.deinit();

    try testing.expect(f1.state.isPending());
    try f1.setRunning();
    try testing.expect(f1.state.isRunning());
    try f1.setResult(42);
    try testing.expect(f1.state.hasResult());

    // pending -> cancelled
    var f2 = Future(i32).init(testing.allocator);
    defer f2.deinit();

    try testing.expect(f2.state.isPending());
    _ = f2.cancel();
    try testing.expect(f2.state.isCancelled());

    // pending -> running -> error
    var f3 = Future(i32).init(testing.allocator);
    defer f3.deinit();

    try testing.expect(f3.state.isPending());
    try f3.setRunning();
    try f3.setException(error.Failure);
    try testing.expect(f3.state.hasException());
}

test "exception_format" {
    const exc = FutureException.withMessage(error.InvalidArgument, "value must be positive");
    const formatted = try exc.format(testing.allocator);
    defer testing.allocator.free(formatted);

    try testing.expectEqualStrings("InvalidArgument: value must be positive", formatted);
}
