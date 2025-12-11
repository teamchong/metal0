/// Datetime struct - represents datetime.datetime

const std = @import("std");
const runtime = @import("../../runtime.zig");
const Timedelta = @import("timedelta.zig").Timedelta;
const Date = @import("date.zig").Date;
const Time = @import("time.zig").Time;
const daysFromDate = @import("date.zig").daysFromDate;

const c = @cImport({
    @cInclude("time.h");
});

fn isLeapYear(year: u32) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

/// Datetime struct - represents datetime.datetime
pub const Datetime = struct {
    year: u32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32,
    /// fold attribute - disambiguates wall times during DST transitions
    /// 0 = first occurrence (before DST transition)
    /// 1 = second occurrence (after DST transition)
    /// See: https://docs.python.org/3/library/datetime.html#datetime.datetime.fold
    fold: u1 = 0,

    /// Create datetime.datetime.now() using local time
    pub fn now() Datetime {
        const ts = std.time.timestamp();
        // Use C localtime to get proper timezone-aware local time
        var time_val: c.time_t = @intCast(ts);
        const local_tm = c.localtime(&time_val);
        if (local_tm) |tm_ptr| {
            const tm = tm_ptr.*;
            // Get microseconds from nanoTimestamp
            const nano_ts = std.time.nanoTimestamp();
            const micros: u32 = @intCast(@mod(@divFloor(nano_ts, 1000), 1_000_000));

            return Datetime{
                .year = @intCast(tm.tm_year + 1900),
                .month = @intCast(tm.tm_mon + 1),
                .day = @intCast(tm.tm_mday),
                .hour = @intCast(tm.tm_hour),
                .minute = @intCast(tm.tm_min),
                .second = @intCast(tm.tm_sec),
                .microsecond = micros,
            };
        }
        // Fallback to UTC
        return fromTimestamp(ts);
    }

    /// Create from Unix timestamp (UTC)
    pub fn fromTimestamp(ts: i64) Datetime {
        const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(ts) };
        const day_seconds = epoch_secs.getDaySeconds();
        const year_day = epoch_secs.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        // Get microseconds from nanoTimestamp if available
        const nano_ts = std.time.nanoTimestamp();
        const micros: u32 = @intCast(@mod(@divFloor(nano_ts, 1000), 1_000_000));

        return Datetime{
            .year = @intCast(year_day.year),
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
            .hour = day_seconds.getHoursIntoDay(),
            .minute = day_seconds.getMinutesIntoHour(),
            .second = day_seconds.getSecondsIntoMinute(),
            .microsecond = micros,
        };
    }

    /// Convert to string: YYYY-MM-DD HH:MM:SS or YYYY-MM-DD HH:MM:SS.ffffff (Python format)
    pub fn toString(self: Datetime, allocator: std.mem.Allocator) ![]const u8 {
        // Only show microseconds if non-zero (Python behavior)
        if (self.microsecond > 0) {
            return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
                self.year, self.month, self.day, self.hour, self.minute, self.second, self.microsecond,
            });
        }
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
            self.year, self.month, self.day, self.hour, self.minute, self.second,
        });
    }

    /// Create PyString from datetime
    pub fn toPyString(self: Datetime, allocator: std.mem.Allocator) !*runtime.PyObject {
        const str = try self.toString(allocator);
        return try runtime.PyString.create(allocator, str);
    }

    /// Convert to ISO format: YYYY-MM-DDTHH:MM:SS.ffffff
    pub fn toIsoformat(self: Datetime, allocator: std.mem.Allocator) ![]const u8 {
        if (self.microsecond > 0) {
            return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
                self.year, self.month, self.day, self.hour, self.minute, self.second, self.microsecond,
            });
        }
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
            self.year, self.month, self.day, self.hour, self.minute, self.second,
        });
    }

    /// Convert to Unix timestamp
    pub fn toTimestamp(self: Datetime) f64 {
        const days = daysFromDate(self.year, self.month, self.day);
        const secs = @as(i64, days) * 86400 + @as(i64, self.hour) * 3600 + @as(i64, self.minute) * 60 + @as(i64, self.second);
        return @as(f64, @floatFromInt(secs)) + @as(f64, @floatFromInt(self.microsecond)) / 1_000_000.0;
    }

    /// Convert to ctime format: "Sun Jun  9 01:21:11 1993"
    pub fn toCtime(self: Datetime, allocator: std.mem.Allocator) ![]const u8 {
        const weekdays = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
        const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
        const wd = self.weekday();
        return std.fmt.allocPrint(allocator, "{s} {s} {d: >2} {d:0>2}:{d:0>2}:{d:0>2} {d}", .{
            weekdays[@intCast(wd)], months[@intCast(self.month - 1)], self.day, self.hour, self.minute, self.second, self.year,
        });
    }

    /// Get day of week (0=Monday, 6=Sunday)
    pub fn weekday(self: Datetime) i64 {
        const days = daysFromDate(self.year, self.month, self.day);
        return @mod(days + 3, 7); // Jan 1, 1970 was Thursday (3)
    }

    /// Get ordinal (days since 0001-01-01)
    pub fn toOrdinal(self: Datetime) i64 {
        return daysFromDate(self.year, self.month, self.day) + 719163; // Days from 0001-01-01 to 1970-01-01
    }

    /// Parse from ISO format string "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM:SS"
    pub fn parseIsoformat(s: []const u8) !Datetime {
        if (s.len < 10) return error.InvalidFormat;
        const year = std.fmt.parseInt(u32, s[0..4], 10) catch return error.InvalidFormat;
        const month = std.fmt.parseInt(u8, s[5..7], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, s[8..10], 10) catch return error.InvalidFormat;
        var hour: u8 = 0;
        var minute: u8 = 0;
        var second: u8 = 0;
        var microsecond: u32 = 0;
        if (s.len >= 19 and (s[10] == 'T' or s[10] == ' ')) {
            hour = std.fmt.parseInt(u8, s[11..13], 10) catch 0;
            minute = std.fmt.parseInt(u8, s[14..16], 10) catch 0;
            second = std.fmt.parseInt(u8, s[17..19], 10) catch 0;
            if (s.len > 20 and s[19] == '.') {
                const usec_str = s[20..@min(26, s.len)];
                microsecond = std.fmt.parseInt(u32, usec_str, 10) catch 0;
                var mult: u32 = 1;
                var i: usize = usec_str.len;
                while (i < 6) : (i += 1) mult *= 10;
                microsecond *= mult;
            }
        }
        return Datetime{ .year = year, .month = month, .day = day, .hour = hour, .minute = minute, .second = second, .microsecond = microsecond };
    }

    /// Add timedelta to datetime
    pub fn addTimedelta(self: Datetime, td: Timedelta) Datetime {
        // Convert to timestamp, add delta, convert back
        const ts = self.toTimestamp();
        const delta_secs = td.totalSeconds();
        const new_ts: i64 = @intFromFloat(ts + delta_secs);
        return Datetime.fromTimestamp(new_ts);
    }

    /// Subtract timedelta from datetime
    pub fn subTimedelta(self: Datetime, td: Timedelta) Datetime {
        const ts = self.toTimestamp();
        const delta_secs = td.totalSeconds();
        const new_ts: i64 = @intFromFloat(ts - delta_secs);
        return Datetime.fromTimestamp(new_ts);
    }

    /// Get difference between two datetimes as timedelta
    pub fn diff(self: Datetime, other: Datetime) Timedelta {
        const ts1 = self.toTimestamp();
        const ts2 = other.toTimestamp();
        const diff_secs = ts1 - ts2;
        const days: i64 = @intFromFloat(@floor(diff_secs / 86400.0));
        const remaining_secs: i64 = @intFromFloat(@mod(diff_secs, 86400.0));
        return Timedelta{
            .days = days,
            .seconds = remaining_secs,
            .microseconds = 0,
        };
    }
};

