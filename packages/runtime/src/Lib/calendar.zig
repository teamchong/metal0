//! CPython source: Lib/calendar.py
//!
//! Provides calendar-related functions, including calendar printing
//! and various date calculations.
//!
//! Mirrors: CPython Lib/calendar.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Days of the week (0 = Monday, 6 = Sunday)
pub const MONDAY = 0;
pub const TUESDAY = 1;
pub const WEDNESDAY = 2;
pub const THURSDAY = 3;
pub const FRIDAY = 4;
pub const SATURDAY = 5;
pub const SUNDAY = 6;

/// Month names (1-indexed, index 0 is empty)
pub const month_name = [_][]const u8{
    "",
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

/// Abbreviated month names
pub const month_abbr = [_][]const u8{
    "",
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
};

/// Day names (0 = Monday)
pub const day_name = [_][]const u8{
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
};

/// Abbreviated day names
pub const day_abbr = [_][]const u8{
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
    "Sun",
};

/// Days in each month (non-leap year, 1-indexed)
const mdays = [_]i32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

// ============================================================================
// Core Calendar Functions
// ============================================================================

/// Returns the day of week for a given date (0=Monday, 6=Sunday)
pub fn weekday(year: i32, month: i32, day: i32) i32 {
    const m = if (month < 3) month + 12 else month;
    const y = if (month < 3) year - 1 else year;
    const k = @rem(y, 100);
    const j = @divFloor(y, 100);
    const h = @rem(@as(i32, day + @divFloor(13 * (m + 1), 5) + k + @divFloor(k, 4) + @divFloor(j, 4) - 2 * j + 700), 7);
    return @rem(h + 5, 7);
}

/// Returns true if year is a leap year
pub fn isleap(year: i32) bool {
    return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or @rem(year, 400) == 0;
}

/// Returns number of days in a given month
pub fn daysInMonth(year: i32, month: i32) i32 {
    const days = [_]i32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 and isleap(year)) return 29;
    return days[@intCast(month)];
}

/// Calendar row type - 7 days per week
pub const WeekRow = [7]i32;

/// Returns a matrix where each row represents a week, and each value is a day number (0 = not in month)
pub fn monthcalendar(allocator: std.mem.Allocator, year_val: anytype, month_val: anytype) []WeekRow {
    const year: i32 = @intCast(year_val);
    const month: i32 = @intCast(month_val);

    const first_day = weekday(year, month, 1);
    const ndays = daysInMonth(year, month);

    // Calculate number of weeks needed
    const total_cells = @as(usize, @intCast(first_day)) + @as(usize, @intCast(ndays));
    const nweeks = (total_cells + 6) / 7;

    // Allocate result
    var result = allocator.alloc(WeekRow, nweeks) catch return &[_]WeekRow{};

    var day: i32 = 1;
    for (0..nweeks) |week| {
        for (0..7) |dow| {
            const cell_index = week * 7 + dow;
            const day_offset = @as(i32, @intCast(cell_index)) - first_day;

            if (day_offset >= 0 and day_offset < ndays) {
                result[week][dow] = day_offset + 1;
            } else {
                result[week][dow] = 0;
            }
        }
        day += 7;
    }

    return result;
}

/// Number of leap years in range [y1, y2)
pub fn leapdays(y1: i32, y2: i32) i32 {
    const y1_adj = y1 - 1;
    const y2_adj = y2 - 1;
    return (@divFloor(y2_adj, 4) - @divFloor(y1_adj, 4)) -
        (@divFloor(y2_adj, 100) - @divFloor(y1_adj, 100)) +
        (@divFloor(y2_adj, 400) - @divFloor(y1_adj, 400));
}

/// Return weekday (0-6 ~ Mon-Sun) and number of days (28-31) for year, month
pub fn monthrange(year: i32, month: i32) struct { first_weekday: i32, ndays: i32 } {
    return .{
        .first_weekday = weekday(year, month, 1),
        .ndays = daysInMonth(year, month),
    };
}

// ============================================================================
// Calendar Class (simplified)
// ============================================================================

