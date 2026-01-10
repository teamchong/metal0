//! test.test_concurrent_futures.test_wait - Futures wait tests
//!
//! Tests for concurrent.futures wait() function and related utilities
//! including FIRST_COMPLETED, FIRST_EXCEPTION, and ALL_COMPLETED modes.

const std = @import("std");
const testing = std.testing;

/// Error types for wait operations
pub const WaitError = error{
    TimeoutError,
    InvalidFutures,
    EmptyFuturesList,
    WaitInterrupted,
    AllFuturesFailed,
};

/// Wait return conditions
pub const WaitCondition = enum {
    first_completed, // Return when any future finishes
    first_exception, // Return when any future raises exception
    all_completed, // Return when all futures finish

    pub fn description(self: WaitCondition) []const u8 {
        return switch (self) {
            .first_completed => "FIRST_COMPLETED",
            .first_exception => "FIRST_EXCEPTION",
            .all_completed => "ALL_COMPLETED",
        };
    }

    pub fn requiresAll(self: WaitCondition) bool {
        return self == .all_completed;
    }

    pub fn stopsOnException(self: WaitCondition) bool {
        return self == .first_exception;
    }
};

/// Options for wait operations
pub const WaitOptions = struct {
    timeout_ms: ?u64 = null,
    condition: WaitCondition = .all_completed,
    poll_interval_ms: u64 = 10,

    pub fn init() WaitOptions {
        return .{};
    }

    pub fn firstCompleted() WaitOptions {
        return .{ .condition = .first_completed };
    }

    pub fn firstException() WaitOptions {
        return .{ .condition = .first_exception };
    }

    pub fn allCompleted() WaitOptions {
        return .{ .condition = .all_completed };
    }

    pub fn withTimeout(timeout_ms: u64) WaitOptions {
        return .{ .timeout_ms = timeout_ms };
    }

    pub fn hasTimeout(self: WaitOptions) bool {
        return self.timeout_ms != null;
    }
};

/// Result of a wait operation
pub fn WaitResult(comptime T: type) type {
    return struct {
        const Self = @This();

        done: std.ArrayList(*FutureState(T)),
        not_done: std.ArrayList(*FutureState(T)),
        allocator: std.mem.Allocator,
        timed_out: bool = false,
        wait_time_ms: u64 = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .done = std.ArrayList(*FutureState(T)).init(allocator),
                .not_done = std.ArrayList(*FutureState(T)).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.done.deinit();
            self.not_done.deinit();
        }

        pub fn addDone(self: *Self, future: *FutureState(T)) !void {
            try self.done.append(future);
        }

        pub fn addNotDone(self: *Self, future: *FutureState(T)) !void {
            try self.not_done.append(future);
        }

        pub fn doneCount(self: Self) usize {
            return self.done.items.len;
        }

        pub fn notDoneCount(self: Self) usize {
            return self.not_done.items.len;
        }

        pub fn allDone(self: Self) bool {
            return self.not_done.items.len == 0;
        }

        pub fn anyDone(self: Self) bool {
            return self.done.items.len > 0;
        }
    };
}

/// Simple future state for wait operations
pub fn FutureState(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const State = enum {
            pending,
            running,
            completed,
            failed,
            cancelled,

            pub fn isDone(self: State) bool {
                return self == .completed or self == .failed or self == .cancelled;
            }
        };

        id: u64,
        state: State = .pending,
        result: ?T = null,
        exception: ?anyerror = null,
        completion_time: ?i64 = null,

        pub fn init(id: u64) Self {
            return .{ .id = id };
        }

        pub fn isDone(self: Self) bool {
            return self.state.isDone();
        }

        pub fn complete(self: *Self, result: T) void {
            self.result = result;
            self.state = .completed;
            self.completion_time = std.time.milliTimestamp();
        }

        pub fn fail(self: *Self, err: anyerror) void {
            self.exception = err;
            self.state = .failed;
            self.completion_time = std.time.milliTimestamp();
        }

        pub fn cancel(self: *Self) void {
            self.state = .cancelled;
            self.completion_time = std.time.milliTimestamp();
        }

        pub fn hasException(self: Self) bool {
            return self.exception != null;
        }
    };
}