/// Extend Datetime with additional CPython-compatible methods
pub const DatetimeExt = struct {
    /// replace(year, month, day, ...) - return datetime with some fields replaced
    pub fn replace(dt: Datetime, year: ?u32, month: ?u8, day: ?u8, hour: ?u8, minute: ?u8, second: ?u8, microsecond: ?u32) Datetime {
        return Datetime{
            .year = year orelse dt.year,
            .month = month orelse dt.month,
            .day = day orelse dt.day,
            .hour = hour orelse dt.hour,
            .minute = minute orelse dt.minute,
            .second = second orelse dt.second,
            .microsecond = microsecond orelse dt.microsecond,
        };
    }

    /// date() - extract Date from Datetime
    pub fn toDate(dt: Datetime) Date {
        return Date{
            .year = dt.year,
            .month = dt.month,
            .day = dt.day,
        };
    }

    /// time() - extract Time from Datetime
    pub fn toTime(dt: Datetime) Time {
        return Time{
            .hour = dt.hour,
            .minute = dt.minute,
            .second = dt.second,
            .microsecond = dt.microsecond,
        };
    }

    /// isoweekday() - day of week (1=Monday, 7=Sunday)
    pub fn isoweekday(dt: Datetime) i64 {
        return dt.weekday() + 1;
    }

    /// isocalendar() - return (year, week, weekday) tuple
    pub fn isocalendar(dt: Datetime) struct { i64, i64, i64 } {
        const ordinal = dt.toOrdinal();
        const weekday_val = dt.weekday() + 1; // 1=Monday

        // ISO week number calculation
        const jan1_ordinal = daysFromDate(dt.year, 1, 1) + 719163;
        const jan1_weekday = @mod(daysFromDate(dt.year, 1, 1) + 3, 7) + 1;

        var week_num: i64 = @divFloor(ordinal - jan1_ordinal + jan1_weekday - 1, 7);
        if (jan1_weekday > 4) week_num -= 1;
        if (week_num < 1) {
            // Week belongs to previous year
            return .{ @as(i64, dt.year) - 1, 52, weekday_val };
        }
        if (week_num > 52) {
            // Check if it's week 1 of next year
            const dec31_weekday = @mod(daysFromDate(dt.year, 12, 31) + 3, 7) + 1;
            if (dec31_weekday < 4) {
                return .{ @as(i64, dt.year) + 1, 1, weekday_val };
            }
        }
        return .{ @as(i64, dt.year), week_num, weekday_val };
    }

    /// timestamp() - return POSIX timestamp
    pub fn timestamp(dt: Datetime) f64 {
        return dt.toTimestamp();
    }

    /// timetuple() - return time.struct_time (as a tuple for now)
    pub fn timetuple(dt: Datetime) struct { i64, i64, i64, i64, i64, i64, i64, i64, i64 } {
        const days_in_months = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var yday: i64 = dt.day;
        var m: u8 = 1;
        while (m < dt.month) : (m += 1) {
            yday += days_in_months[m - 1];
            if (m == 2 and isLeapYear(dt.year)) yday += 1;
        }
        return .{
            @as(i64, dt.year),
            @as(i64, dt.month),
            @as(i64, dt.day),
            @as(i64, dt.hour),
            @as(i64, dt.minute),
            @as(i64, dt.second),
            dt.weekday(),
            yday,
            -1, // tm_isdst
        };
    }
};

