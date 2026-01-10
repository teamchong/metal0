//! test.test_concurrent_futures.test_cancel - Future cancel tests
//!
//! Tests for future cancellation including cancel() method, running state
//! management, CancelledError handling, and cancellation propagation.

const std = @import("std");
const testing = std.testing;

/// Error types for cancel operations
pub const CancelError = error{
    CancelledError,
    AlreadyRunning,
    AlreadyCompleted,
    CancelNotAllowed,
    CancelFailed,
};

/// Reason for cancellation
pub const CancelReason = enum {
    user_requested,
    timeout_expired,
    executor_shutdown,
    parent_cancelled,
    resource_unavailable,
    system_error,

    pub fn description(self: CancelReason) []const u8 {
        return switch (self) {
            .user_requested => "Cancelled by user request",
            .timeout_expired => "Cancelled due to timeout",
            .executor_shutdown => "Cancelled due to executor shutdown",
            .parent_cancelled => "Cancelled because parent was cancelled",
            .resource_unavailable => "Cancelled due to resource unavailability",
            .system_error => "Cancelled due to system error",
        };
    }

    pub fn isRecoverable(self: CancelReason) bool {
        return self == .user_requested or self == .timeout_expired;
    }
};

/// Options for cancel operations
pub const CancelOptions = struct {
    reason: CancelReason = .user_requested,
    message: ?[]const u8 = null,
    propagate_to_children: bool = true,
    wait_for_running: bool = false,
    force: bool = false,

    pub fn init() CancelOptions {
        return .{};
    }

    pub fn withReason(reason: CancelReason) CancelOptions {
        return .{ .reason = reason };
    }

    pub fn withMessage(message: []const u8) CancelOptions {
        return .{ .message = message };
    }

    pub fn forced() CancelOptions {
        return .{ .force = true };
    }

    pub fn noPropagation() CancelOptions {
        return .{ .propagate_to_children = false };
    }
};

/// Result of a cancel operation
pub const CancelResult = struct {
    success: bool = false,
    was_running: bool = false,
    was_pending: bool = false,
    was_already_done: bool = false,
    reason: ?CancelReason = null,
    cancelled_children: usize = 0,

    pub fn succeeded(reason: CancelReason) CancelResult {
        return .{
            .success = true,
            .reason = reason,
        };
    }

    pub fn failedAlreadyRunning() CancelResult {
        return .{
            .success = false,
            .was_running = true,
        };
    }

    pub fn failedAlreadyDone() CancelResult {
        return .{
            .success = false,
            .was_already_done = true,
        };
    }
};

/// Cancellation token for cooperative cancellation
pub const CancellationToken = struct {
    const Self = @This();

    cancelled: bool = false,
    reason: ?CancelReason = null,
    cancel_time: ?i64 = null,
    message: ?[]const u8 = null,

    pub fn init() Self {
        return .{};
    }

    pub fn cancel(self: *Self, reason: CancelReason) void {
        if (!self.cancelled) {
            self.cancelled = true;
            self.reason = reason;
            self.cancel_time = std.time.milliTimestamp();
        }
    }

    pub fn cancelWithMessage(self: *Self, reason: CancelReason, message: []const u8) void {
        self.cancel(reason);
        self.message = message;
    }

    pub fn isCancellationRequested(self: Self) bool {
        return self.cancelled;
    }

    pub fn throwIfCancelled(self: Self) CancelError!void {
        if (self.cancelled) {
            return CancelError.CancelledError;
        }
    }

    pub fn reset(self: *Self) void {
        self.cancelled = false;
        self.reason = null;
        self.cancel_time = null;
        self.message = null;
    }
};

/// Linked cancellation tokens for hierarchical cancellation
pub const LinkedCancellationToken = struct {
    const Self = @This();

    token: CancellationToken = .{},
    parent: ?*Self = null,
    children: std.ArrayList(*Self),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .children = std.ArrayList(*Self).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn initWithParent(allocator: std.mem.Allocator, parent: *Self) !Self {
        var self = init(allocator);
        self.parent = parent;
        try parent.children.append(&self);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.children.deinit();
    }

    pub fn cancel(self: *Self, reason: CancelReason, propagate: bool) usize {
        if (self.token.cancelled) return 0;

        self.token.cancel(reason);
        var cancelled_count: usize = 1;

        if (propagate) {
            for (self.children.items) |child| {
                cancelled_count += child.cancel(.parent_cancelled, true);
            }
        }

        return cancelled_count;
    }

    pub fn isCancellationRequested(self: Self) bool {
        if (self.token.cancelled) return true;
        if (self.parent) |p| {
            return p.isCancellationRequested();
        }
        return false;
    }
};

