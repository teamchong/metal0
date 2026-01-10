//! test.test_concurrent_futures.test_as_completed - as_completed() iterator tests
//!
//! Tests for the as_completed() function which yields futures in completion order,
//! allowing processing of results as they become available.

const std = @import("std");
const testing = std.testing;

/// Error types for as_completed operations
pub const AsCompletedError = error{
    EmptyFuturesSet,
    TimeoutError,
    IterationComplete,
    InvalidFuture,
    AlreadyIterating,
};

/// State of a future for as_completed tracking
pub fn CompletionFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const State = enum {
            pending,
            running,
            completed,
            failed,
            cancelled,
        };

        id: u64,
        state: State = .pending,
        result: ?T = null,
        exception: ?anyerror = null,
        completion_time: ?i64 = null,
        yielded: bool = false,

        pub fn init(id: u64) Self {
            return .{ .id = id };
        }

        pub fn complete(self: *Self, value: T) void {
            self.result = value;
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

        pub fn isDone(self: Self) bool {
            return self.state == .completed or self.state == .failed or self.state == .cancelled;
        }

        pub fn isYielded(self: Self) bool {
            return self.yielded;
        }

        pub fn markYielded(self: *Self) void {
            self.yielded = true;
        }
    };
}

/// as_completed iterator that yields futures in completion order
pub fn AsCompletedIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        futures: std.ArrayList(*CompletionFuture(T)),
        allocator: std.mem.Allocator,
        timeout_ms: ?u64 = null,
        start_time: i64,
        yielded_count: usize = 0,
        completed: bool = false,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .futures = std.ArrayList(*CompletionFuture(T)).init(allocator),
                .allocator = allocator,
                .start_time = std.time.milliTimestamp(),
            };
        }

        pub fn initWithTimeout(allocator: std.mem.Allocator, timeout_ms: u64) Self {
            var iter = init(allocator);
            iter.timeout_ms = timeout_ms;
            return iter;
        }

        pub fn deinit(self: *Self) void {
            self.futures.deinit();
        }

        pub fn addFuture(self: *Self, future: *CompletionFuture(T)) !void {
            try self.futures.append(future);
        }

        pub fn addFutures(self: *Self, futures: []*CompletionFuture(T)) !void {
            for (futures) |f| {
                try self.futures.append(f);
            }
        }

        /// Get the next completed future
        pub fn next(self: *Self) AsCompletedError!?*CompletionFuture(T) {
            // Check if all futures have been yielded
            if (self.yielded_count >= self.futures.items.len) {
                self.completed = true;
                return null;
            }

            // Check timeout
            if (self.timeout_ms) |timeout| {
                const elapsed = std.time.milliTimestamp() - self.start_time;
                if (elapsed >= @as(i64, @intCast(timeout))) {
                    return AsCompletedError.TimeoutError;
                }
            }

            // Find the next completed, non-yielded future
            // Sort by completion time to get earliest completed first
            var earliest: ?*CompletionFuture(T) = null;
            var earliest_time: i64 = std.math.maxInt(i64);

            for (self.futures.items) |future| {
                if (future.isDone() and !future.isYielded()) {
                    if (future.completion_time) |ct| {
                        if (ct < earliest_time) {
                            earliest_time = ct;
                            earliest = future;
                        }
                    } else {
                        if (earliest == null) {
                            earliest = future;
                        }
                    }
                }
            }

            if (earliest) |f| {
                f.markYielded();
                self.yielded_count += 1;
                return f;
            }

            // No completed futures available yet
            return null;
        }

        /// Collect all completed futures
        pub fn collectCompleted(self: *Self) ![]*CompletionFuture(T) {
            var completed = std.ArrayList(*CompletionFuture(T)).init(self.allocator);

            while (try self.next()) |future| {
                try completed.append(future);
            }

            return completed.toOwnedSlice();
        }

        pub fn remainingCount(self: Self) usize {
            return self.futures.items.len - self.yielded_count;
        }

        pub fn totalCount(self: Self) usize {
            return self.futures.items.len;
        }

        pub fn yieldedCount(self: Self) usize {
            return self.yielded_count;
        }

        pub fn isComplete(self: Self) bool {
            return self.completed or self.yielded_count >= self.futures.items.len;
        }

        pub fn getElapsedMs(self: Self) i64 {
            return std.time.milliTimestamp() - self.start_time;
        }

        pub fn reset(self: *Self) void {
            for (self.futures.items) |f| {
                f.yielded = false;
            }
            self.yielded_count = 0;
            self.completed = false;
            self.start_time = std.time.milliTimestamp();
        }
    };
}

