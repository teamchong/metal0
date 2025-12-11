/// pytime - Python Time Functions
/// Mirrors cpython/Python/pytime.c
///
/// This module provides time-related utilities for the Python runtime:
/// - High-resolution timestamps
/// - Time conversion (seconds, nanoseconds, etc.)
/// - Clock sources (monotonic, perf_counter, process_time)
/// - Timeout calculations

const std = @import("std");

// Re-export submodules
pub const constants = @import("pytime/constants.zig");
pub const types = @import("pytime/types.zig");
pub const conversion = @import("pytime/conversion.zig");
pub const clocks = @import("pytime/clocks.zig");
pub const timeout = @import("pytime/timeout.zig");
pub const sleep = @import("pytime/sleep.zig");
pub const localtime_mod = @import("pytime/localtime.zig");

// Re-export commonly used items from constants
pub const NS_PER_SEC = constants.NS_PER_SEC;
pub const US_PER_SEC = constants.US_PER_SEC;
pub const MS_PER_SEC = constants.MS_PER_SEC;
pub const NS_PER_MS = constants.NS_PER_MS;
pub const NS_PER_US = constants.NS_PER_US;
pub const TIME_MAX = constants.TIME_MAX;
pub const TIME_MIN = constants.TIME_MIN;

// Re-export types
pub const PyTime = types.PyTime;
pub const Timespec = types.Timespec;
pub const Timeval = types.Timeval;
pub const RoundMode = types.RoundMode;
pub const BrokenDownTime = types.BrokenDownTime;
pub const ClockInfo = types.ClockInfo;

// Re-export conversion functions
pub const secondsToNanos = conversion.secondsToNanos;
pub const nanosToSeconds = conversion.nanosToSeconds;
pub const nanosToMillis = conversion.nanosToMillis;
pub const nanosToMicros = conversion.nanosToMicros;
pub const millisToNanos = conversion.millisToNanos;
pub const microsToNanos = conversion.microsToNanos;

// Re-export clock functions
pub const monotonicNanos = clocks.monotonicNanos;
pub const monotonicSeconds = clocks.monotonicSeconds;
pub const timeNanos = clocks.timeNanos;
pub const timeSeconds = clocks.timeSeconds;
pub const timeTimespec = clocks.timeTimespec;
pub const perfCounterNanos = clocks.perfCounterNanos;
pub const perfCounterSeconds = clocks.perfCounterSeconds;
pub const processTimeNanos = clocks.processTimeNanos;
pub const processTimeSeconds = clocks.processTimeSeconds;
pub const threadTimeNanos = clocks.threadTimeNanos;
pub const threadTimeSeconds = clocks.threadTimeSeconds;
pub const monotonicClockInfo = clocks.monotonicClockInfo;
pub const timeClockInfo = clocks.timeClockInfo;
pub const perfCounterClockInfo = clocks.perfCounterClockInfo;
pub const processTimeClockInfo = clocks.processTimeClockInfo;

// Re-export timeout handling
pub const Deadline = timeout.Deadline;

// Re-export sleep functions
pub const sleepNanos = sleep.sleepNanos;
pub const sleepSeconds = sleep.sleepSeconds;
pub const sleepMillis = sleep.sleepMillis;

// Re-export local time functions
pub const localtime = localtime_mod.localtime;
pub const mktime = localtime_mod.mktime;

/// Initialize time module
pub fn init() void {
    // No initialization needed - Zig stdlib handles clock sources
}

// ============================================================================
// Tests
// ============================================================================

test "time conversion" {
    const nanos: i64 = 1_500_000_000; // 1.5 seconds
    const seconds = nanosToSeconds(nanos);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), seconds, 0.0001);

    const back = try secondsToNanos(seconds);
    try std.testing.expectEqual(nanos, back);
}

test "millis conversion" {
    const millis: i64 = 1500;
    const nanos = try millisToNanos(millis);
    try std.testing.expectEqual(@as(i64, 1_500_000_000), nanos);

    const back = nanosToMillis(nanos, .floor);
    try std.testing.expectEqual(millis, back);
}

test "timespec" {
    const ts = Timespec{
        .tv_sec = 5,
        .tv_nsec = 500_000_000,
    };
    const nanos = ts.toNanos();
    try std.testing.expectEqual(@as(i64, 5_500_000_000), nanos);

    const back = Timespec.fromNanos(nanos);
    try std.testing.expectEqual(ts.tv_sec, back.tv_sec);
    try std.testing.expectEqual(ts.tv_nsec, back.tv_nsec);
}

test "deadline" {
    const deadline = Deadline.fromNanos(100_000_000); // 100ms
    try std.testing.expect(!deadline.isExpired());
    try std.testing.expect(deadline.remainingNanos() > 0);
}

test "div round" {
    // Direct test of divRound via nanosToMicros (divides by 1000)
    try std.testing.expectEqual(@as(i64, 15), conversion.nanosToMicros(15_000, .floor));
    try std.testing.expectEqual(@as(i64, 15), conversion.nanosToMicros(15_000, .ceiling));
    try std.testing.expectEqual(@as(i64, 15), conversion.nanosToMicros(15_000, .half_even));
}

test "clock info" {
    const mono = monotonicClockInfo();
    try std.testing.expect(mono.monotonic);
    try std.testing.expect(!mono.adjustable);

    const wall = timeClockInfo();
    try std.testing.expect(!wall.monotonic);
    try std.testing.expect(wall.adjustable);
}