/// Cancellable future state
pub fn CancellableFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const State = enum {
            pending,
            running,
            cancelled,
            completed,
            failed,

            pub fn canBeCancelled(self: State) bool {
                return self == .pending;
            }

            pub fn isDone(self: State) bool {
                return self == .cancelled or self == .completed or self == .failed;
            }
        };

        id: u64,
        state: State = .pending,
        result: ?T = null,
        exception: ?anyerror = null,
        cancel_info: ?CancelInfo = null,
        creation_time: i64,

        pub const CancelInfo = struct {
            reason: CancelReason,
            message: ?[]const u8 = null,
            cancelled_at: i64,
        };

        pub fn init(id: u64) Self {
            return .{
                .id = id,
                .creation_time = std.time.milliTimestamp(),
            };
        }

        pub fn cancel(self: *Self, options: CancelOptions) CancelResult {
            return self.cancelWithReason(options.reason, options.message);
        }

        pub fn cancelWithReason(self: *Self, reason: CancelReason, message: ?[]const u8) CancelResult {
            if (self.state.isDone()) {
                return CancelResult.failedAlreadyDone();
            }

            if (self.state == .running) {
                return CancelResult.failedAlreadyRunning();
            }

            self.state = .cancelled;
            self.cancel_info = .{
                .reason = reason,
                .message = message,
                .cancelled_at = std.time.milliTimestamp(),
            };

            return CancelResult.succeeded(reason);
        }

        pub fn setRunning(self: *Self) CancelError!void {
            if (self.state == .cancelled) {
                return CancelError.CancelledError;
            }
            if (self.state != .pending) {
                return CancelError.AlreadyRunning;
            }
            self.state = .running;
        }

        pub fn setResult(self: *Self, value: T) CancelError!void {
            if (self.state == .cancelled) {
                return CancelError.CancelledError;
            }
            self.result = value;
            self.state = .completed;
        }

        pub fn setException(self: *Self, err: anyerror) void {
            self.exception = err;
            self.state = .failed;
        }

        pub fn cancelled(self: Self) bool {
            return self.state == .cancelled;
        }

        pub fn done(self: Self) bool {
            return self.state.isDone();
        }

        pub fn running(self: Self) bool {
            return self.state == .running;
        }

        pub fn getResult(self: Self) CancelError!T {
            if (self.state == .cancelled) {
                return CancelError.CancelledError;
            }
            if (self.result) |r| {
                return r;
            }
            if (self.exception) |e| {
                return e;
            }
            return CancelError.CancelFailed;
        }

        pub fn getCancelReason(self: Self) ?CancelReason {
            if (self.cancel_info) |info| {
                return info.reason;
            }
            return null;
        }
    };
}