/// Batch wrapper for as_completed results
pub fn CompletedBatch(comptime T: type) type {
    return struct {
        const Self = @This();

        futures: []*CompletionFuture(T),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, futures: []*CompletionFuture(T)) Self {
            return .{
                .futures = futures,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.futures);
        }

        pub fn count(self: Self) usize {
            return self.futures.len;
        }

        pub fn getResults(self: Self, allocator: std.mem.Allocator) ![]T {
            var results = try allocator.alloc(T, self.futures.len);
            var i: usize = 0;

            for (self.futures) |f| {
                if (f.result) |r| {
                    results[i] = r;
                    i += 1;
                }
            }

            // Shrink to actual size
            return results[0..i];
        }

        pub fn getSuccessCount(self: Self) usize {
            var count_val: usize = 0;
            for (self.futures) |f| {
                if (f.state == .completed) count_val += 1;
            }
            return count_val;
        }

        pub fn getFailureCount(self: Self) usize {
            var count_val: usize = 0;
            for (self.futures) |f| {
                if (f.state == .failed) count_val += 1;
            }
            return count_val;
        }
    };
}

/// Options for as_completed
pub const AsCompletedOptions = struct {
    timeout_ms: ?u64 = null,
    yield_on_exception: bool = true,
    yield_on_cancel: bool = true,

    pub fn init() AsCompletedOptions {
        return .{};
    }

    pub fn withTimeout(timeout_ms: u64) AsCompletedOptions {
        return .{ .timeout_ms = timeout_ms };
    }

    pub fn successOnly() AsCompletedOptions {
        return .{
            .yield_on_exception = false,
            .yield_on_cancel = false,
        };
    }
};

/// Utility function to create as_completed iterator
pub fn asCompleted(comptime T: type, allocator: std.mem.Allocator, futures: []*CompletionFuture(T), options: AsCompletedOptions) !AsCompletedIterator(T) {
    var iter = if (options.timeout_ms) |timeout|
        AsCompletedIterator(T).initWithTimeout(allocator, timeout)
    else
        AsCompletedIterator(T).init(allocator);

    try iter.addFutures(futures);
    return iter;
}