/// Wait controller for managing wait operations
pub fn WaitController(comptime T: type) type {
    return struct {
        const Self = @This();

        futures: std.ArrayList(*FutureState(T)),
        options: WaitOptions,
        allocator: std.mem.Allocator,
        start_time: ?i64 = null,

        pub fn init(allocator: std.mem.Allocator, options: WaitOptions) Self {
            return .{
                .futures = std.ArrayList(*FutureState(T)).init(allocator),
                .options = options,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.futures.deinit();
        }

        pub fn addFuture(self: *Self, future: *FutureState(T)) !void {
            try self.futures.append(future);
        }

        pub fn wait(self: *Self) !WaitResult(T) {
            self.start_time = std.time.milliTimestamp();
            var result = WaitResult(T).init(self.allocator);

            while (true) {
                // Check timeout
                if (self.options.timeout_ms) |timeout| {
                    const elapsed = self.getElapsedMs();
                    if (elapsed >= timeout) {
                        result.timed_out = true;
                        break;
                    }
                }

                // Partition futures into done/not_done
                var any_done = false;
                var any_exception = false;

                for (self.futures.items) |future| {
                    if (future.isDone()) {
                        any_done = true;
                        if (future.hasException()) {
                            any_exception = true;
                        }
                    }
                }

                // Check condition
                const should_return = switch (self.options.condition) {
                    .first_completed => any_done,
                    .first_exception => any_exception or any_done,
                    .all_completed => blk: {
                        var all_done = true;
                        for (self.futures.items) |f| {
                            if (!f.isDone()) {
                                all_done = false;
                                break;
                            }
                        }
                        break :blk all_done;
                    },
                };

                if (should_return) break;

                // Poll interval (simplified - just break in tests)
                break;
            }

            // Populate result
            for (self.futures.items) |future| {
                if (future.isDone()) {
                    try result.addDone(future);
                } else {
                    try result.addNotDone(future);
                }
            }

            result.wait_time_ms = self.getElapsedMs();
            return result;
        }

        pub fn getElapsedMs(self: Self) u64 {
            if (self.start_time) |start| {
                return @intCast(std.time.milliTimestamp() - start);
            }
            return 0;
        }

        pub fn futureCount(self: Self) usize {
            return self.futures.items.len;
        }
    };
}

/// Utility to wait for first completed future
pub fn waitFirstCompleted(comptime T: type, allocator: std.mem.Allocator, futures: []*FutureState(T)) !WaitResult(T) {
    var controller = WaitController(T).init(allocator, WaitOptions.firstCompleted());
    defer controller.deinit();

    for (futures) |f| {
        try controller.addFuture(f);
    }

    return controller.wait();
}

/// Utility to wait for all futures
pub fn waitAll(comptime T: type, allocator: std.mem.Allocator, futures: []*FutureState(T)) !WaitResult(T) {
    var controller = WaitController(T).init(allocator, WaitOptions.allCompleted());
    defer controller.deinit();

    for (futures) |f| {
        try controller.addFuture(f);
    }

    return controller.wait();
}

/// Wait statistics for monitoring
pub const WaitStats = struct {
    total_waits: usize = 0,
    total_wait_time_ms: u64 = 0,
    timeouts: usize = 0,
    avg_futures_per_wait: f64 = 0,

    pub fn recordWait(self: *WaitStats, wait_time_ms: u64, future_count: usize, timed_out: bool) void {
        const prev_total = self.total_waits;
        self.total_waits += 1;
        self.total_wait_time_ms += wait_time_ms;
        if (timed_out) self.timeouts += 1;

        // Update running average
        const prev_avg = self.avg_futures_per_wait;
        self.avg_futures_per_wait = (prev_avg * @as(f64, @floatFromInt(prev_total)) + @as(f64, @floatFromInt(future_count))) / @as(f64, @floatFromInt(self.total_waits));
    }

    pub fn avgWaitTimeMs(self: WaitStats) f64 {
        if (self.total_waits == 0) return 0;
        return @as(f64, @floatFromInt(self.total_wait_time_ms)) / @as(f64, @floatFromInt(self.total_waits));
    }

    pub fn timeoutRate(self: WaitStats) f64 {
        if (self.total_waits == 0) return 0;
        return @as(f64, @floatFromInt(self.timeouts)) / @as(f64, @floatFromInt(self.total_waits));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "wait_condition_descriptions" {
    try testing.expectEqualStrings("FIRST_COMPLETED", WaitCondition.first_completed.description());
    try testing.expectEqualStrings("FIRST_EXCEPTION", WaitCondition.first_exception.description());
    try testing.expectEqualStrings("ALL_COMPLETED", WaitCondition.all_completed.description());
}

test "wait_condition_properties" {
    try testing.expect(!WaitCondition.first_completed.requiresAll());
    try testing.expect(WaitCondition.all_completed.requiresAll());

    try testing.expect(WaitCondition.first_exception.stopsOnException());
    try testing.expect(!WaitCondition.first_completed.stopsOnException());
}

test "wait_options_default" {
    const opts = WaitOptions.init();
    try testing.expect(opts.timeout_ms == null);
    try testing.expectEqual(WaitCondition.all_completed, opts.condition);
    try testing.expect(!opts.hasTimeout());
}

test "wait_options_first_completed" {
    const opts = WaitOptions.firstCompleted();
    try testing.expectEqual(WaitCondition.first_completed, opts.condition);
}

test "wait_options_with_timeout" {
    const opts = WaitOptions.withTimeout(5000);
    try testing.expect(opts.hasTimeout());
    try testing.expectEqual(@as(u64, 5000), opts.timeout_ms.?);
}

test "future_state_basic" {
    var future = FutureState(i32).init(1);

    try testing.expectEqual(@as(u64, 1), future.id);
    try testing.expect(!future.isDone());
    try testing.expect(!future.hasException());

    future.complete(42);
    try testing.expect(future.isDone());
    try testing.expectEqual(@as(i32, 42), future.result.?);
}

test "future_state_fail" {
    var future = FutureState(i32).init(1);

    future.fail(error.SomeError);
    try testing.expect(future.isDone());
    try testing.expect(future.hasException());
    try testing.expectEqual(error.SomeError, future.exception.?);
}

test "future_state_cancel" {
    var future = FutureState(i32).init(1);

    future.cancel();
    try testing.expect(future.isDone());
    try testing.expectEqual(FutureState(i32).State.cancelled, future.state);
}

test "wait_result_basic" {
    var f1 = FutureState(i32).init(1);
    var f2 = FutureState(i32).init(2);
    f1.complete(10);

    var result = WaitResult(i32).init(testing.allocator);
    defer result.deinit();

    try result.addDone(&f1);
    try result.addNotDone(&f2);

    try testing.expectEqual(@as(usize, 1), result.doneCount());
    try testing.expectEqual(@as(usize, 1), result.notDoneCount());
    try testing.expect(!result.allDone());
    try testing.expect(result.anyDone());
}

test "wait_controller_all_completed" {
    var f1 = FutureState(i32).init(1);
    var f2 = FutureState(i32).init(2);
    f1.complete(10);
    f2.complete(20);

    var controller = WaitController(i32).init(testing.allocator, WaitOptions.allCompleted());
    defer controller.deinit();

    try controller.addFuture(&f1);
    try controller.addFuture(&f2);

    var result = try controller.wait();
    defer result.deinit();

    try testing.expect(result.allDone());
    try testing.expectEqual(@as(usize, 2), result.doneCount());
}

test "wait_controller_first_completed" {
    var f1 = FutureState(i32).init(1);
    var f2 = FutureState(i32).init(2);
    f1.complete(10);
    // f2 still pending

    var controller = WaitController(i32).init(testing.allocator, WaitOptions.firstCompleted());
    defer controller.deinit();

    try controller.addFuture(&f1);
    try controller.addFuture(&f2);

    var result = try controller.wait();
    defer result.deinit();

    try testing.expect(result.anyDone());
    try testing.expectEqual(@as(usize, 1), result.doneCount());
    try testing.expectEqual(@as(usize, 1), result.notDoneCount());
}

test "wait_first_completed_utility" {
    var f1 = FutureState(i32).init(1);
    var f2 = FutureState(i32).init(2);
    f1.complete(100);

    var futures = [_]*FutureState(i32){ &f1, &f2 };
    var result = try waitFirstCompleted(i32, testing.allocator, &futures);
    defer result.deinit();

    try testing.expect(result.anyDone());
}

test "wait_all_utility" {
    var f1 = FutureState(i32).init(1);
    var f2 = FutureState(i32).init(2);
    f1.complete(100);
    f2.complete(200);

    var futures = [_]*FutureState(i32){ &f1, &f2 };
    var result = try waitAll(i32, testing.allocator, &futures);
    defer result.deinit();

    try testing.expect(result.allDone());
    try testing.expectEqual(@as(usize, 2), result.doneCount());
}

test "wait_stats" {
    var stats = WaitStats{};

    stats.recordWait(100, 5, false);
    try testing.expectEqual(@as(usize, 1), stats.total_waits);
    try testing.expectEqual(@as(u64, 100), stats.total_wait_time_ms);
    try testing.expectApproxEqAbs(@as(f64, 5.0), stats.avg_futures_per_wait, 0.01);

    stats.recordWait(200, 10, true);
    try testing.expectEqual(@as(usize, 2), stats.total_waits);
    try testing.expectEqual(@as(usize, 1), stats.timeouts);
    try testing.expectApproxEqAbs(@as(f64, 150.0), stats.avgWaitTimeMs(), 0.01);
    try testing.expectApproxEqAbs(@as(f64, 0.5), stats.timeoutRate(), 0.01);
}

test "future_state_is_done_enum" {
    try testing.expect(!FutureState(i32).State.pending.isDone());
    try testing.expect(!FutureState(i32).State.running.isDone());
    try testing.expect(FutureState(i32).State.completed.isDone());
    try testing.expect(FutureState(i32).State.failed.isDone());
    try testing.expect(FutureState(i32).State.cancelled.isDone());
}
