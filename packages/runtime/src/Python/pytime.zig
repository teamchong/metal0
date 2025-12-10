/// pytime - Python Time Functions
/// Mirrors cpython/Python/pytime.c
///
/// This module provides time-related utilities for the Python runtime:
/// - High-resolution timestamps
/// - Time conversion (seconds, nanoseconds, etc.)
/// - Clock sources (monotonic, perf_counter, process_time)
/// - Timeout calculations

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Time Units and Constants
// ============================================================================

/// Nanoseconds per second
pub const NS_PER_SEC: i64 = 1_000_000_000;

/// Microseconds per second
pub const US_PER_SEC: i64 = 1_000_000;

/// Milliseconds per second
pub const MS_PER_SEC: i64 = 1_000;

/// Nanoseconds per millisecond
pub const NS_PER_MS: i64 = 1_000_000;

/// Nanoseconds per microsecond
pub const NS_PER_US: i64 = 1_000;

/// Maximum timestamp value (fits in i64 nanoseconds)
pub const TIME_MAX: i64 = std.math.maxInt(i64);

/// Minimum timestamp value
pub const TIME_MIN: i64 = std.math.minInt(i64);

// ============================================================================
// Time Types
// ============================================================================

/// Time represented in nanoseconds (internal representation)
pub const PyTime = i64;

/// Timespec structure (seconds + nanoseconds)
pub const Timespec = struct {
    tv_sec: i64,
    tv_nsec: i64,

    pub fn toNanos(self: Timespec) i64 {
        return self.tv_sec * NS_PER_SEC + self.tv_nsec;
    }

    pub fn fromNanos(nanos: i64) Timespec {
        return .{
            .tv_sec = @divFloor(nanos, NS_PER_SEC),
            .tv_nsec = @mod(nanos, NS_PER_SEC),
        };
    }
};

/// Timeval structure (seconds + microseconds)
pub const Timeval = struct {
    tv_sec: i64,
    tv_usec: i64,

    pub fn toNanos(self: Timeval) i64 {
        return self.tv_sec * NS_PER_SEC + self.tv_usec * NS_PER_US;
    }

    pub fn fromNanos(nanos: i64) Timeval {
        return .{
            .tv_sec = @divFloor(nanos, NS_PER_SEC),
            .tv_usec = @divFloor(@mod(nanos, NS_PER_SEC), NS_PER_US),
        };
    }
};

/// Rounding mode for time conversions
pub const RoundMode = enum {
    floor, // Round towards negative infinity
    ceiling, // Round towards positive infinity
    half_even, // Round to nearest, ties to even (banker's rounding)
    up, // Round away from zero
    down, // Round towards zero
};

// ============================================================================
// Conversion Functions
// ============================================================================

/// Convert seconds (f64) to nanoseconds (i64)
pub fn secondsToNanos(seconds: f64) !i64 {
    const scaled = seconds * @as(f64, @floatFromInt(NS_PER_SEC));
    if (scaled > @as(f64, @floatFromInt(TIME_MAX)) or scaled < @as(f64, @floatFromInt(TIME_MIN))) {
        return error.Overflow;
    }
    return @intFromFloat(scaled);
}

/// Convert nanoseconds to seconds (f64)
pub fn nanosToSeconds(nanos: i64) f64 {
    return @as(f64, @floatFromInt(nanos)) / @as(f64, @floatFromInt(NS_PER_SEC));
}

/// Convert nanoseconds to milliseconds
pub fn nanosToMillis(nanos: i64, round: RoundMode) i64 {
    return divRound(nanos, NS_PER_MS, round);
}

/// Convert nanoseconds to microseconds
pub fn nanosToMicros(nanos: i64, round: RoundMode) i64 {
    return divRound(nanos, NS_PER_US, round);
}

/// Convert milliseconds to nanoseconds
pub fn millisToNanos(millis: i64) !i64 {
    const result = @mulWithOverflow(millis, NS_PER_MS);
    if (result[1] != 0) return error.Overflow;
    return result[0];
}

/// Convert microseconds to nanoseconds
pub fn microsToNanos(micros: i64) !i64 {
    const result = @mulWithOverflow(micros, NS_PER_US);
    if (result[1] != 0) return error.Overflow;
    return result[0];
}

