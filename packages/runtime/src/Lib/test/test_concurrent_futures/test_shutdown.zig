//! test.test_concurrent_futures.test_shutdown - Executor shutdown tests
//!
//! Tests for executor shutdown behavior including wait parameter,
//! cancel_futures option, and graceful vs immediate shutdown.

const std = @import("std");
const testing = std.testing;

/// Error types for shutdown operations
pub const ShutdownError = error{
    AlreadyShutdown,
    ShutdownInProgress,
    ShutdownTimeout,
    TasksStillRunning,
    ShutdownFailed,
};

/// Shutdown mode for executor termination
pub const ShutdownMode = enum {
    graceful, // Wait for running tasks to complete
    immediate, // Cancel all tasks immediately
    soft, // Wait with timeout, then force

    pub fn waitsForTasks(self: ShutdownMode) bool {
        return self == .graceful or self == .soft;
    }

    pub fn cancelsOnTimeout(self: ShutdownMode) bool {
        return self == .soft;
    }
};

/// Options for executor shutdown
pub const ShutdownOptions = struct {
    wait: bool = true,
    cancel_futures: bool = false,
    timeout_ms: ?u64 = null,
    mode: ShutdownMode = .graceful,

    pub fn init() ShutdownOptions {
        return .{};
    }

    pub fn immediate() ShutdownOptions {
        return .{
            .wait = false,
            .cancel_futures = true,
            .mode = .immediate,
        };
    }

    pub fn graceful() ShutdownOptions {
        return .{
            .wait = true,
            .cancel_futures = false,
            .mode = .graceful,
        };
    }

    pub fn withTimeout(timeout_ms: u64) ShutdownOptions {
        return .{
            .wait = true,
            .timeout_ms = timeout_ms,
            .mode = .soft,
        };
    }

    pub fn shouldWait(self: ShutdownOptions) bool {
        return self.wait and !self.cancel_futures;
    }

    pub fn shouldCancelFutures(self: ShutdownOptions) bool {
        return self.cancel_futures;
    }

    pub fn hasTimeout(self: ShutdownOptions) bool {
        return self.timeout_ms != null;
    }
};

/// Result of a shutdown operation
pub const ShutdownResult = struct {
    success: bool = false,
    completed_tasks: usize = 0,
    cancelled_tasks: usize = 0,
    pending_tasks: usize = 0,
    duration_ms: i64 = 0,
    timed_out: bool = false,
    error_message: ?[]const u8 = null,

    pub fn init() ShutdownResult {
        return .{};
    }

    pub fn succeeded() ShutdownResult {
        return .{ .success = true };
    }

    pub fn failed(message: []const u8) ShutdownResult {
        return .{ .success = false, .error_message = message };
    }

    pub fn timedOut(pending: usize) ShutdownResult {
        return .{
            .success = false,
            .pending_tasks = pending,
            .timed_out = true,
        };
    }

    pub fn totalTasks(self: ShutdownResult) usize {
        return self.completed_tasks + self.cancelled_tasks + self.pending_tasks;
    }

    pub fn wasClean(self: ShutdownResult) bool {
        return self.success and self.pending_tasks == 0 and !self.timed_out;
    }
};