pub const Calendar = struct {
    firstweekday: i32 = MONDAY,

    pub fn init() Calendar {
        return .{};
    }

    pub fn initWithFirstWeekday(firstweekday: i32) Calendar {
        return .{ .firstweekday = firstweekday };
    }

    pub fn setfirstweekday(self: *Calendar, firstweekday: i32) void {
        self.firstweekday = firstweekday;
    }

    pub fn getfirstweekday(self: *const Calendar) i32 {
        return self.firstweekday;
    }

    /// Return an iterator for one week of weekday numbers
    pub fn iterweekdays(self: *const Calendar) [7]i32 {
        var result: [7]i32 = undefined;
        for (0..7) |i| {
            result[i] = @rem(self.firstweekday + @as(i32, @intCast(i)), 7);
        }
        return result;
    }

    /// Return weeks in a month as an iterator of tuples (day, weekday)
    pub fn itermonthdays2(self: *const Calendar, allocator: std.mem.Allocator, year: i32, month: i32) ![]struct { day: i32, weekday: i32 } {
        var days = std.ArrayList(struct { day: i32, weekday: i32 }).init(allocator);
        errdefer days.deinit();

        const range = monthrange(year, month);
        const first = range.first_weekday;
        const ndays = range.ndays;

        // Days before month (0s with weekday)
        const days_before = @rem(first - self.firstweekday + 7, 7);
        for (0..@as(usize, @intCast(days_before))) |i| {
            try days.append(.{ .day = 0, .weekday = @rem(self.firstweekday + @as(i32, @intCast(i)), 7) });
        }

        // Days in month
        for (1..@as(usize, @intCast(ndays + 1))) |d| {
            const dow = weekday(year, month, @intCast(d));
            try days.append(.{ .day = @intCast(d), .weekday = dow });
        }

        // Days after month to complete the week
        const total = days.items.len;
        const remaining = (7 - @rem(total, 7)) % 7;
        for (0..remaining) |i| {
            const dow = @rem(@as(i32, @intCast(i)) + weekday(year, month, ndays) + 1, 7);
            try days.append(.{ .day = 0, .weekday = dow });
        }

        return days.toOwnedSlice();
    }

    /// Return weeks of a month
    pub fn monthdayscalendar(self: *const Calendar, allocator: std.mem.Allocator, year: i32, month: i32) ![]WeekRow {
        _ = self;
        return monthcalendar(allocator, year, month);
    }
};

// ============================================================================
// Text Calendar
// ============================================================================

