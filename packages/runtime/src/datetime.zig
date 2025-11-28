/// DateTime module - Python datetime.datetime, datetime.date, datetime.timedelta support
const std = @import("std");
const runtime = @import("runtime.zig");

/// Datetime struct - represents datetime.datetime
pub const Datetime = struct {
    year: u32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32,

    /// Create datetime.datetime.now() using local time
    pub fn now() Datetime {
        const ts = std.time.timestamp();
        // Get local timezone offset (hardcoded PST -8 hours for now)
        // TODO: Use proper timezone detection
        const local_offset: i64 = -8 * 3600; // PST offset
        return fromTimestamp(ts + local_offset);
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

    /// Convert to string: YYYY-MM-DD HH:MM:SS.ffffff (Python format)
    pub fn toString(self: Datetime, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
            self.year,
            self.month,
            self.day,
            self.hour,
            self.minute,
            self.second,
            self.microsecond,
        });
    }

    /// Create PyString from datetime
    pub fn toPyString(self: Datetime, allocator: std.mem.Allocator) !*runtime.PyObject {
        const str = try self.toString(allocator);
        return try runtime.PyString.create(allocator, str);
    }
};

/// Date struct - represents datetime.date
pub const Date = struct {
    year: i32,
    month: u8,
    day: u8,

    /// Create datetime.date.today()
    pub fn today() Date {
        const ts = std.time.timestamp();
        const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(ts) };
        const year_day = epoch_secs.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return Date{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
        };
    }

    /// Convert to string: YYYY-MM-DD
    pub fn toString(self: Date, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            self.year,
            self.month,
            self.day,
        });
    }

    /// Create PyString from date
    pub fn toPyString(self: Date, allocator: std.mem.Allocator) !*runtime.PyObject {
        const str = try self.toString(allocator);
        return try runtime.PyString.create(allocator, str);
    }
};

/// Timedelta struct - represents datetime.timedelta
pub const Timedelta = struct {
    days: i64,
    seconds: i64,
    microseconds: i64,

    /// Create timedelta from days (most common usage)
    pub fn fromDays(days: i64) Timedelta {
        return Timedelta{
            .days = days,
            .seconds = 0,
            .microseconds = 0,
        };
    }

    /// Create timedelta with all components
    pub fn init(days: i64, seconds: i64, microseconds: i64) Timedelta {
        return Timedelta{
            .days = days,
            .seconds = seconds,
            .microseconds = microseconds,
        };
    }

    /// Total seconds in the timedelta
    pub fn totalSeconds(self: Timedelta) f64 {
        const day_secs: f64 = @floatFromInt(self.days * 86400);
        const secs: f64 = @floatFromInt(self.seconds);
        const usecs: f64 = @floatFromInt(self.microseconds);
        return day_secs + secs + usecs / 1_000_000.0;
    }

    /// Convert to string representation
    pub fn toString(self: Timedelta, allocator: std.mem.Allocator) ![]const u8 {
        if (self.seconds == 0 and self.microseconds == 0) {
            if (self.days == 1) {
                return std.fmt.allocPrint(allocator, "1 day, 0:00:00", .{});
            } else {
                return std.fmt.allocPrint(allocator, "{d} days, 0:00:00", .{self.days});
            }
        }

        const hours = @divTrunc(self.seconds, 3600);
        const mins = @divTrunc(@mod(self.seconds, 3600), 60);
        const secs = @mod(self.seconds, 60);

        if (self.days == 1) {
            return std.fmt.allocPrint(allocator, "1 day, {d}:{d:0>2}:{d:0>2}", .{ hours, mins, secs });
        } else if (self.days == 0) {
            return std.fmt.allocPrint(allocator, "{d}:{d:0>2}:{d:0>2}", .{ hours, mins, secs });
        } else {
            return std.fmt.allocPrint(allocator, "{d} days, {d}:{d:0>2}:{d:0>2}", .{ self.days, hours, mins, secs });
        }
    }

    /// Create PyString from timedelta
    pub fn toPyString(self: Timedelta, allocator: std.mem.Allocator) !*runtime.PyObject {
        const str = try self.toString(allocator);
        return try runtime.PyString.create(allocator, str);
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

/// datetime.date.today() - returns string representation
pub fn dateToday(allocator: std.mem.Allocator) !*runtime.PyObject {
    const d = Date.today();
    return d.toPyString(allocator);
}

/// datetime.timedelta(days=N) - returns Timedelta struct
pub fn timedelta(days: i64) Timedelta {
    return Timedelta.fromDays(days);
}

/// datetime.timedelta(days, seconds, microseconds) - full constructor
pub fn timedeltaFull(days: i64, seconds: i64, microseconds: i64) Timedelta {
    return Timedelta.init(days, seconds, microseconds);
}

/// datetime.timedelta(days=N) - returns PyString for codegen
pub fn timedeltaToPyString(allocator: std.mem.Allocator, days: i64) !*runtime.PyObject {
    const td = Timedelta.fromDays(days);
    return td.toPyString(allocator);
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

test "date.today()" {
    const d = Date.today();
    try std.testing.expect(d.year >= 2020);
    try std.testing.expect(d.month >= 1 and d.month <= 12);
    try std.testing.expect(d.day >= 1 and d.day <= 31);
}

test "timedelta" {
    const td = Timedelta.fromDays(7);
    try std.testing.expectEqual(@as(i64, 7), td.days);
    try std.testing.expectEqual(@as(f64, 604800.0), td.totalSeconds());
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
        .microsecond = 0,
    };
    const str = try dt.toString(allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("2025-11-25 14:30:45", str);
}

test "date.toString()" {
    const allocator = std.testing.allocator;
    const d = Date{
        .year = 2025,
        .month = 11,
        .day = 25,
    };
    const str = try d.toString(allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("2025-11-25", str);
}
