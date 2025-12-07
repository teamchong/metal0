/// _pydatetime - Pure Python datetime Implementation
/// Mirrors cpython/Lib/_pydatetime.py
///
/// Pure Zig implementation of datetime operations.
/// Provides the low-level datetime calculations used by the datetime module.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Days in each month (non-leap year)
pub const DAYS_IN_MONTH = [_]u8{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

/// Days before each month (non-leap year)
pub const DAYS_BEFORE_MONTH = blk: {
    var days: [13]u16 = undefined;
    days[0] = 0;
    var total: u16 = 0;
    for (1..13) |i| {
        days[i] = total;
        total += DAYS_IN_MONTH[i];
    }
    break :blk days;
};

/// Minimum year
pub const MINYEAR: i32 = 1;

/// Maximum year
pub const MAXYEAR: i32 = 9999;

/// Seconds per minute
pub const SECONDS_PER_MINUTE: u32 = 60;

/// Seconds per hour
pub const SECONDS_PER_HOUR: u32 = 3600;

/// Seconds per day
pub const SECONDS_PER_DAY: u32 = 86400;

/// Microseconds per second
pub const MICROSECONDS_PER_SECOND: u32 = 1_000_000;

/// Microseconds per day
pub const MICROSECONDS_PER_DAY: u64 = 86_400_000_000;

// ============================================================================
// Date Functions
// ============================================================================

/// Check if a year is a leap year
pub fn isLeapYear(year: i32) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

/// Get days in a year
pub fn daysInYear(year: i32) u16 {
    return if (isLeapYear(year)) 366 else 365;
}

/// Get days in a month
pub fn daysInMonth(year: i32, month: u8) u8 {
    if (month < 1 or month > 12) return 0;
    if (month == 2 and isLeapYear(year)) return 29;
    return DAYS_IN_MONTH[month];
}

/// Get days before a month in a year
pub fn daysBeforeMonth(year: i32, month: u8) u16 {
    if (month < 1 or month > 12) return 0;
    var days = DAYS_BEFORE_MONTH[month];
    if (month > 2 and isLeapYear(year)) days += 1;
    return days;
}

/// Get days before a year (from year 1)
pub fn daysBeforeYear(year: i32) i64 {
    const y = year - 1;
    return @as(i64, y) * 365 + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400);
}

/// Convert year/month/day to ordinal (days since year 1)
pub fn ymdToOrdinal(year: i32, month: u8, day: u8) i64 {
    return daysBeforeYear(year) + daysBeforeMonth(year, month) + day;
}

/// Convert ordinal to year/month/day
pub fn ordinalToYmd(ordinal: i64) struct { year: i32, month: u8, day: u8 } {
    if (ordinal < 1) return .{ .year = 1, .month = 1, .day = 1 };

    // Estimate year
    var n = ordinal;
    var year: i32 = @intCast(@divFloor(n, 365));
    if (year < 1) year = 1;

    // Adjust year
    while (daysBeforeYear(year + 1) < n) {
        year += 1;
    }
    while (daysBeforeYear(year) >= n) {
        year -= 1;
    }

    n -= daysBeforeYear(year);

    // Find month
    var month: u8 = 1;
    while (month < 12) {
        const dim = daysInMonth(year, month);
        if (n <= dim) break;
        n -= dim;
        month += 1;
    }

    return .{
        .year = year,
        .month = month,
        .day = @intCast(n),
    };
}

/// Get day of week (0=Monday, 6=Sunday)
pub fn dayOfWeek(year: i32, month: u8, day: u8) u8 {
    const ordinal = ymdToOrdinal(year, month, day);
    return @intCast(@mod(ordinal + 6, 7));
}

/// Get ISO day of week (1=Monday, 7=Sunday)
pub fn isoDayOfWeek(year: i32, month: u8, day: u8) u8 {
    return dayOfWeek(year, month, day) + 1;
}