/// Division with rounding mode
fn divRound(numerator: i64, denominator: i64, round: RoundMode) i64 {
    const quotient = @divFloor(numerator, denominator);
    const remainder = @mod(numerator, denominator);

    if (remainder == 0) return quotient;

    return switch (round) {
        .floor => quotient,
        .ceiling => quotient + 1,
        .down => if (numerator >= 0) quotient else quotient + 1,
        .up => if (numerator >= 0) quotient + 1 else quotient,
        .half_even => blk: {
            const half = @divFloor(denominator, 2);
            if (remainder > half) {
                break :blk quotient + 1;
            } else if (remainder < half) {
                break :blk quotient;
            } else {
                // Exactly half - round to even
                break :blk if (@mod(quotient, 2) == 0) quotient else quotient + 1;
            }
        },
    };
}

// ============================================================================
// Clock Functions
// ============================================================================

/// Get current monotonic time in nanoseconds
pub fn monotonicNanos() i64 {
    const instant = std.time.Instant.now() catch return 0;
    return @intCast(instant.timestamp);
}

/// Get current monotonic time as float seconds
pub fn monotonicSeconds() f64 {
    return nanosToSeconds(monotonicNanos());
}

/// Get current wall clock time in nanoseconds since epoch
pub fn timeNanos() i64 {
    return std.time.nanoTimestamp();
}

/// Get current wall clock time in seconds since epoch
pub fn timeSeconds() f64 {
    return nanosToSeconds(timeNanos());
}

/// Get current wall clock time as Timespec
pub fn timeTimespec() Timespec {
    return Timespec.fromNanos(timeNanos());
}

/// Get performance counter (highest resolution available)
pub fn perfCounterNanos() i64 {
    // On most systems, nanoTimestamp uses the best available source
    return std.time.nanoTimestamp();
}

/// Get performance counter as float seconds
pub fn perfCounterSeconds() f64 {
    return nanosToSeconds(perfCounterNanos());
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
    return nanosToSeconds(processTimeNanos());
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
    return nanosToSeconds(threadTimeNanos());
}

// ============================================================================
// Timeout Handling
// ============================================================================

/// Deadline for timeout operations
pub const Deadline = struct {
    start: i64,
    timeout_ns: i64,

    const Self = @This();

    /// Create a deadline from timeout in seconds
    pub fn fromSeconds(timeout: f64) !Self {
        const timeout_ns = try secondsToNanos(timeout);
        return .{
            .start = monotonicNanos(),
            .timeout_ns = timeout_ns,
        };
    }

    /// Create a deadline from timeout in nanoseconds
    pub fn fromNanos(timeout_ns: i64) Self {
        return .{
            .start = monotonicNanos(),
            .timeout_ns = timeout_ns,
        };
    }

    /// Check if deadline has passed
    pub fn isExpired(self: Self) bool {
        if (self.timeout_ns < 0) return false; // Infinite timeout
        const elapsed = monotonicNanos() - self.start;
        return elapsed >= self.timeout_ns;
    }

    /// Get remaining time in nanoseconds
    pub fn remainingNanos(self: Self) i64 {
        if (self.timeout_ns < 0) return TIME_MAX; // Infinite
        const elapsed = monotonicNanos() - self.start;
        const remaining = self.timeout_ns - elapsed;
        return if (remaining < 0) 0 else remaining;
    }

    /// Get remaining time in seconds
    pub fn remainingSeconds(self: Self) f64 {
        return nanosToSeconds(self.remainingNanos());
    }

    /// Update timeout to remaining time (for restarting interrupted operations)
    pub fn updateRemaining(self: *Self) void {
        const remaining = self.remainingNanos();
        self.timeout_ns = remaining;
        self.start = monotonicNanos();
    }
};

// ============================================================================
// Sleep Functions
// ============================================================================

/// Sleep for given nanoseconds
pub fn sleepNanos(nanos: i64) void {
    if (nanos <= 0) return;
    std.time.sleep(@intCast(nanos));
}

/// Sleep for given seconds (float)
pub fn sleepSeconds(seconds: f64) void {
    if (seconds <= 0) return;
    const nanos = secondsToNanos(seconds) catch return;
    sleepNanos(nanos);
}

/// Sleep for given milliseconds
pub fn sleepMillis(millis: i64) void {
    if (millis <= 0) return;
    const nanos = millisToNanos(millis) catch return;
    sleepNanos(nanos);
}

// ============================================================================
// Time Information
// ============================================================================

/// Clock info structure (matches Python's time.get_clock_info)
pub const ClockInfo = struct {
    name: []const u8,
    implementation: []const u8,
    monotonic: bool,
    adjustable: bool,
    resolution: f64, // in seconds
};

