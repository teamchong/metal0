//! Python time module - Time access and conversions
//!
//! Provides various time-related functions. This is a Metal0-specific
//! implementation (CPython's time module is implemented in C as _time).

const std = @import("std");

/// Get current time in seconds since Unix epoch
pub fn time() f64 {
    const nanos = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(nanos)) / @as(f64, std.time.ns_per_s);
}

/// Sleep for the specified number of seconds
pub fn sleep(secs: f64) void {
    const ns: u64 = @intFromFloat(secs * @as(f64, std.time.ns_per_s));
    std.Thread.sleep(ns);
}

/// Get monotonic clock time
pub fn monotonic() f64 {
    const nanos = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(nanos)) / @as(f64, std.time.ns_per_s);
}

/// Get performance counter value
pub fn perf_counter() f64 {
    return monotonic();
}

/// Time nanoseconds since epoch
pub fn time_ns() i128 {
    return std.time.nanoTimestamp();
}

/// Monotonic nanoseconds
pub fn monotonic_ns() i128 {
    return std.time.nanoTimestamp();
}

/// struct_time representation
pub const struct_time = struct {
    tm_sec: i32 = 0,
    tm_min: i32 = 0,
    tm_hour: i32 = 0,
    tm_mday: i32 = 1,
    tm_mon: i32 = 1,
    tm_year: i32 = 1970,
    tm_wday: i32 = 0,
    tm_yday: i32 = 0,
    tm_isdst: i32 = -1,
};

/// Convert timestamp to UTC struct_time (gmtime)
pub fn gmtime(timestamp: f64) struct_time {
    const secs: i64 = @intFromFloat(timestamp);
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(secs) };
    const day_secs = epoch.getDaySeconds();
    const year_day = epoch.getEpochDay().calculateYearDay();

    return .{
        .tm_sec = @intCast(day_secs.getSecondsIntoMinute()),
        .tm_min = @intCast(day_secs.getMinutesIntoHour()),
        .tm_hour = @intCast(day_secs.getHoursIntoDay()),
        .tm_mday = @intCast(year_day.day + 1),
        .tm_mon = @intCast(@intFromEnum(year_day.month)),
        .tm_year = @as(i32, @intCast(year_day.year)) - 1900,
        .tm_wday = 0,
        .tm_yday = @intCast(year_day.day),
        .tm_isdst = 0,
    };
}

/// Convert timestamp to local struct_time
pub fn localtime(timestamp: f64) struct_time {
    return gmtime(timestamp); // Simplified: assumes UTC
}

test "time returns positive" {
    const t = time();
    try std.testing.expect(t > 0);
}