/// Get ISO week number
pub fn isoWeek(year: i32, month: u8, day: u8) struct { year: i32, week: u8, weekday: u8 } {
    const ordinal = ymdToOrdinal(year, month, day);
    const weekday = @as(u8, @intCast(@mod(ordinal + 6, 7))) + 1;

    // Find Thursday of the same week
    const thursday = ordinal + (4 - weekday);

    // Find year of the Thursday
    const thursday_ymd = ordinalToYmd(thursday);
    const iso_year = thursday_ymd.year;

    // Find ordinal of Jan 1 of iso_year
    const jan1 = ymdToOrdinal(iso_year, 1, 1);
    const jan1_weekday = @as(u8, @intCast(@mod(jan1 + 6, 7))) + 1;

    // Find first Thursday of iso_year
    var first_thursday = jan1 + @as(i64, @intCast(4 - jan1_weekday));
    if (jan1_weekday > 4) first_thursday += 7;

    // Week number
    const week = @as(u8, @intCast(@divFloor(thursday - first_thursday, 7) + 1));

    return .{ .year = iso_year, .week = week, .weekday = weekday };
}

// ============================================================================
// Time Functions
// ============================================================================

/// Convert hours/minutes/seconds to total seconds
pub fn hmsToSeconds(hour: u8, minute: u8, second: u8) u32 {
    return @as(u32, hour) * SECONDS_PER_HOUR +
        @as(u32, minute) * SECONDS_PER_MINUTE +
        second;
}

/// Convert total seconds to hours/minutes/seconds
pub fn secondsToHms(total_seconds: u32) struct { hour: u8, minute: u8, second: u8 } {
    const hour = @as(u8, @intCast(total_seconds / SECONDS_PER_HOUR));
    const remainder = total_seconds % SECONDS_PER_HOUR;
    const minute = @as(u8, @intCast(remainder / SECONDS_PER_MINUTE));
    const second = @as(u8, @intCast(remainder % SECONDS_PER_MINUTE));
    return .{ .hour = hour, .minute = minute, .second = second };
}

// ============================================================================
// Timedelta Operations
// ============================================================================

/// Normalize days, seconds, microseconds
pub fn normalizeTimedelta(days: i64, seconds: i64, microseconds: i64) struct { days: i64, seconds: i32, microseconds: i32 } {
    var d = days;
    var s = seconds;
    var us = microseconds;

    // Normalize microseconds
    if (us < 0 or us >= MICROSECONDS_PER_SECOND) {
        const us_adj = @divFloor(us, MICROSECONDS_PER_SECOND);
        s += us_adj;
        us -= us_adj * MICROSECONDS_PER_SECOND;
    }

    // Normalize seconds
    if (s < 0 or s >= SECONDS_PER_DAY) {
        const s_adj = @divFloor(s, SECONDS_PER_DAY);
        d += s_adj;
        s -= s_adj * SECONDS_PER_DAY;
    }

    return .{
        .days = d,
        .seconds = @intCast(s),
        .microseconds = @intCast(us),
    };
}

/// Total seconds in a timedelta
pub fn timedeltaTotalSeconds(days: i64, seconds: i32, microseconds: i32) f64 {
    return @as(f64, @floatFromInt(days)) * @as(f64, SECONDS_PER_DAY) +
        @as(f64, @floatFromInt(seconds)) +
        @as(f64, @floatFromInt(microseconds)) / @as(f64, MICROSECONDS_PER_SECOND);
}

// ============================================================================
// Timezone Operations
// ============================================================================

/// UTC offset in seconds
pub const UTC_OFFSET: i32 = 0;

/// Format UTC offset as string (+HH:MM or -HH:MM)
pub fn formatUtcOffset(offset_seconds: i32) [6]u8 {
    var buf: [6]u8 = undefined;
    const sign: u8 = if (offset_seconds < 0) '-' else '+';
    const abs_offset = if (offset_seconds < 0) -offset_seconds else offset_seconds;
    const hours = @divFloor(abs_offset, 3600);
    const minutes = @divFloor(@mod(abs_offset, 3600), 60);

    _ = std.fmt.bufPrint(&buf, "{c}{d:0>2}:{d:0>2}", .{
        sign,
        @as(u8, @intCast(hours)),
        @as(u8, @intCast(minutes)),
    }) catch {};

    return buf;
}

// ============================================================================
// Validation
// ============================================================================