pub const TextCalendar = struct {
    cal: Calendar,

    pub fn init() TextCalendar {
        return .{ .cal = Calendar.init() };
    }

    pub fn initWithFirstWeekday(firstweekday: i32) TextCalendar {
        return .{ .cal = Calendar.initWithFirstWeekday(firstweekday) };
    }

    /// Format a weekday name (abbreviated)
    pub fn formatweekday(width: usize) [7][]const u8 {
        var result: [7][]const u8 = undefined;
        for (0..7) |i| {
            const name = day_abbr[i];
            result[i] = if (width >= name.len) name else name[0..width];
        }
        return result;
    }

    /// Format a week header
    pub fn formatweekheader(self: *const TextCalendar, allocator: std.mem.Allocator, width: usize) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        const weekdays = self.cal.iterweekdays();
        for (weekdays, 0..) |dow, i| {
            if (i > 0) try result.append(' ');
            const name = day_abbr[@intCast(dow)];
            const display = if (width >= name.len) name else name[0..width];
            try result.appendSlice(display);
            // Pad to width
            for (display.len..width) |_| {
                try result.append(' ');
            }
        }

        return result.toOwnedSlice();
    }

    /// Format a month name and year
    pub fn formatmonthname(allocator: std.mem.Allocator, year: i32, month: i32, width: usize) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var buf: [64]u8 = undefined;
        const header = std.fmt.bufPrint(&buf, "{s} {d}", .{ month_name[@intCast(month)], year }) catch return result.toOwnedSlice();

        // Center the header
        const padding = if (width > header.len) (width - header.len) / 2 else 0;
        for (0..padding) |_| {
            try result.append(' ');
        }
        try result.appendSlice(header);

        return result.toOwnedSlice();
    }

    /// Format a month as a string
    pub fn formatmonth(self: *const TextCalendar, allocator: std.mem.Allocator, year: i32, month: i32) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        const width: usize = 21; // 7 * 3 = 21 for standard calendar

        // Month name header
        const header = try formatmonthname(allocator, year, month, width);
        defer allocator.free(header);
        try result.appendSlice(header);
        try result.append('\n');

        // Weekday header
        const weekheader = try self.formatweekheader(allocator, 2);
        defer allocator.free(weekheader);
        try result.appendSlice(weekheader);
        try result.append('\n');

        // Days
        const weeks = monthcalendar(allocator, year, month);
        defer allocator.free(weeks);

        for (weeks) |week| {
            for (week, 0..) |day, i| {
                if (i > 0) try result.append(' ');
                if (day == 0) {
                    try result.appendSlice("  ");
                } else {
                    var buf: [8]u8 = undefined;
                    const day_str = std.fmt.bufPrint(&buf, "{d:2}", .{day}) catch "  ";
                    try result.appendSlice(day_str);
                }
            }
            try result.append('\n');
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Module-level functions
// ============================================================================

/// Format a calendar month
pub fn prmonth(allocator: std.mem.Allocator, year: i32, month: i32) ![]u8 {
    const tc = TextCalendar.init();
    return tc.formatmonth(allocator, year, month);
}

/// Get the current time as a tuple (for compatibility)
pub fn timegm(tm: anytype) i64 {
    // Convert struct tm to epoch seconds (simplified)
    const year: i32 = tm.tm_year + 1900;
    const mon: i32 = tm.tm_mon + 1;
    const day: i32 = tm.tm_mday;

    var days: i64 = 0;
    var y: i32 = 1970;
    while (y < year) : (y += 1) {
        days += if (isleap(y)) 366 else 365;
    }
    var m: i32 = 1;
    while (m < mon) : (m += 1) {
        days += daysInMonth(year, m);
    }
    days += day - 1;

    return days * 86400 + tm.tm_hour * 3600 + tm.tm_min * 60 + tm.tm_sec;
}

// ============================================================================
// Tests
// ============================================================================

test "weekday" {
    // January 1, 2024 is a Monday (0)
    try std.testing.expectEqual(@as(i32, 0), weekday(2024, 1, 1));
    // December 25, 2024 is a Wednesday (2)
    try std.testing.expectEqual(@as(i32, 2), weekday(2024, 12, 25));
}

test "isleap" {
    try std.testing.expect(isleap(2024));
    try std.testing.expect(!isleap(2023));
    try std.testing.expect(isleap(2000));
    try std.testing.expect(!isleap(1900));
}

test "daysInMonth" {
    try std.testing.expectEqual(@as(i32, 31), daysInMonth(2024, 1));
    try std.testing.expectEqual(@as(i32, 29), daysInMonth(2024, 2)); // Leap year
    try std.testing.expectEqual(@as(i32, 28), daysInMonth(2023, 2)); // Non-leap year
    try std.testing.expectEqual(@as(i32, 30), daysInMonth(2024, 4));
}

test "leapdays" {
    try std.testing.expectEqual(@as(i32, 1), leapdays(2020, 2021)); // 2020 is leap
    try std.testing.expectEqual(@as(i32, 2), leapdays(2020, 2025)); // 2020, 2024
}

test "monthrange" {
    const range = monthrange(2024, 1);
    try std.testing.expectEqual(@as(i32, 0), range.first_weekday); // Monday
    try std.testing.expectEqual(@as(i32, 31), range.ndays);
}

test "Calendar iterweekdays" {
    const cal = Calendar.init();
    const days = cal.iterweekdays();
    try std.testing.expectEqual(@as(i32, 0), days[0]); // Monday
    try std.testing.expectEqual(@as(i32, 6), days[6]); // Sunday
}

test "month_name" {
    try std.testing.expectEqualStrings("January", month_name[1]);
    try std.testing.expectEqualStrings("December", month_name[12]);
}

test "day_name" {
    try std.testing.expectEqualStrings("Monday", day_name[0]);
    try std.testing.expectEqualStrings("Sunday", day_name[6]);
}
