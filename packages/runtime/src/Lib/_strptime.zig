//! Python '_strptime' module - String parsing for time
//!
//! Provides strptime() implementation for parsing time strings.
//!
//! Mirrors: CPython Lib/_strptime.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Weekday names (full)
pub const WEEKDAY_NAMES = [_][]const u8{
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
};

/// Weekday abbreviations
pub const WEEKDAY_ABBR = [_][]const u8{
    "mon", "tue", "wed", "thu", "fri", "sat", "sun",
};

/// Month names (full)
pub const MONTH_NAMES = [_][]const u8{
    "", "january", "february", "march", "april", "may", "june",
    "july", "august", "september", "october", "november", "december",
};

/// Month abbreviations
pub const MONTH_ABBR = [_][]const u8{
    "", "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec",
};

/// AM/PM indicators
pub const AM_PM = [_][]const u8{ "am", "pm" };

// ============================================================================
// TimeRE - Regular expression patterns for time parsing
// ============================================================================

/// Time regex patterns
pub const TimeRE = struct {
    const Self = @This();

    locale_time: LocaleTime,

    pub fn init() Self {
        return .{
            .locale_time = LocaleTime.init(),
        };
    }

    /// Get pattern for directive
    pub fn pattern(self: *Self, directive: u8) ?[]const u8 {
        _ = self;
        return switch (directive) {
            'd' => "(?P<d>3[0-1]|[1-2]\\d|0[1-9]|[1-9]| [1-9])", // Day of month
            'm' => "(?P<m>1[0-2]|0[1-9]|[1-9])", // Month number
            'y' => "(?P<y>\\d\\d)", // 2-digit year
            'Y' => "(?P<Y>\\d\\d\\d\\d)", // 4-digit year
            'H' => "(?P<H>2[0-3]|[0-1]\\d|\\d)", // Hour (24)
            'I' => "(?P<I>1[0-2]|0[1-9]|[1-9])", // Hour (12)
            'M' => "(?P<M>[0-5]\\d|\\d)", // Minute
            'S' => "(?P<S>6[0-1]|[0-5]\\d|\\d)", // Second
            'f' => "(?P<f>[0-9]{1,6})", // Microsecond
            'j' => "(?P<j>36[0-6]|3[0-5]\\d|[1-2]\\d\\d|0[1-9]\\d|00[1-9]|[1-9]\\d|0[1-9]|[1-9])", // Day of year
            'U' => "(?P<U>5[0-3]|[0-4]\\d|\\d)", // Week number (Sunday)
            'W' => "(?P<W>5[0-3]|[0-4]\\d|\\d)", // Week number (Monday)
            'w' => "(?P<w>[0-6])", // Weekday number
            'z' => "(?P<z>[+-]\\d\\d[0-5]\\d|Z)", // UTC offset
            'Z' => "(?P<Z>[A-Z][A-Za-z_]+)", // Timezone name
            '%' => "%",
            else => null,
        };
    }
};

// ============================================================================
// LocaleTime - Locale-specific time info
// ============================================================================

/// Locale time information
pub const LocaleTime = struct {
    const Self = @This();

    // Weekdays
    a_weekday: [7][]const u8,
    f_weekday: [7][]const u8,

    // Months
    a_month: [13][]const u8,
    f_month: [13][]const u8,

    // AM/PM
    am_pm: [2][]const u8,

    // Date/time formats
    lc_date_time: []const u8,
    lc_date: []const u8,
    lc_time: []const u8,

    // Timezone
    timezone: [2][]const u8,

    pub fn init() Self {
        var self = Self{
            .a_weekday = undefined,
            .f_weekday = undefined,
            .a_month = undefined,
            .f_month = undefined,
            .am_pm = .{ "AM", "PM" },
            .lc_date_time = "%a %b %d %H:%M:%S %Y",
            .lc_date = "%m/%d/%y",
            .lc_time = "%H:%M:%S",
            .timezone = .{ "UTC", "UTC" },
        };

        // Set weekday names
        for (0..7) |i| {
            self.a_weekday[i] = WEEKDAY_ABBR[i];
            self.f_weekday[i] = WEEKDAY_NAMES[i];
        }

        // Set month names
        for (0..13) |i| {
            self.a_month[i] = MONTH_ABBR[i];
            self.f_month[i] = MONTH_NAMES[i];
        }

        return self;
    }
};

// ============================================================================
// Parsed Time Structure
// ============================================================================