// =============================================================================
// Public API for codegen
// =============================================================================

/// datetime.datetime.now() - returns string representation
pub fn datetimeNow(allocator: std.mem.Allocator) !*runtime.PyObject {
    const dt = Datetime.now();
    return dt.toPyString(allocator);
}

/// datetime.datetime constructor with all fields
pub fn datetime(year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, microsecond: i64) Datetime {
    return Datetime{
        .year = @intCast(year),
        .month = @intCast(month),
        .day = @intCast(day),
        .hour = @intCast(hour),
        .minute = @intCast(minute),
        .second = @intCast(second),
        .microsecond = @intCast(microsecond),
    };
}

/// datetime.datetime.utcnow() - UTC current time (deprecated in Python 3.12 but still available)
pub fn utcnow() Datetime {
    const ts = std.time.timestamp();
    return Datetime.fromTimestamp(ts);
}

/// datetime.datetime.utcfromtimestamp(timestamp)
pub fn utcfromtimestamp(ts: f64) Datetime {
    return Datetime.fromTimestamp(@intFromFloat(ts));
}

/// datetime.combine(date, time) -> datetime
pub fn combine(d: Date, t: Time) Datetime {
    return Datetime{
        .year = d.year,
        .month = d.month,
        .day = d.day,
        .hour = t.hour,
        .minute = t.minute,
        .second = t.second,
        .microsecond = t.microsecond,
    };
}

/// datetime.fromisocalendar(year, week, day) -> datetime
/// Create a datetime from an ISO calendar date with time at midnight
pub fn datetimeFromIsocalendar(year: i64, week: i64, day: i64) !Datetime {
    const date_module = @import("date.zig");
    const d = try date_module.dateFromIsocalendar(year, week, day);
    return Datetime{
        .year = d.year,
        .month = d.month,
        .day = d.day,
        .hour = 0,
        .minute = 0,
        .second = 0,
        .microsecond = 0,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "datetime.now()" {
    const dt = Datetime.now();
    // Should be a reasonable year
    try std.testing.expect(dt.year >= 2020);
    try std.testing.expect(dt.month >= 1 and dt.month <= 12);
    try std.testing.expect(dt.day >= 1 and dt.day <= 31);
}

test "datetime.toString()" {
    const allocator = std.testing.allocator;
    const dt = Datetime{
        .year = 2025,
        .month = 11,
        .day = 25,
        .hour = 14,
        .minute = 30,
        .second = 45,
        .microsecond = 123456,
    };
    const str = try dt.toString(allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("2025-11-25 14:30:45.123456", str);
}