/// Tracks shutdown state and progress
pub const ShutdownTracker = struct {
    const Self = @This();

    state: State = .running,
    shutdown_requested_at: ?i64 = null,
    shutdown_completed_at: ?i64 = null,
    options: ShutdownOptions = .{},
    result: ShutdownResult = .{},

    pub const State = enum {
        running,
        shutdown_requested,
        draining,
        cancelling,
        completed,
        failed,

        pub fn isShuttingDown(self: State) bool {
            return self != .running and self != .completed and self != .failed;
        }

        pub fn isTerminal(self: State) bool {
            return self == .completed or self == .failed;
        }
    };

    pub fn init() Self {
        return .{};
    }

    pub fn requestShutdown(self: *Self, options: ShutdownOptions) ShutdownError!void {
        if (self.state.isTerminal()) {
            return ShutdownError.AlreadyShutdown;
        }
        if (self.state.isShuttingDown()) {
            return ShutdownError.ShutdownInProgress;
        }

        self.state = .shutdown_requested;
        self.shutdown_requested_at = std.time.milliTimestamp();
        self.options = options;

        if (options.cancel_futures) {
            self.state = .cancelling;
        } else if (options.wait) {
            self.state = .draining;
        }
    }

    pub fn recordTaskCompleted(self: *Self) void {
        self.result.completed_tasks += 1;
    }

    pub fn recordTaskCancelled(self: *Self) void {
        self.result.cancelled_tasks += 1;
    }

    pub fn setPendingTasks(self: *Self, count: usize) void {
        self.result.pending_tasks = count;
    }

    pub fn complete(self: *Self, success: bool) void {
        self.state = if (success) .completed else .failed;
        self.shutdown_completed_at = std.time.milliTimestamp();
        self.result.success = success;

        if (self.shutdown_requested_at) |start| {
            self.result.duration_ms = self.shutdown_completed_at.? - start;
        }
    }

    pub fn getElapsedTime(self: Self) i64 {
        if (self.shutdown_requested_at) |start| {
            const end = self.shutdown_completed_at orelse std.time.milliTimestamp();
            return end - start;
        }
        return 0;
    }

    pub fn isShutdown(self: Self) bool {
        return self.state.isTerminal();
    }

    pub fn isInProgress(self: Self) bool {
        return self.state.isShuttingDown();
    }
};

/// Manages pending futures during shutdown
pub fn PendingFuturesManager(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const FutureEntry = struct {
            id: u64,
            submitted_at: i64,
            result: ?T = null,
            cancelled: bool = false,
            completed: bool = false,
        };

        futures: std.ArrayList(FutureEntry),
        allocator: std.mem.Allocator,
        next_id: u64 = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .futures = std.ArrayList(FutureEntry).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.futures.deinit();
        }

        pub fn addFuture(self: *Self) !u64 {
            const id = self.next_id;
            self.next_id += 1;
            try self.futures.append(.{
                .id = id,
                .submitted_at = std.time.milliTimestamp(),
            });
            return id;
        }

        pub fn completeFuture(self: *Self, id: u64, result: T) bool {
            for (self.futures.items) |*f| {
                if (f.id == id and !f.cancelled and !f.completed) {
                    f.result = result;
                    f.completed = true;
                    return true;
                }
            }
            return false;
        }

        pub fn cancelFuture(self: *Self, id: u64) bool {
            for (self.futures.items) |*f| {
                if (f.id == id and !f.completed) {
                    f.cancelled = true;
                    return true;
                }
            }
            return false;
        }

        pub fn cancelAll(self: *Self) usize {
            var count: usize = 0;
            for (self.futures.items) |*f| {
                if (!f.completed and !f.cancelled) {
                    f.cancelled = true;
                    count += 1;
                }
            }
            return count;
        }

        pub fn getPendingCount(self: Self) usize {
            var count: usize = 0;
            for (self.futures.items) |f| {
                if (!f.completed and !f.cancelled) {
                    count += 1;
                }
            }
            return count;
        }

        pub fn getCompletedCount(self: Self) usize {
            var count: usize = 0;
            for (self.futures.items) |f| {
                if (f.completed) {
                    count += 1;
                }
            }
            return count;
        }

        pub fn getCancelledCount(self: Self) usize {
            var count: usize = 0;
            for (self.futures.items) |f| {
                if (f.cancelled) {
                    count += 1;
                }
            }
            return count;
        }

        pub fn clear(self: *Self) void {
            self.futures.clearRetainingCapacity();
        }
    };
}