/// Cancel scope for managing multiple cancellable operations
pub fn CancelScope(comptime T: type) type {
    return struct {
        const Self = @This();

        futures: std.ArrayList(*CancellableFuture(T)),
        allocator: std.mem.Allocator,
        cancelled: bool = false,
        cancel_reason: ?CancelReason = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .futures = std.ArrayList(*CancellableFuture(T)).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.futures.deinit();
        }

        pub fn add(self: *Self, future: *CancellableFuture(T)) !void {
            try self.futures.append(future);
        }

        pub fn cancelAll(self: *Self, reason: CancelReason) usize {
            if (self.cancelled) return 0;

            self.cancelled = true;
            self.cancel_reason = reason;

            var cancelled_count: usize = 0;
            for (self.futures.items) |future| {
                const result = future.cancel(CancelOptions.withReason(reason));
                if (result.success) {
                    cancelled_count += 1;
                }
            }
            return cancelled_count;
        }

        pub fn count(self: Self) usize {
            return self.futures.items.len;
        }

        pub fn getPendingCount(self: Self) usize {
            var pending: usize = 0;
            for (self.futures.items) |f| {
                if (f.state == .pending) pending += 1;
            }
            return pending;
        }

        pub fn getCancelledCount(self: Self) usize {
            var count_val: usize = 0;
            for (self.futures.items) |f| {
                if (f.cancelled()) count_val += 1;
            }
            return count_val;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "cancel_reason_descriptions" {
    try testing.expectEqualStrings("Cancelled by user request", CancelReason.user_requested.description());
    try testing.expectEqualStrings("Cancelled due to timeout", CancelReason.timeout_expired.description());
    try testing.expectEqualStrings("Cancelled due to executor shutdown", CancelReason.executor_shutdown.description());
}

test "cancel_reason_recoverable" {
    try testing.expect(CancelReason.user_requested.isRecoverable());
    try testing.expect(CancelReason.timeout_expired.isRecoverable());
    try testing.expect(!CancelReason.system_error.isRecoverable());
    try testing.expect(!CancelReason.executor_shutdown.isRecoverable());
}

test "cancel_options_default" {
    const opts = CancelOptions.init();
    try testing.expectEqual(CancelReason.user_requested, opts.reason);
    try testing.expect(opts.propagate_to_children);
    try testing.expect(!opts.force);
}

test "cancel_options_with_reason" {
    const opts = CancelOptions.withReason(.timeout_expired);
    try testing.expectEqual(CancelReason.timeout_expired, opts.reason);
}

test "cancel_options_forced" {
    const opts = CancelOptions.forced();
    try testing.expect(opts.force);
}

test "cancel_result_succeeded" {
    const result = CancelResult.succeeded(.user_requested);
    try testing.expect(result.success);
    try testing.expectEqual(CancelReason.user_requested, result.reason.?);
}

test "cancel_result_failed_running" {
    const result = CancelResult.failedAlreadyRunning();
    try testing.expect(!result.success);
    try testing.expect(result.was_running);
}

test "cancellation_token_basic" {
    var token = CancellationToken.init();

    try testing.expect(!token.isCancellationRequested());
    try token.throwIfCancelled();

    token.cancel(.user_requested);
    try testing.expect(token.isCancellationRequested());
    try testing.expectEqual(CancelReason.user_requested, token.reason.?);
    try testing.expectError(CancelError.CancelledError, token.throwIfCancelled());
}

test "cancellation_token_with_message" {
    var token = CancellationToken.init();
    token.cancelWithMessage(.timeout_expired, "Operation took too long");

    try testing.expect(token.isCancellationRequested());
    try testing.expectEqualStrings("Operation took too long", token.message.?);
}

test "cancellation_token_reset" {
    var token = CancellationToken.init();
    token.cancel(.user_requested);

    try testing.expect(token.isCancellationRequested());

    token.reset();
    try testing.expect(!token.isCancellationRequested());
    try testing.expect(token.reason == null);
}

test "cancellable_future_cancel_pending" {
    var future = CancellableFuture(i32).init(1);

    try testing.expect(!future.cancelled());
    try testing.expect(!future.done());

    const result = future.cancel(CancelOptions.init());
    try testing.expect(result.success);
    try testing.expect(future.cancelled());
    try testing.expect(future.done());
}

test "cancellable_future_cannot_cancel_running" {
    var future = CancellableFuture(i32).init(1);
    try future.setRunning();

    const result = future.cancel(CancelOptions.init());
    try testing.expect(!result.success);
    try testing.expect(result.was_running);
    try testing.expect(!future.cancelled());
}

test "cancellable_future_cannot_cancel_completed" {
    var future = CancellableFuture(i32).init(1);
    try future.setResult(42);

    const result = future.cancel(CancelOptions.init());
    try testing.expect(!result.success);
    try testing.expect(result.was_already_done);
}

test "cancellable_future_get_result_cancelled" {
    var future = CancellableFuture(i32).init(1);
    _ = future.cancel(CancelOptions.init());

    try testing.expectError(CancelError.CancelledError, future.getResult());
}

test "cancellable_future_set_running_cancelled" {
    var future = CancellableFuture(i32).init(1);
    _ = future.cancel(CancelOptions.init());

    try testing.expectError(CancelError.CancelledError, future.setRunning());
}

test "cancellable_future_cancel_reason" {
    var future = CancellableFuture(i32).init(1);
    _ = future.cancelWithReason(.executor_shutdown, "Executor is shutting down");

    try testing.expectEqual(CancelReason.executor_shutdown, future.getCancelReason().?);
    try testing.expectEqualStrings("Executor is shutting down", future.cancel_info.?.message.?);
}

test "cancel_scope_cancel_all" {
    var f1 = CancellableFuture(i32).init(1);
    var f2 = CancellableFuture(i32).init(2);
    var f3 = CancellableFuture(i32).init(3);

    // Set f2 to running so it can't be cancelled
    try f2.setRunning();

    var scope = CancelScope(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.add(&f1);
    try scope.add(&f2);
    try scope.add(&f3);

    const cancelled = scope.cancelAll(.executor_shutdown);

    try testing.expectEqual(@as(usize, 2), cancelled); // f1 and f3
    try testing.expect(f1.cancelled());
    try testing.expect(!f2.cancelled()); // Was running
    try testing.expect(f3.cancelled());
}

test "cancel_scope_counts" {
    var f1 = CancellableFuture(i32).init(1);
    var f2 = CancellableFuture(i32).init(2);

    var scope = CancelScope(i32).init(testing.allocator);
    defer scope.deinit();

    try scope.add(&f1);
    try scope.add(&f2);

    try testing.expectEqual(@as(usize, 2), scope.count());
    try testing.expectEqual(@as(usize, 2), scope.getPendingCount());
    try testing.expectEqual(@as(usize, 0), scope.getCancelledCount());

    _ = f1.cancel(CancelOptions.init());

    try testing.expectEqual(@as(usize, 1), scope.getPendingCount());
    try testing.expectEqual(@as(usize, 1), scope.getCancelledCount());
}

test "future_state_can_be_cancelled" {
    try testing.expect(CancellableFuture(i32).State.pending.canBeCancelled());
    try testing.expect(!CancellableFuture(i32).State.running.canBeCancelled());
    try testing.expect(!CancellableFuture(i32).State.completed.canBeCancelled());
    try testing.expect(!CancellableFuture(i32).State.cancelled.canBeCancelled());
}