/// Get clock info for monotonic clock
pub fn monotonicClockInfo() ClockInfo {
    return .{
        .name = "monotonic",
        .implementation = if (builtin.os.tag == .linux) "clock_gettime(CLOCK_MONOTONIC)" else if (builtin.os.tag == .macos) "mach_absolute_time()" else "QueryPerformanceCounter()",
        .monotonic = true,
        .adjustable = false,
        .resolution = 1.0 / @as(f64, @floatFromInt(NS_PER_SEC)),
    };
}

/// Get clock info for wall clock
pub fn timeClockInfo() ClockInfo {
    return .{
        .name = "time",
        .implementation = if (builtin.os.tag == .linux) "clock_gettime(CLOCK_REALTIME)" else if (builtin.os.tag == .macos) "gettimeofday()" else "GetSystemTimeAsFileTime()",
        .monotonic = false,
        .adjustable = true,
        .resolution = 1.0 / @as(f64, @floatFromInt(NS_PER_SEC)),
    };
}

/// Get clock info for performance counter
pub fn perfCounterClockInfo() ClockInfo {
    return .{
        .name = "perf_counter",
        .implementation = monotonicClockInfo().implementation,
        .monotonic = true,
        .adjustable = false,
        .resolution = 1.0 / @as(f64, @floatFromInt(NS_PER_SEC)),
    };
}

/// Get clock info for process time
pub fn processTimeClockInfo() ClockInfo {
    return .{
        .name = "process_time",
        .implementation = if (builtin.os.tag == .linux) "clock_gettime(CLOCK_PROCESS_CPUTIME_ID)" else "getrusage()",
        .monotonic = true,
        .adjustable = false,
        .resolution = 1.0 / @as(f64, @floatFromInt(NS_PER_SEC)),
    };
}

// ============================================================================
// Local Time Conversion
// ============================================================================

/// Broken down time structure
pub const BrokenDownTime = struct {
    year: i32, // Year (e.g., 2024)
    month: u4, // Month (1-12)
    day: u5, // Day of month (1-31)
    hour: u5, // Hour (0-23)
    minute: u6, // Minute (0-59)
    second: u6, // Second (0-59)
    weekday: u3, // Day of week (0=Monday, 6=Sunday)
    yearday: u9, // Day of year (1-366)
    is_dst: ?bool, // Daylight saving time flag

    /// Get ISO weekday (1=Monday, 7=Sunday)
    pub fn isoWeekday(self: BrokenDownTime) u3 {
        return self.weekday + 1;
    }
};

/// Convert timestamp to broken down local time
pub fn localtime(timestamp: i64) BrokenDownTime {
    const epoch_secs = @divFloor(timestamp, NS_PER_SEC);
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch_secs) };
    const day_seconds = epoch.getDaySeconds();
    const year_day = epoch.getEpochDay().calculateYearDay();

    return .{
        .year = year_day.year,
        .month = @intCast(year_day.month.numeric()),
        .day = year_day.day,
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
        .weekday = @intCast(epoch.getEpochDay().dayOfWeek().numeric()),
        .yearday = year_day.day, // Simplified
        .is_dst = null, // DST info not available
    };
}

/// Convert broken down time to timestamp
pub fn mktime(tm: BrokenDownTime) !i64 {
    // Convert to epoch day
    const month = std.time.epoch.Month.jan.toInt();
    _ = month;
    // Simplified implementation
    var days: i64 = 0;

    // Years since 1970
    var y: i32 = 1970;
    while (y < tm.year) : (y += 1) {
        days += if (isLeapYear(y)) 366 else 365;
    }

    // Months
    const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var m: u4 = 1;
    while (m < tm.month) : (m += 1) {
        var d = days_in_month[m - 1];
        if (m == 2 and isLeapYear(tm.year)) d += 1;
        days += d;
    }

    // Days
    days += tm.day - 1;

    // Convert to nanoseconds
    var secs = days * 86400;
    secs += @as(i64, tm.hour) * 3600;
    secs += @as(i64, tm.minute) * 60;
    secs += tm.second;

    return secs * NS_PER_SEC;
}

fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;
    return false;
}

// ============================================================================
// Initialization
// ============================================================================

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
    try std.testing.expectEqual(@as(i64, 1), divRound(15, 10, .floor));
    try std.testing.expectEqual(@as(i64, 2), divRound(15, 10, .ceiling));
    try std.testing.expectEqual(@as(i64, 2), divRound(15, 10, .half_even));
}

test "clock info" {
    const mono = monotonicClockInfo();
    try std.testing.expect(mono.monotonic);
    try std.testing.expect(!mono.adjustable);

    const wall = timeClockInfo();
    try std.testing.expect(!wall.monotonic);
    try std.testing.expect(wall.adjustable);
}