/// Result of parsing a time string
pub const ParsedTime = struct {
    year: ?i32 = null,
    month: ?u8 = null,
    day: ?u8 = null,
    hour: ?u8 = null,
    minute: ?u8 = null,
    second: ?u8 = null,
    microsecond: ?u32 = null,
    weekday: ?u8 = null,
    yearday: ?u16 = null,
    tz_offset: ?i32 = null,
    tz_name: ?[]const u8 = null,

    /// Convert to struct_time-like array
    pub fn toTuple(self: ParsedTime) [9]i32 {
        return .{
            self.year orelse 1900,
            @as(i32, self.month orelse 1),
            @as(i32, self.day orelse 1),
            @as(i32, self.hour orelse 0),
            @as(i32, self.minute orelse 0),
            @as(i32, self.second orelse 0),
            @as(i32, self.weekday orelse 0),
            @as(i32, self.yearday orelse 1),
            if (self.tz_offset != null) @as(i32, 1) else @as(i32, -1),
        };
    }
};

// ============================================================================
// strptime Implementation
// ============================================================================

/// Parse error
pub const ParseError = error{
    InvalidFormat,
    ValueOutOfRange,
    UnmatchedData,
};

/// Parse a time string according to format
pub fn strptime(data: []const u8, format: []const u8) !ParsedTime {
    var result = ParsedTime{};
    var data_idx: usize = 0;
    var fmt_idx: usize = 0;

    while (fmt_idx < format.len) {
        if (format[fmt_idx] == '%') {
            fmt_idx += 1;
            if (fmt_idx >= format.len) return ParseError.InvalidFormat;

            const directive = format[fmt_idx];
            fmt_idx += 1;

            // Parse based on directive
            switch (directive) {
                'Y' => {
                    // 4-digit year
                    if (data_idx + 4 > data.len) return ParseError.UnmatchedData;
                    result.year = std.fmt.parseInt(i32, data[data_idx .. data_idx + 4], 10) catch return ParseError.InvalidFormat;
                    data_idx += 4;
                },
                'y' => {
                    // 2-digit year
                    if (data_idx + 2 > data.len) return ParseError.UnmatchedData;
                    var year = std.fmt.parseInt(i32, data[data_idx .. data_idx + 2], 10) catch return ParseError.InvalidFormat;
                    // Interpret 2-digit year
                    if (year < 69) {
                        year += 2000;
                    } else {
                        year += 1900;
                    }
                    result.year = year;
                    data_idx += 2;
                },
                'm' => {
                    // Month (01-12)
                    const end = @min(data_idx + 2, data.len);
                    result.month = std.fmt.parseInt(u8, data[data_idx..end], 10) catch return ParseError.InvalidFormat;
                    if (result.month.? < 1 or result.month.? > 12) return ParseError.ValueOutOfRange;
                    data_idx = end;
                },
                'd' => {
                    // Day (01-31)
                    const end = @min(data_idx + 2, data.len);
                    result.day = std.fmt.parseInt(u8, data[data_idx..end], 10) catch return ParseError.InvalidFormat;
                    if (result.day.? < 1 or result.day.? > 31) return ParseError.ValueOutOfRange;
                    data_idx = end;
                },
                'H' => {
                    // Hour (00-23)
                    const end = @min(data_idx + 2, data.len);
                    result.hour = std.fmt.parseInt(u8, data[data_idx..end], 10) catch return ParseError.InvalidFormat;
                    if (result.hour.? > 23) return ParseError.ValueOutOfRange;
                    data_idx = end;
                },
                'I' => {
                    // Hour (01-12)
                    const end = @min(data_idx + 2, data.len);
                    result.hour = std.fmt.parseInt(u8, data[data_idx..end], 10) catch return ParseError.InvalidFormat;
                    if (result.hour.? < 1 or result.hour.? > 12) return ParseError.ValueOutOfRange;
                    data_idx = end;
                },
                'M' => {
                    // Minute (00-59)
                    const end = @min(data_idx + 2, data.len);
                    result.minute = std.fmt.parseInt(u8, data[data_idx..end], 10) catch return ParseError.InvalidFormat;
                    if (result.minute.? > 59) return ParseError.ValueOutOfRange;
                    data_idx = end;
                },
                'S' => {
                    // Second (00-61)
                    const end = @min(data_idx + 2, data.len);
                    result.second = std.fmt.parseInt(u8, data[data_idx..end], 10) catch return ParseError.InvalidFormat;
                    if (result.second.? > 61) return ParseError.ValueOutOfRange;
                    data_idx = end;
                },
                'f' => {
                    // Microseconds
                    var end = data_idx;
                    while (end < data.len and end - data_idx < 6 and data[end] >= '0' and data[end] <= '9') {
                        end += 1;
                    }
                    if (end == data_idx) return ParseError.InvalidFormat;
                    var us = std.fmt.parseInt(u32, data[data_idx..end], 10) catch return ParseError.InvalidFormat;
                    // Pad to 6 digits
                    const digits = end - data_idx;
                    var i: usize = digits;
                    while (i < 6) : (i += 1) {
                        us *= 10;
                    }
                    result.microsecond = us;
                    data_idx = end;
                },
                'j' => {
                    // Day of year (001-366)
                    const end = @min(data_idx + 3, data.len);
                    result.yearday = std.fmt.parseInt(u16, data[data_idx..end], 10) catch return ParseError.InvalidFormat;
                    if (result.yearday.? < 1 or result.yearday.? > 366) return ParseError.ValueOutOfRange;
                    data_idx = end;
                },
                'w' => {
                    // Weekday (0-6)
                    if (data_idx >= data.len) return ParseError.UnmatchedData;
                    result.weekday = std.fmt.parseInt(u8, data[data_idx .. data_idx + 1], 10) catch return ParseError.InvalidFormat;
                    if (result.weekday.? > 6) return ParseError.ValueOutOfRange;
                    data_idx += 1;
                },
                'z' => {
                    // Timezone offset (+HHMM or -HHMM or Z)
                    if (data_idx >= data.len) return ParseError.UnmatchedData;
                    if (data[data_idx] == 'Z') {
                        result.tz_offset = 0;
                        data_idx += 1;
                    } else if (data[data_idx] == '+' or data[data_idx] == '-') {
                        const sign: i32 = if (data[data_idx] == '-') -1 else 1;
                        data_idx += 1;
                        if (data_idx + 4 > data.len) return ParseError.UnmatchedData;
                        const hours = std.fmt.parseInt(i32, data[data_idx .. data_idx + 2], 10) catch return ParseError.InvalidFormat;
                        const mins = std.fmt.parseInt(i32, data[data_idx + 2 .. data_idx + 4], 10) catch return ParseError.InvalidFormat;
                        result.tz_offset = sign * (hours * 3600 + mins * 60);
                        data_idx += 4;
                    } else {
                        return ParseError.InvalidFormat;
                    }
                },
                '%' => {
                    // Literal %
                    if (data_idx >= data.len or data[data_idx] != '%') return ParseError.UnmatchedData;
                    data_idx += 1;
                },
                else => return ParseError.InvalidFormat,
            }
        } else {
            // Literal character match
            if (data_idx >= data.len) return ParseError.UnmatchedData;
            if (data[data_idx] != format[fmt_idx]) {
                // Allow whitespace flexibility
                if (std.ascii.isWhitespace(format[fmt_idx]) and std.ascii.isWhitespace(data[data_idx])) {
                    // Skip whitespace in both
                    while (fmt_idx < format.len and std.ascii.isWhitespace(format[fmt_idx])) {
                        fmt_idx += 1;
                    }
                    while (data_idx < data.len and std.ascii.isWhitespace(data[data_idx])) {
                        data_idx += 1;
                    }
                    continue;
                }
                return ParseError.UnmatchedData;
            }
            fmt_idx += 1;
            data_idx += 1;
        }
    }

    return result;
}