/// Statistics for as_completed iterations
pub const AsCompletedStats = struct {
    total_futures: usize = 0,
    yielded_futures: usize = 0,
    successful: usize = 0,
    failed: usize = 0,
    cancelled: usize = 0,
    timed_out: bool = false,
    total_time_ms: i64 = 0,

    pub fn recordYield(self: *AsCompletedStats, future_state: CompletionFuture(i32).State) void {
        self.yielded_futures += 1;
        switch (future_state) {
            .completed => self.successful += 1,
            .failed => self.failed += 1,
            .cancelled => self.cancelled += 1,
            else => {},
        }
    }

    pub fn successRate(self: AsCompletedStats) f64 {
        if (self.yielded_futures == 0) return 0;
        return @as(f64, @floatFromInt(self.successful)) / @as(f64, @floatFromInt(self.yielded_futures));
    }

    pub fn completionRate(self: AsCompletedStats) f64 {
        if (self.total_futures == 0) return 0;
        return @as(f64, @floatFromInt(self.yielded_futures)) / @as(f64, @floatFromInt(self.total_futures));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "completion_future_basic" {
    var future = CompletionFuture(i32).init(1);

    try testing.expect(!future.isDone());
    try testing.expect(!future.isYielded());

    future.complete(42);
    try testing.expect(future.isDone());
    try testing.expectEqual(@as(i32, 42), future.result.?);
}

test "completion_future_fail" {
    var future = CompletionFuture(i32).init(1);

    future.fail(error.SomeError);
    try testing.expect(future.isDone());
    try testing.expectEqual(error.SomeError, future.exception.?);
}

test "completion_future_cancel" {
    var future = CompletionFuture(i32).init(1);

    future.cancel();
    try testing.expect(future.isDone());
    try testing.expectEqual(CompletionFuture(i32).State.cancelled, future.state);
}

test "as_completed_iterator_basic" {
    var f1 = CompletionFuture(i32).init(1);
    var f2 = CompletionFuture(i32).init(2);
    f1.complete(10);
    f2.complete(20);

    var iter = AsCompletedIterator(i32).init(testing.allocator);
    defer iter.deinit();

    try iter.addFuture(&f1);
    try iter.addFuture(&f2);

    try testing.expectEqual(@as(usize, 2), iter.totalCount());
    try testing.expectEqual(@as(usize, 0), iter.yieldedCount());

    const first = (try iter.next()).?;
    try testing.expect(first.isDone());
    try testing.expectEqual(@as(usize, 1), iter.yieldedCount());

    const second = (try iter.next()).?;
    try testing.expect(second.isDone());
    try testing.expectEqual(@as(usize, 2), iter.yieldedCount());

    try testing.expect((try iter.next()) == null);
    try testing.expect(iter.isComplete());
}

test "as_completed_iterator_order" {
    var f1 = CompletionFuture(i32).init(1);
    var f2 = CompletionFuture(i32).init(2);
    var f3 = CompletionFuture(i32).init(3);

    // Complete in reverse order with different times
    f3.complete(30);
    f3.completion_time = 100;

    f2.complete(20);
    f2.completion_time = 50;

    f1.complete(10);
    f1.completion_time = 75;

    var iter = AsCompletedIterator(i32).init(testing.allocator);
    defer iter.deinit();

    try iter.addFuture(&f1);
    try iter.addFuture(&f2);
    try iter.addFuture(&f3);

    // Should yield in completion time order: f2 (50), f1 (75), f3 (100)
    const first = (try iter.next()).?;
    try testing.expectEqual(@as(u64, 2), first.id);

    const second = (try iter.next()).?;
    try testing.expectEqual(@as(u64, 1), second.id);

    const third = (try iter.next()).?;
    try testing.expectEqual(@as(u64, 3), third.id);
}

test "as_completed_iterator_pending" {
    var f1 = CompletionFuture(i32).init(1);
    var f2 = CompletionFuture(i32).init(2);
    f1.complete(10);
    // f2 is still pending

    var iter = AsCompletedIterator(i32).init(testing.allocator);
    defer iter.deinit();

    try iter.addFuture(&f1);
    try iter.addFuture(&f2);

    const first = (try iter.next()).?;
    try testing.expectEqual(@as(u64, 1), first.id);

    // Next should return null because f2 is pending
    const second = try iter.next();
    try testing.expect(second == null);
}

test "as_completed_iterator_reset" {
    var f1 = CompletionFuture(i32).init(1);
    f1.complete(10);

    var iter = AsCompletedIterator(i32).init(testing.allocator);
    defer iter.deinit();

    try iter.addFuture(&f1);

    _ = try iter.next();
    try testing.expectEqual(@as(usize, 1), iter.yieldedCount());

    iter.reset();
    try testing.expectEqual(@as(usize, 0), iter.yieldedCount());
    try testing.expect(!iter.isComplete());

    // Can iterate again
    const again = (try iter.next()).?;
    try testing.expectEqual(@as(u64, 1), again.id);
}

test "as_completed_collect" {
    var f1 = CompletionFuture(i32).init(1);
    var f2 = CompletionFuture(i32).init(2);
    f1.complete(10);
    f2.complete(20);

    var iter = AsCompletedIterator(i32).init(testing.allocator);
    defer iter.deinit();

    try iter.addFuture(&f1);
    try iter.addFuture(&f2);

    const completed = try iter.collectCompleted();
    defer testing.allocator.free(completed);

    try testing.expectEqual(@as(usize, 2), completed.len);
}

test "completed_batch" {
    var f1 = CompletionFuture(i32).init(1);
    var f2 = CompletionFuture(i32).init(2);
    var f3 = CompletionFuture(i32).init(3);

    f1.complete(10);
    f2.fail(error.SomeError);
    f3.complete(30);

    var futures_array = [_]*CompletionFuture(i32){ &f1, &f2, &f3 };
    const futures_slice = try testing.allocator.dupe(*CompletionFuture(i32), &futures_array);

    var batch = CompletedBatch(i32).init(testing.allocator, futures_slice);
    defer batch.deinit();

    try testing.expectEqual(@as(usize, 3), batch.count());
    try testing.expectEqual(@as(usize, 2), batch.getSuccessCount());
    try testing.expectEqual(@as(usize, 1), batch.getFailureCount());
}

test "as_completed_options" {
    const default_opts = AsCompletedOptions.init();
    try testing.expect(default_opts.timeout_ms == null);
    try testing.expect(default_opts.yield_on_exception);

    const timeout_opts = AsCompletedOptions.withTimeout(5000);
    try testing.expectEqual(@as(u64, 5000), timeout_opts.timeout_ms.?);

    const success_only = AsCompletedOptions.successOnly();
    try testing.expect(!success_only.yield_on_exception);
    try testing.expect(!success_only.yield_on_cancel);
}

test "as_completed_stats" {
    var stats = AsCompletedStats{};
    stats.total_futures = 10;

    stats.recordYield(.completed);
    stats.recordYield(.completed);
    stats.recordYield(.failed);
    stats.recordYield(.cancelled);

    try testing.expectEqual(@as(usize, 4), stats.yielded_futures);
    try testing.expectEqual(@as(usize, 2), stats.successful);
    try testing.expectEqual(@as(usize, 1), stats.failed);
    try testing.expectEqual(@as(usize, 1), stats.cancelled);
    try testing.expectApproxEqAbs(@as(f64, 0.5), stats.successRate(), 0.01);
    try testing.expectApproxEqAbs(@as(f64, 0.4), stats.completionRate(), 0.01);
}

test "as_completed_utility_function" {
    var f1 = CompletionFuture(i32).init(1);
    var f2 = CompletionFuture(i32).init(2);
    f1.complete(10);
    f2.complete(20);

    var futures = [_]*CompletionFuture(i32){ &f1, &f2 };
    var iter = try asCompleted(i32, testing.allocator, &futures, AsCompletedOptions.init());
    defer iter.deinit();

    try testing.expectEqual(@as(usize, 2), iter.totalCount());
}
