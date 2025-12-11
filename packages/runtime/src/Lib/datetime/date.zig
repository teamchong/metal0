/// Date struct - represents datetime.date

const std = @import("std");
const runtime = @import("../../runtime.zig");
const Timedelta = @import("timedelta.zig").Timedelta;

const c = @cImport({
    @cInclude("time.h");
});

/// Helper function to calculate days since Unix epoch (1970-01-01) from year, month, day
pub fn daysFromDate(year: u32, month: u8, day: u8) i64 {
    // Use Rata Die algorithm
    var y: i64 = @intCast(year);
    var m: i64 = @intCast(month);
    const d: i64 = @intCast(day);

    if (m <= 2) {
        y -= 1;
        m += 12;
    }

    const era = @divFloor(y, 400);
    const yoe = @mod(y, 400);
    const doy = @divFloor(153 * (m - 3) + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;

    return era * 146097 + doe - 719468; // Days since 1970-01-01
}

fn isLeapYear(year: u32) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

/// Date struct - represents datetime.date
pub const Date = struct {
    year: u32,
    month: u8,
    day: u8,

    /// Create datetime.date.today() using local time
    pub fn today() Date {
        const ts = std.time.timestamp();
        // Use C localtime to get proper timezone-aware local date
        var time_val: c.time_t = @intCast(ts);
        const local_tm = c.localtime(&time_val);
        if (local_tm) |tm_ptr| {
            const tm = tm_ptr.*;
            return Date{
                .year = @intCast(tm.tm_year + 1900),
                .month = @intCast(tm.tm_mon + 1),
                .day = @intCast(tm.tm_mday),
            };
        }
        // Fallback to UTC
        const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(ts) };
        const year_day = epoch_secs.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        return Date{
            .year = @intCast(year_day.year),
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

    /// Parse from ISO format string "YYYY-MM-DD"
    pub fn parseIsoformat(s: []const u8) !Date {
        if (s.len < 10) return error.InvalidFormat;
        const year = std.fmt.parseInt(u32, s[0..4], 10) catch return error.InvalidFormat;
        const month = std.fmt.parseInt(u8, s[5..7], 10) catch return error.InvalidFormat;
        const day = std.fmt.parseInt(u8, s[8..10], 10) catch return error.InvalidFormat;
        return Date{ .year = year, .month = month, .day = day };
    }

    /// Create from ordinal (days since 0001-01-01)
    pub fn fromOrdinal(ordinal: i64) Date {
        const days_since_1970 = ordinal - 719163;
        const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(days_since_1970 * 86400) };
        const year_day = epoch_secs.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        return Date{
            .year = @intCast(year_day.year),
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
        };
    }

    /// Get day of week (0=Monday, 6=Sunday)
    pub fn weekday(self: Date) i64 {
        const days = daysFromDate(self.year, self.month, self.day);
        return @mod(days + 3, 7);
    }

    /// Get ordinal (days since 0001-01-01)
    pub fn toOrdinal(self: Date) i64 {
        return daysFromDate(self.year, self.month, self.day) + 719163;
    }
};

/// Extend Date with additional CPython-compatible methods
pub const DateExt = struct {
    /// replace(year, month, day) - return date with some fields replaced
    pub fn replace(d: Date, year: ?u32, month: ?u8, day: ?u8) Date {
        return Date{
            .year = year orelse d.year,
            .month = month orelse d.month,
            .day = day orelse d.day,
        };
    }

    /// isoweekday() - day of week (1=Monday, 7=Sunday)
    pub fn isoweekday(d: Date) i64 {
        return d.weekday() + 1;
    }

    /// isocalendar() - return (year, week, weekday) tuple
    pub fn isocalendar(d: Date) struct { i64, i64, i64 } {
        // Import Datetime to avoid circular dependency issue
        const datetime_impl = @import("datetime_impl.zig");
        const dt = datetime_impl.Datetime{
            .year = d.year,
            .month = d.month,
            .day = d.day,
            .hour = 0,
            .minute = 0,
            .second = 0,
            .microsecond = 0,
        };
        return datetime_impl.DatetimeExt.isocalendar(dt);
    }

    /// ctime() - return ctime-style string
    pub fn ctime(d: Date, allocator: std.mem.Allocator) ![]const u8 {
        const weekdays = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
        const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
        const wd = d.weekday();
        return std.fmt.allocPrint(allocator, "{s} {s} {d: >2} 00:00:00 {d}", .{
            weekdays[@intCast(wd)], months[@intCast(d.month - 1)], d.day, d.year,
        });
    }

    /// timetuple() - return time.struct_time
    pub fn timetuple(d: Date) struct { i64, i64, i64, i64, i64, i64, i64, i64, i64 } {
        const days_in_months = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var yday: i64 = d.day;
        var m: u8 = 1;
        while (m < d.month) : (m += 1) {
            yday += days_in_months[m - 1];
            if (m == 2 and isLeapYear(d.year)) yday += 1;
        }
        return .{
            @as(i64, d.year),
            @as(i64, d.month),
            @as(i64, d.day),
            0, // hour
            0, // minute
            0, // second
            d.weekday(),
            yday,
            -1, // tm_isdst
        };
    }
};

// =============================================================================
// Public API for codegen
// =============================================================================

/// datetime.date.today() - returns string representation
pub fn dateToday(allocator: std.mem.Allocator) !*runtime.PyObject {
    const d = Date.today();
    return d.toPyString(allocator);
}

/// datetime.date(year, month, day) - returns Date struct
pub fn date(year: i64, month: i64, day: i64) Date {
    return Date{
        .year = @intCast(year),
        .month = @intCast(month),
        .day = @intCast(day),
    };
}

/// date.fromisocalendar(year, week, day) -> date
/// Create a date from an ISO calendar date (year, week number, day of week)
/// Week 1 is the week containing the first Thursday of the year.
/// Day 1 is Monday, Day 7 is Sunday.
pub fn dateFromIsocalendar(year: i64, week: i64, day: i64) !Date {
    if (week < 1 or week > 53) return error.ValueError;
    if (day < 1 or day > 7) return error.ValueError;

    // Find January 4th of the given year (always in week 1)
    const jan4 = Date{ .year = @intCast(year), .month = 1, .day = 4 };
    const jan4_ordinal = jan4.toOrdinal();
    const jan4_weekday = jan4.weekday(); // 0 = Monday

    // Find the Monday of week 1
    const week1_monday = jan4_ordinal - jan4_weekday;

    // Calculate the ordinal for the target date
    const target_ordinal = week1_monday + (week - 1) * 7 + (day - 1);

    // Validate that the week number is valid for this year
    if (week == 53) {
        // Check if year has 53 weeks
        const dec28 = Date{ .year = @intCast(year), .month = 12, .day = 28 };
        const dec28_weekday = dec28.weekday();
        const last_week_monday = dec28.toOrdinal() - dec28_weekday;
        const weeks_in_year: i64 = @divFloor(last_week_monday - week1_monday, 7) + 1;
        if (weeks_in_year < 53) return error.ValueError;
    }

    return Date.fromOrdinal(target_ordinal);
}

// =============================================================================
// Tests
// =============================================================================

test "date.today()" {
    const d = Date.today();
    try std.testing.expect(d.year >= 2020);
    try std.testing.expect(d.month >= 1 and d.month <= 12);
    try std.testing.expect(d.day >= 1 and d.day <= 31);
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
