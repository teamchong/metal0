/// Local Time Conversion
/// Convert between timestamps and broken-down time structures

const std = @import("std");
const constants = @import("constants.zig");
const types = @import("types.zig");

/// Convert timestamp to broken down local time
pub fn localtime(timestamp: i64) types.BrokenDownTime {
    const epoch_secs = @divFloor(timestamp, constants.NS_PER_SEC);
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
pub fn mktime(tm: types.BrokenDownTime) !i64 {
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

    return secs * constants.NS_PER_SEC;
}

fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;
    return false;
}
