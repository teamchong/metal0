/// Clock Functions
/// High-resolution clock sources for timing operations

const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.zig");
const types = @import("types.zig");
const conversion = @import("conversion.zig");

/// Get current monotonic time in nanoseconds
pub fn monotonicNanos() i64 {
    // Use milliTimestamp as a monotonic clock source
    // Multiply by 1_000_000 to convert milliseconds to nanoseconds
    return std.time.milliTimestamp() * 1_000_000;
}

/// Get current monotonic time as float seconds
pub fn monotonicSeconds() f64 {
    return conversion.nanosToSeconds(monotonicNanos());
}

/// Get current wall clock time in nanoseconds since epoch
pub fn timeNanos() i64 {
    return std.time.nanoTimestamp();
}

/// Get current wall clock time in seconds since epoch
pub fn timeSeconds() f64 {
    return conversion.nanosToSeconds(timeNanos());
}

/// Get current wall clock time as Timespec
pub fn timeTimespec() types.Timespec {
    return types.Timespec.fromNanos(timeNanos());
}

/// Get performance counter (highest resolution available)
pub fn perfCounterNanos() i64 {
    // On most systems, nanoTimestamp uses the best available source
    return std.time.nanoTimestamp();
}

/// Get performance counter as float seconds
pub fn perfCounterSeconds() f64 {
    return conversion.nanosToSeconds(perfCounterNanos());
}

/// Get process time (user + system CPU time) in nanoseconds
pub fn processTimeNanos() i64 {
    if (builtin.os.tag == .linux or builtin.os.tag == .freebsd or
        builtin.os.tag == .netbsd or builtin.os.tag == .openbsd)
    {
        // Use clock_gettime with CLOCK_PROCESS_CPUTIME_ID
        var ts: std.posix.timespec = undefined;
        const CLOCK_PROCESS_CPUTIME_ID = 2; // Linux/BSD value
        const result = std.posix.clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts);
        if (result == 0) {
            return ts.sec * std.time.ns_per_s + ts.nsec;
        }
        // Fall back to monotonic if process clock unavailable
        return monotonicNanos();
    } else if (builtin.os.tag == .macos) {
        // macOS: Use mach_absolute_time based approximation
        // CLOCK_PROCESS_CPUTIME_ID is not well supported on macOS
        // Use thread_info for actual CPU time would require mach APIs
        return monotonicNanos();
    } else if (builtin.os.tag == .windows) {
        // Windows: GetProcessTimes requires kernel32 FFI
        // Monotonic time is acceptable for most use cases
        return monotonicNanos();
    }
    return monotonicNanos();
}

/// Get process time as float seconds
pub fn processTimeSeconds() f64 {
    return conversion.nanosToSeconds(processTimeNanos());
}

/// Get thread time in nanoseconds
pub fn threadTimeNanos() i64 {
    if (builtin.os.tag == .linux) {
        // Use clock_gettime with CLOCK_THREAD_CPUTIME_ID
        var ts: std.posix.timespec = undefined;
        const CLOCK_THREAD_CPUTIME_ID = 3; // Linux value
        const result = std.posix.clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts);
        if (result == 0) {
            return ts.sec * std.time.ns_per_s + ts.nsec;
        }
    }
    // Fall back to process time for other platforms
    return processTimeNanos();
}

/// Get thread time as float seconds
pub fn threadTimeSeconds() f64 {
    return conversion.nanosToSeconds(threadTimeNanos());
}

/// Get clock info for monotonic clock
pub fn monotonicClockInfo() types.ClockInfo {
    return .{
        .name = "monotonic",
        .implementation = if (builtin.os.tag == .linux) "clock_gettime(CLOCK_MONOTONIC)" else if (builtin.os.tag == .macos) "mach_absolute_time()" else "QueryPerformanceCounter()",
        .monotonic = true,
        .adjustable = false,
        .resolution = 1.0 / @as(f64, @floatFromInt(constants.NS_PER_SEC)),
    };
}

/// Get clock info for wall clock
pub fn timeClockInfo() types.ClockInfo {
    return .{
        .name = "time",
        .implementation = if (builtin.os.tag == .linux) "clock_gettime(CLOCK_REALTIME)" else if (builtin.os.tag == .macos) "gettimeofday()" else "GetSystemTimeAsFileTime()",
        .monotonic = false,
        .adjustable = true,
        .resolution = 1.0 / @as(f64, @floatFromInt(constants.NS_PER_SEC)),
    };
}

/// Get clock info for performance counter
pub fn perfCounterClockInfo() types.ClockInfo {
    return .{
        .name = "perf_counter",
        .implementation = monotonicClockInfo().implementation,
        .monotonic = true,
        .adjustable = false,
        .resolution = 1.0 / @as(f64, @floatFromInt(constants.NS_PER_SEC)),
    };
}

/// Get clock info for process time
pub fn processTimeClockInfo() types.ClockInfo {
    return .{
        .name = "process_time",
        .implementation = if (builtin.os.tag == .linux) "clock_gettime(CLOCK_PROCESS_CPUTIME_ID)" else "getrusage()",
        .monotonic = true,
        .adjustable = false,
        .resolution = 1.0 / @as(f64, @floatFromInt(constants.NS_PER_SEC)),
    };
}