/// Executor wrapper with shutdown support
pub const ShutdownableExecutor = struct {
    const Self = @This();

    tracker: ShutdownTracker = .{},
    active_tasks: usize = 0,
    max_workers: usize = 4,

    pub fn init(max_workers: usize) Self {
        return .{ .max_workers = max_workers };
    }

    pub fn submit(self: *Self) ShutdownError!void {
        if (self.tracker.state.isShuttingDown() or self.tracker.state.isTerminal()) {
            return ShutdownError.AlreadyShutdown;
        }
        self.active_tasks += 1;
    }

    pub fn completeTask(self: *Self) void {
        if (self.active_tasks > 0) {
            self.active_tasks -= 1;
            self.tracker.recordTaskCompleted();
        }
    }

    pub fn shutdown(self: *Self, options: ShutdownOptions) ShutdownResult {
        self.tracker.requestShutdown(options) catch |err| {
            return switch (err) {
                ShutdownError.AlreadyShutdown => ShutdownResult.failed("Already shutdown"),
                ShutdownError.ShutdownInProgress => ShutdownResult.failed("Shutdown in progress"),
                else => ShutdownResult.failed("Shutdown failed"),
            };
        };

        if (options.cancel_futures) {
            self.tracker.result.cancelled_tasks = self.active_tasks;
            self.active_tasks = 0;
        } else if (options.wait) {
            // Simulate waiting for tasks
            self.tracker.result.completed_tasks = self.active_tasks;
            self.active_tasks = 0;
        } else {
            self.tracker.setPendingTasks(self.active_tasks);
        }

        const success = self.active_tasks == 0;
        self.tracker.complete(success);
        return self.tracker.result;
    }

    pub fn isShutdown(self: Self) bool {
        return self.tracker.isShutdown();
    }

    pub fn getActiveTaskCount(self: Self) usize {
        return self.active_tasks;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "shutdown_options_default" {
    const opts = ShutdownOptions.init();
    try testing.expect(opts.wait);
    try testing.expect(!opts.cancel_futures);
    try testing.expect(opts.timeout_ms == null);
    try testing.expectEqual(ShutdownMode.graceful, opts.mode);
}

test "shutdown_options_immediate" {
    const opts = ShutdownOptions.immediate();
    try testing.expect(!opts.wait);
    try testing.expect(opts.cancel_futures);
    try testing.expectEqual(ShutdownMode.immediate, opts.mode);
    try testing.expect(!opts.shouldWait());
    try testing.expect(opts.shouldCancelFutures());
}

test "shutdown_options_graceful" {
    const opts = ShutdownOptions.graceful();
    try testing.expect(opts.wait);
    try testing.expect(!opts.cancel_futures);
    try testing.expect(opts.shouldWait());
    try testing.expect(!opts.shouldCancelFutures());
}

test "shutdown_options_with_timeout" {
    const opts = ShutdownOptions.withTimeout(5000);
    try testing.expect(opts.hasTimeout());
    try testing.expectEqual(@as(u64, 5000), opts.timeout_ms.?);
    try testing.expectEqual(ShutdownMode.soft, opts.mode);
}

test "shutdown_result_succeeded" {
    const result = ShutdownResult.succeeded();
    try testing.expect(result.success);
    try testing.expect(result.wasClean());
}

test "shutdown_result_failed" {
    const result = ShutdownResult.failed("Something went wrong");
    try testing.expect(!result.success);
    try testing.expectEqualStrings("Something went wrong", result.error_message.?);
}

test "shutdown_result_timed_out" {
    const result = ShutdownResult.timedOut(5);
    try testing.expect(!result.success);
    try testing.expect(result.timed_out);
    try testing.expectEqual(@as(usize, 5), result.pending_tasks);
}

test "shutdown_tracker_states" {
    var tracker = ShutdownTracker.init();

    try testing.expectEqual(ShutdownTracker.State.running, tracker.state);
    try testing.expect(!tracker.isShutdown());
    try testing.expect(!tracker.isInProgress());

    try tracker.requestShutdown(ShutdownOptions.graceful());
    try testing.expectEqual(ShutdownTracker.State.draining, tracker.state);
    try testing.expect(tracker.isInProgress());

    tracker.complete(true);
    try testing.expect(tracker.isShutdown());
    try testing.expect(tracker.result.success);
}

test "shutdown_tracker_cancelling" {
    var tracker = ShutdownTracker.init();

    try tracker.requestShutdown(ShutdownOptions.immediate());
    try testing.expectEqual(ShutdownTracker.State.cancelling, tracker.state);
}

test "shutdown_tracker_already_shutdown" {
    var tracker = ShutdownTracker.init();

    try tracker.requestShutdown(ShutdownOptions.graceful());
    tracker.complete(true);

    try testing.expectError(ShutdownError.AlreadyShutdown, tracker.requestShutdown(ShutdownOptions.graceful()));
}

test "shutdown_tracker_in_progress" {
    var tracker = ShutdownTracker.init();

    try tracker.requestShutdown(ShutdownOptions.graceful());

    try testing.expectError(ShutdownError.ShutdownInProgress, tracker.requestShutdown(ShutdownOptions.graceful()));
}

test "shutdown_tracker_task_tracking" {
    var tracker = ShutdownTracker.init();

    try tracker.requestShutdown(ShutdownOptions.graceful());

    tracker.recordTaskCompleted();
    tracker.recordTaskCompleted();
    tracker.recordTaskCancelled();

    try testing.expectEqual(@as(usize, 2), tracker.result.completed_tasks);
    try testing.expectEqual(@as(usize, 1), tracker.result.cancelled_tasks);
}

test "pending_futures_manager" {
    var manager = PendingFuturesManager(i32).init(testing.allocator);
    defer manager.deinit();

    const id1 = try manager.addFuture();
    const id2 = try manager.addFuture();
    const id3 = try manager.addFuture();

    try testing.expectEqual(@as(usize, 3), manager.getPendingCount());

    try testing.expect(manager.completeFuture(id1, 42));
    try testing.expectEqual(@as(usize, 2), manager.getPendingCount());
    try testing.expectEqual(@as(usize, 1), manager.getCompletedCount());

    try testing.expect(manager.cancelFuture(id2));
    try testing.expectEqual(@as(usize, 1), manager.getPendingCount());
    try testing.expectEqual(@as(usize, 1), manager.getCancelledCount());

    // id3 still pending
    try testing.expect(!manager.completeFuture(999, 0)); // Invalid ID
    _ = id3;
}

test "pending_futures_cancel_all" {
    var manager = PendingFuturesManager(i32).init(testing.allocator);
    defer manager.deinit();

    _ = try manager.addFuture();
    _ = try manager.addFuture();
    _ = try manager.addFuture();

    const cancelled = manager.cancelAll();
    try testing.expectEqual(@as(usize, 3), cancelled);
    try testing.expectEqual(@as(usize, 0), manager.getPendingCount());
    try testing.expectEqual(@as(usize, 3), manager.getCancelledCount());
}

test "shutdownable_executor_graceful" {
    var executor = ShutdownableExecutor.init(4);

    try executor.submit();
    try executor.submit();
    try testing.expectEqual(@as(usize, 2), executor.getActiveTaskCount());

    const result = executor.shutdown(ShutdownOptions.graceful());

    try testing.expect(result.success);
    try testing.expectEqual(@as(usize, 2), result.completed_tasks);
    try testing.expect(executor.isShutdown());
}

test "shutdownable_executor_immediate" {
    var executor = ShutdownableExecutor.init(4);

    try executor.submit();
    try executor.submit();
    try executor.submit();

    const result = executor.shutdown(ShutdownOptions.immediate());

    try testing.expect(result.success);
    try testing.expectEqual(@as(usize, 3), result.cancelled_tasks);
    try testing.expectEqual(@as(usize, 0), result.completed_tasks);
}

test "shutdownable_executor_reject_after_shutdown" {
    var executor = ShutdownableExecutor.init(4);

    _ = executor.shutdown(ShutdownOptions.graceful());

    try testing.expectError(ShutdownError.AlreadyShutdown, executor.submit());
}

test "shutdown_mode_properties" {
    try testing.expect(ShutdownMode.graceful.waitsForTasks());
    try testing.expect(ShutdownMode.soft.waitsForTasks());
    try testing.expect(!ShutdownMode.immediate.waitsForTasks());

    try testing.expect(ShutdownMode.soft.cancelsOnTimeout());
    try testing.expect(!ShutdownMode.graceful.cancelsOnTimeout());
}