/// Parse time string (Python-compatible wrapper)
pub fn _strptime_time(data: []const u8, format: []const u8) ![9]i32 {
    const parsed = try strptime(data, format);
    return parsed.toTuple();
}

// ============================================================================
// Tests
// ============================================================================

test "strptime basic date" {
    const result = try strptime("2024-01-15", "%Y-%m-%d");
    try std.testing.expectEqual(@as(i32, 2024), result.year.?);
    try std.testing.expectEqual(@as(u8, 1), result.month.?);
    try std.testing.expectEqual(@as(u8, 15), result.day.?);
}

test "strptime with time" {
    const result = try strptime("2024-01-15 14:30:45", "%Y-%m-%d %H:%M:%S");
    try std.testing.expectEqual(@as(i32, 2024), result.year.?);
    try std.testing.expectEqual(@as(u8, 14), result.hour.?);
    try std.testing.expectEqual(@as(u8, 30), result.minute.?);
    try std.testing.expectEqual(@as(u8, 45), result.second.?);
}

test "strptime 2-digit year" {
    const result1 = try strptime("01/15/24", "%m/%d/%y");
    try std.testing.expectEqual(@as(i32, 2024), result1.year.?);

    const result2 = try strptime("01/15/99", "%m/%d/%y");
    try std.testing.expectEqual(@as(i32, 1999), result2.year.?);
}

test "strptime microseconds" {
    const result = try strptime("14:30:45.123456", "%H:%M:%S.%f");
    try std.testing.expectEqual(@as(u32, 123456), result.microsecond.?);
}

test "strptime timezone Z" {
    const result = try strptime("2024-01-15T14:30:45Z", "%Y-%m-%dT%H:%M:%SZ");
    try std.testing.expectEqual(@as(i32, 2024), result.year.?);
}

test "LocaleTime init" {
    const lt = LocaleTime.init();
    try std.testing.expectEqualStrings("mon", lt.a_weekday[0]);
    try std.testing.expectEqualStrings("january", lt.f_month[1]);
}

test "TimeRE patterns" {
    var re = TimeRE.init();
    try std.testing.expect(re.pattern('Y') != null);
    try std.testing.expect(re.pattern('m') != null);
    try std.testing.expect(re.pattern('?') == null);
}