/// Validate date components
pub fn validateDate(year: i32, month: u8, day: u8) bool {
    if (year < MINYEAR or year > MAXYEAR) return false;
    if (month < 1 or month > 12) return false;
    if (day < 1 or day > daysInMonth(year, month)) return false;
    return true;
}

/// Validate time components
pub fn validateTime(hour: u8, minute: u8, second: u8, microsecond: u32) bool {
    if (hour > 23) return false;
    if (minute > 59) return false;
    if (second > 59) return false;
    if (microsecond >= MICROSECONDS_PER_SECOND) return false;
    return true;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _pydatetime module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "leap year" {
    try std.testing.expect(isLeapYear(2000));
    try std.testing.expect(!isLeapYear(1900));
    try std.testing.expect(isLeapYear(2024));
    try std.testing.expect(!isLeapYear(2023));
}

test "days in month" {
    try std.testing.expectEqual(@as(u8, 31), daysInMonth(2023, 1));
    try std.testing.expectEqual(@as(u8, 28), daysInMonth(2023, 2));
    try std.testing.expectEqual(@as(u8, 29), daysInMonth(2024, 2));
    try std.testing.expectEqual(@as(u8, 30), daysInMonth(2023, 4));
}

test "days in year" {
    try std.testing.expectEqual(@as(u16, 365), daysInYear(2023));
    try std.testing.expectEqual(@as(u16, 366), daysInYear(2024));
}

test "ymd to ordinal" {
    // Jan 1, year 1 = day 1
    try std.testing.expectEqual(@as(i64, 1), ymdToOrdinal(1, 1, 1));
    // Dec 31, year 1 = day 365
    try std.testing.expectEqual(@as(i64, 365), ymdToOrdinal(1, 12, 31));
}

test "ordinal to ymd" {
    const result = ordinalToYmd(1);
    try std.testing.expectEqual(@as(i32, 1), result.year);
    try std.testing.expectEqual(@as(u8, 1), result.month);
    try std.testing.expectEqual(@as(u8, 1), result.day);

    // Roundtrip
    const ord = ymdToOrdinal(2024, 3, 15);
    const back = ordinalToYmd(ord);
    try std.testing.expectEqual(@as(i32, 2024), back.year);
    try std.testing.expectEqual(@as(u8, 3), back.month);
    try std.testing.expectEqual(@as(u8, 15), back.day);
}

test "day of week" {
    // January 1, 2024 was a Monday (0)
    try std.testing.expectEqual(@as(u8, 0), dayOfWeek(2024, 1, 1));
    // December 25, 2024 is a Wednesday (2)
    try std.testing.expectEqual(@as(u8, 2), dayOfWeek(2024, 12, 25));
}

test "hms to seconds" {
    try std.testing.expectEqual(@as(u32, 3661), hmsToSeconds(1, 1, 1));
    try std.testing.expectEqual(@as(u32, 43200), hmsToSeconds(12, 0, 0));
}

test "seconds to hms" {
    const result = secondsToHms(3661);
    try std.testing.expectEqual(@as(u8, 1), result.hour);
    try std.testing.expectEqual(@as(u8, 1), result.minute);
    try std.testing.expectEqual(@as(u8, 1), result.second);
}

test "normalize timedelta" {
    const result = normalizeTimedelta(0, 90061, 1500000);
    try std.testing.expectEqual(@as(i64, 1), result.days);
    try std.testing.expectEqual(@as(i32, 3662), result.seconds);
    try std.testing.expectEqual(@as(i32, 500000), result.microseconds);
}

test "validate date" {
    try std.testing.expect(validateDate(2024, 2, 29));
    try std.testing.expect(!validateDate(2023, 2, 29));
    try std.testing.expect(!validateDate(2024, 13, 1));
    try std.testing.expect(!validateDate(0, 1, 1));
}

test "validate time" {
    try std.testing.expect(validateTime(23, 59, 59, 999999));
    try std.testing.expect(!validateTime(24, 0, 0, 0));
    try std.testing.expect(!validateTime(0, 60, 0, 0));
}

test "format utc offset" {
    const positive = formatUtcOffset(3600);
    try std.testing.expectEqualStrings("+01:00", &positive);

    const negative = formatUtcOffset(-18000);
    try std.testing.expectEqualStrings("-05:00", &negative);
}
