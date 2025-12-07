//! Python 'timeit' module - Measure execution time of small code snippets
//!
//! Provides a simple way to time small bits of Python code.
//! In Zig context, we provide timing utilities for measuring code execution.
//!
//! Mirrors: CPython Lib/timeit.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

pub const default_number: u64 = 1_000_000;
pub const default_repeat: usize = 5;
pub const default_timer = std.time.Timer;

// ============================================================================
// Timer class
// ============================================================================

/// Timer class for timing code execution
pub const Timer = struct {
    allocator: std.mem.Allocator,
    stmt: ?*const fn () void = null,
    setup: ?*const fn () void = null,
    globals: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator) Timer {
        return .{ .allocator = allocator };
    }

    /// Time a single execution
    pub fn timeit(self: *const Timer, number: u64) f64 {
        // Run setup if provided
        if (self.setup) |setup_fn| {
            setup_fn();
        }

        var timer = std.time.Timer.start() catch return 0;

        // Run the statement 'number' times
        var i: u64 = 0;
        while (i < number) : (i += 1) {
            if (self.stmt) |stmt_fn| {
                stmt_fn();
            }
        }

        const elapsed = timer.read();
        return @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s;
    }

    /// Repeat timing and return list of times
    pub fn repeat(self: *const Timer, repeat_count: usize, number: u64) ![]f64 {
        var times = try self.allocator.alloc(f64, repeat_count);
        for (times, 0..) |*t, i| {
            _ = i;
            t.* = self.timeit(number);
        }
        return times;
    }

    /// Auto-range to find appropriate number of iterations
    pub fn autorange(self: *const Timer) struct { number: u64, time_taken: f64 } {
        var i: u6 = 0;
        while (i < 10) : (i += 1) {
            const number: u64 = @as(u64, 1) << (i * 3); // 1, 8, 64, 512, ...
            const time_taken = self.timeit(number);
            if (time_taken >= 0.2) {
                return .{ .number = number, .time_taken = time_taken };
            }
        }
        return .{ .number = 1 << 30, .time_taken = self.timeit(1 << 30) };
    }
};

// ============================================================================
// Module-level functions
// ============================================================================

/// Time execution of a function
pub fn timeit(func: *const fn () void, number: u64) f64 {
    const timer = Timer{
        .allocator = undefined,
        .stmt = func,
    };
    return timer.timeit(number);
}

/// Repeat timing and return minimum time
pub fn repeat(allocator: std.mem.Allocator, func: *const fn () void, repeat_count: usize, number: u64) !f64 {
    var timer = Timer{
        .allocator = allocator,
        .stmt = func,
    };
    const times = try timer.repeat(repeat_count, number);
    defer allocator.free(times);

    var min_time: f64 = times[0];
    for (times[1..]) |t| {
        if (t < min_time) min_time = t;
    }
    return min_time;
}

// ============================================================================
// Timing utilities
// ============================================================================

/// Get current time in seconds (high resolution)
pub fn default_timer_fn() f64 {
    const now = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(now)) / std.time.ns_per_s;
}

/// Format time duration for display
pub fn formatTime(allocator: std.mem.Allocator, seconds: f64) ![]u8 {
    if (seconds >= 1.0) {
        return std.fmt.allocPrint(allocator, "{d:.3} sec", .{seconds});
    } else if (seconds >= 0.001) {
        return std.fmt.allocPrint(allocator, "{d:.3} ms", .{seconds * 1000});
    } else if (seconds >= 0.000001) {
        return std.fmt.allocPrint(allocator, "{d:.3} us", .{seconds * 1_000_000});
    } else {
        return std.fmt.allocPrint(allocator, "{d:.3} ns", .{seconds * 1_000_000_000});
    }
}

/// Format time per iteration
pub fn formatTimePerIter(allocator: std.mem.Allocator, total_seconds: f64, iterations: u64) ![]u8 {
    const per_iter = total_seconds / @as(f64, @floatFromInt(iterations));
    return formatTime(allocator, per_iter);
}

// ============================================================================
// Benchmark helper
// ============================================================================

/// Run a benchmark and print results
pub fn benchmark(
    allocator: std.mem.Allocator,
    name: []const u8,
    func: *const fn () void,
    number: u64,
    repeat_count: usize,
) !void {
    var timer = Timer{
        .allocator = allocator,
        .stmt = func,
    };

    const times = try timer.repeat(repeat_count, number);
    defer allocator.free(times);

    // Find min, max, mean
    var min_time: f64 = times[0];
    var max_time: f64 = times[0];
    var sum: f64 = 0;

    for (times) |t| {
        if (t < min_time) min_time = t;
        if (t > max_time) max_time = t;
        sum += t;
    }

    const mean_time = sum / @as(f64, @floatFromInt(repeat_count));

    // Format and print
    const min_str = try formatTimePerIter(allocator, min_time, number);
    defer allocator.free(min_str);
    const mean_str = try formatTimePerIter(allocator, mean_time, number);
    defer allocator.free(mean_str);

    std.debug.print("{s}: {d} loops, best of {d}: {s} per loop (mean: {s})\n", .{
        name,
        number,
        repeat_count,
        min_str,
        mean_str,
    });
}

// ============================================================================
// Tests
// ============================================================================

test "Timer init" {
    const timer = Timer.init(std.testing.allocator);
    try std.testing.expectEqual(@as(?*const fn () void, null), timer.stmt);
}

test "default constants" {
    try std.testing.expectEqual(@as(u64, 1_000_000), default_number);
    try std.testing.expectEqual(@as(usize, 5), default_repeat);
}

test "formatTime seconds" {
    const allocator = std.testing.allocator;
    const result = try formatTime(allocator, 1.234);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("1.234 sec", result);
}

test "formatTime milliseconds" {
    const allocator = std.testing.allocator;
    const result = try formatTime(allocator, 0.00123);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("1.230 ms", result);
}

test "formatTime microseconds" {
    const allocator = std.testing.allocator;
    const result = try formatTime(allocator, 0.00000123);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("1.230 us", result);
}

test "formatTime nanoseconds" {
    const allocator = std.testing.allocator;
    const result = try formatTime(allocator, 0.00000000123);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("1.230 ns", result);
}

fn testFunc() void {
    var x: u64 = 0;
    for (0..100) |i| {
        x += i;
    }
    std.mem.doNotOptimizeAway(&x);
}

test "timeit basic" {
    const t = timeit(&testFunc, 100);
    try std.testing.expect(t > 0);
    try std.testing.expect(t < 1.0); // Should complete in under 1 second
}

test "Timer repeat" {
    const allocator = std.testing.allocator;
    var timer = Timer{
        .allocator = allocator,
        .stmt = &testFunc,
    };
    const times = try timer.repeat(3, 100);
    defer allocator.free(times);
    try std.testing.expectEqual(@as(usize, 3), times.len);
    for (times) |t| {
        try std.testing.expect(t > 0);
    }
}
