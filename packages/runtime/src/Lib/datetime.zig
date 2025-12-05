/// DateTime module - Python datetime.datetime, datetime.date, datetime.timedelta support
const std = @import("std");
const runtime = @import("../runtime.zig");
const c = @cImport({
    @cInclude("time.h");
});

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
        // Approximate - doesn't account for leap seconds
        const days = @import("datetime.zig").daysFromDate(self.year, self.month, self.day);
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
        const days = @import("datetime.zig").daysFromDate(self.year, self.month, self.day);
        return @mod(days + 3, 7); // Jan 1, 1970 was Thursday (3)
    }

    /// Get ordinal (days since 0001-01-01)
    pub fn toOrdinal(self: Datetime) i64 {
        return @import("datetime.zig").daysFromDate(self.year, self.month, self.day) + 719163; // Days from 0001-01-01 to 1970-01-01
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
        const days = @import("datetime.zig").daysFromDate(self.year, self.month, self.day);
        return @mod(days + 3, 7);
    }

    /// Get ordinal (days since 0001-01-01)
    pub fn toOrdinal(self: Date) i64 {
        return @import("datetime.zig").daysFromDate(self.year, self.month, self.day) + 719163;
    }
};

/// Time struct - represents datetime.time
pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32,

    /// Convert to string: HH:MM:SS.ffffff
    pub fn toString(self: Time, allocator: std.mem.Allocator) ![]const u8 {
        if (self.microsecond > 0) {
            return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
                self.hour, self.minute, self.second, self.microsecond,
            });
        }
        return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{
            self.hour, self.minute, self.second,
        });
    }

    /// Parse from ISO format string "HH:MM:SS" or "HH:MM:SS.ffffff"
    pub fn parseIsoformat(s: []const u8) !Time {
        if (s.len < 8) return error.InvalidFormat;
        const hour = std.fmt.parseInt(u8, s[0..2], 10) catch return error.InvalidFormat;
        const minute = std.fmt.parseInt(u8, s[3..5], 10) catch return error.InvalidFormat;
        const second = std.fmt.parseInt(u8, s[6..8], 10) catch return error.InvalidFormat;
        var microsecond: u32 = 0;
        if (s.len > 9 and s[8] == '.') {
            const usec_str = s[9..@min(15, s.len)];
            microsecond = std.fmt.parseInt(u32, usec_str, 10) catch 0;
            // Pad to 6 digits
            var mult: u32 = 1;
            var i: usize = usec_str.len;
            while (i < 6) : (i += 1) mult *= 10;
            microsecond *= mult;
        }
        return Time{ .hour = hour, .minute = minute, .second = second, .microsecond = microsecond };
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

    /// Add two timedeltas
    pub fn add(self: Timedelta, other: Timedelta) Timedelta {
        return normalize(
            self.days + other.days,
            self.seconds + other.seconds,
            self.microseconds + other.microseconds,
        );
    }

    /// Subtract two timedeltas
    pub fn sub(self: Timedelta, other: Timedelta) Timedelta {
        return normalize(
            self.days - other.days,
            self.seconds - other.seconds,
            self.microseconds - other.microseconds,
        );
    }

    /// Multiply timedelta by integer
    pub fn mul(self: Timedelta, factor: i64) Timedelta {
        return normalize(
            self.days * factor,
            self.seconds * factor,
            self.microseconds * factor,
        );
    }

    /// Divide timedelta by integer (floor division)
    pub fn div(self: Timedelta, divisor: i64) Timedelta {
        const total_us = self.days * 86400 * 1_000_000 + self.seconds * 1_000_000 + self.microseconds;
        const result_us = @divFloor(total_us, divisor);
        return fromMicroseconds(result_us);
    }

    /// Negate timedelta
    pub fn neg(self: Timedelta) Timedelta {
        return Timedelta{
            .days = -self.days,
            .seconds = -self.seconds,
            .microseconds = -self.microseconds,
        };
    }

    /// Absolute value of timedelta
    pub fn abs(self: Timedelta) Timedelta {
        if (self.days < 0 or (self.days == 0 and self.seconds < 0) or
            (self.days == 0 and self.seconds == 0 and self.microseconds < 0))
        {
            return self.neg();
        }
        return self;
    }

    /// Create from total microseconds
    pub fn fromMicroseconds(us: i64) Timedelta {
        var remaining = us;
        const days = @divFloor(remaining, 86400 * 1_000_000);
        remaining = @mod(remaining, 86400 * 1_000_000);
        const seconds = @divFloor(remaining, 1_000_000);
        remaining = @mod(remaining, 1_000_000);
        return Timedelta{
            .days = days,
            .seconds = seconds,
            .microseconds = remaining,
        };
    }

    /// Normalize days/seconds/microseconds to standard ranges
    fn normalize(days: i64, seconds: i64, microseconds: i64) Timedelta {
        var d = days;
        var s = seconds;
        var us = microseconds;

        // Normalize microseconds (0 <= us < 1_000_000)
        if (us >= 1_000_000 or us < 0) {
            const extra_s = @divFloor(us, 1_000_000);
            s += extra_s;
            us = @mod(us, 1_000_000);
        }

        // Normalize seconds (0 <= s < 86400)
        if (s >= 86400 or s < 0) {
            const extra_d = @divFloor(s, 86400);
            d += extra_d;
            s = @mod(s, 86400);
        }

        return Timedelta{
            .days = d,
            .seconds = s,
            .microseconds = us,
        };
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

/// datetime.date(year, month, day) - returns Date struct
pub fn date(year: i64, month: i64, day: i64) Date {
    return Date{
        .year = @intCast(year),
        .month = @intCast(month),
        .day = @intCast(day),
    };
}

/// datetime.time(hour, minute, second, microsecond=0) - returns Time struct
pub fn time(hour: i64, minute: i64, second: i64) Time {
    return Time{
        .hour = @intCast(hour),
        .minute = @intCast(minute),
        .second = @intCast(second),
        .microsecond = 0,
    };
}

/// datetime.time with microseconds
pub fn timeFull(hour: i64, minute: i64, second: i64, microsecond: i64) Time {
    return Time{
        .hour = @intCast(hour),
        .minute = @intCast(minute),
        .second = @intCast(second),
        .microsecond = @intCast(microsecond),
    };
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
// Helper functions
// =============================================================================

/// Calculate days since Unix epoch (1970-01-01) from year, month, day
/// Note: Must be `pub` so struct methods can call it via @This() pattern
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

/// strftime - format datetime according to format string
/// Supports: %Y, %m, %d, %H, %M, %S, %f (microseconds), %A, %a, %B, %b, %j, %U, %W, %w, %y, %p, %I, %%
pub fn strftime(allocator: std.mem.Allocator, dt: Datetime, format: []const u8) ![]const u8 {
    const weekdays_full = [_][]const u8{ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
    const weekdays_abbr = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    const months_full = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const months_abbr = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    var result = std.ArrayList(u8){};

    var i: usize = 0;
    while (i < format.len) {
        if (format[i] == '%' and i + 1 < format.len) {
            const spec = format[i + 1];
            switch (spec) {
                'Y' => try result.writer(allocator).print("{d:0>4}", .{dt.year}),
                'y' => try result.writer(allocator).print("{d:0>2}", .{@mod(dt.year, 100)}),
                'm' => try result.writer(allocator).print("{d:0>2}", .{dt.month}),
                'd' => try result.writer(allocator).print("{d:0>2}", .{dt.day}),
                'H' => try result.writer(allocator).print("{d:0>2}", .{dt.hour}),
                'I' => try result.writer(allocator).print("{d:0>2}", .{if (dt.hour == 0) 12 else if (dt.hour > 12) dt.hour - 12 else dt.hour}),
                'M' => try result.writer(allocator).print("{d:0>2}", .{dt.minute}),
                'S' => try result.writer(allocator).print("{d:0>2}", .{dt.second}),
                'f' => try result.writer(allocator).print("{d:0>6}", .{dt.microsecond}),
                'p' => try result.appendSlice(allocator, if (dt.hour < 12) "AM" else "PM"),
                'A' => try result.appendSlice(allocator, weekdays_full[@intCast(dt.weekday())]),
                'a' => try result.appendSlice(allocator, weekdays_abbr[@intCast(dt.weekday())]),
                'B' => try result.appendSlice(allocator, months_full[@intCast(dt.month - 1)]),
                'b' => try result.appendSlice(allocator, months_abbr[@intCast(dt.month - 1)]),
                'w' => try result.writer(allocator).print("{d}", .{@mod(dt.weekday() + 1, 7)}), // Sunday=0
                'j' => {
                    // Day of year
                    const days_in_months = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
                    var doy: u32 = dt.day;
                    var m: u8 = 1;
                    while (m < dt.month) : (m += 1) {
                        doy += days_in_months[m - 1];
                        if (m == 2 and isLeapYear(dt.year)) doy += 1;
                    }
                    try result.writer(allocator).print("{d:0>3}", .{doy});
                },
                '%' => try result.append(allocator, '%'),
                else => {
                    try result.append(allocator, '%');
                    try result.append(allocator, spec);
                },
            }
            i += 2;
        } else {
            try result.append(allocator, format[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

fn isLeapYear(year: u32) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

// =============================================================================
// Timezone support (100% CPython alignment)
// =============================================================================

/// tzinfo - Abstract base class for timezone information
pub const TzInfo = struct {
    /// Offset from UTC in minutes
    offset_minutes: i32,
    /// Timezone name
    name: []const u8,

    pub fn utcoffset(self: TzInfo) Timedelta {
        const total_seconds = @as(i64, self.offset_minutes) * 60;
        return Timedelta.init(0, total_seconds, 0);
    }

    pub fn tzname(self: TzInfo) []const u8 {
        return self.name;
    }

    pub fn dst(self: TzInfo) ?Timedelta {
        _ = self;
        return null; // No DST by default
    }
};

/// timezone - Fixed offset from UTC
pub const Timezone = struct {
    offset: Timedelta,
    name: ?[]const u8,

    pub fn init(offset: Timedelta, name: ?[]const u8) Timezone {
        return .{ .offset = offset, .name = name };
    }

    pub fn initFromHours(hours: i32) Timezone {
        return .{
            .offset = Timedelta.init(0, @as(i64, hours) * 3600, 0),
            .name = null,
        };
    }

    pub fn initFromMinutes(minutes: i32) Timezone {
        return .{
            .offset = Timedelta.init(0, @as(i64, minutes) * 60, 0),
            .name = null,
        };
    }

    pub fn utcoffset(self: Timezone, dt: Datetime) Timedelta {
        _ = dt;
        return self.offset;
    }

    pub fn tzname(self: Timezone, dt: Datetime, allocator: std.mem.Allocator) ![]const u8 {
        _ = dt;
        if (self.name) |n| return n;

        // Generate name from offset
        const total_secs = self.offset.totalSeconds();
        const hours = @divTrunc(@as(i64, @intFromFloat(total_secs)), 3600);
        const minutes = @divTrunc(@mod(@as(i64, @intFromFloat(total_secs)), 3600), 60);

        if (hours >= 0) {
            return std.fmt.allocPrint(allocator, "UTC+{d:0>2}:{d:0>2}", .{ hours, minutes });
        } else {
            return std.fmt.allocPrint(allocator, "UTC{d:0>2}:{d:0>2}", .{ hours, @abs(minutes) });
        }
    }

    pub fn dst(self: Timezone, dt: Datetime) ?Timedelta {
        _ = self;
        _ = dt;
        return null; // Fixed offset, no DST
    }
};

/// UTC timezone constant
pub const UTC = Timezone{
    .offset = Timedelta.init(0, 0, 0),
    .name = "UTC",
};

// =============================================================================
// Additional Datetime methods for CPython alignment
// =============================================================================

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

/// strptime - parse string to datetime using format
/// Supports: %Y, %m, %d, %H, %M, %S, %f
pub fn strptime(str: []const u8, format: []const u8) !Datetime {
    var year: u32 = 1900;
    var month: u8 = 1;
    var day: u8 = 1;
    var hour: u8 = 0;
    var minute: u8 = 0;
    var second: u8 = 0;
    var microsecond: u32 = 0;

    var str_idx: usize = 0;
    var fmt_idx: usize = 0;

    while (fmt_idx < format.len and str_idx < str.len) {
        if (format[fmt_idx] == '%' and fmt_idx + 1 < format.len) {
            const spec = format[fmt_idx + 1];
            switch (spec) {
                'Y' => {
                    if (str_idx + 4 > str.len) return error.InvalidFormat;
                    year = std.fmt.parseInt(u32, str[str_idx .. str_idx + 4], 10) catch return error.InvalidFormat;
                    str_idx += 4;
                },
                'y' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    const y = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    year = if (y >= 69) 1900 + @as(u32, y) else 2000 + @as(u32, y);
                    str_idx += 2;
                },
                'm' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    month = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'd' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    day = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'H' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    hour = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'I' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    hour = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'M' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    minute = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'S' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    second = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'f' => {
                    // Microseconds - up to 6 digits
                    var end = str_idx;
                    while (end < str.len and end < str_idx + 6 and std.ascii.isDigit(str[end])) : (end += 1) {}
                    const usec_str = str[str_idx..end];
                    microsecond = std.fmt.parseInt(u32, usec_str, 10) catch 0;
                    // Pad to 6 digits
                    var mult: u32 = 1;
                    var i: usize = usec_str.len;
                    while (i < 6) : (i += 1) mult *= 10;
                    microsecond *= mult;
                    str_idx = end;
                },
                'p' => {
                    // AM/PM
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    const ampm = str[str_idx .. str_idx + 2];
                    if (std.mem.eql(u8, ampm, "PM") or std.mem.eql(u8, ampm, "pm")) {
                        if (hour != 12) hour += 12;
                    } else if (std.mem.eql(u8, ampm, "AM") or std.mem.eql(u8, ampm, "am")) {
                        if (hour == 12) hour = 0;
                    }
                    str_idx += 2;
                },
                '%' => {
                    if (str[str_idx] != '%') return error.InvalidFormat;
                    str_idx += 1;
                },
                else => {
                    // Unknown format code - skip
                    str_idx += 1;
                },
            }
            fmt_idx += 2;
        } else {
            // Literal character must match
            if (str[str_idx] != format[fmt_idx]) return error.InvalidFormat;
            str_idx += 1;
            fmt_idx += 1;
        }
    }

    return Datetime{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
        .microsecond = microsecond,
    };
}

// =============================================================================
// Additional methods on Datetime struct
// =============================================================================

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
        const dt = Datetime{
            .year = d.year,
            .month = d.month,
            .day = d.day,
            .hour = 0,
            .minute = 0,
            .second = 0,
            .microsecond = 0,
        };
        return DatetimeExt.isocalendar(dt);
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

/// Extend Time with additional CPython-compatible methods
pub const TimeExt = struct {
    /// replace(hour, minute, second, microsecond) - return time with some fields replaced
    pub fn replace(t: Time, hour: ?u8, minute: ?u8, second: ?u8, microsecond: ?u32) Time {
        return Time{
            .hour = hour orelse t.hour,
            .minute = minute orelse t.minute,
            .second = second orelse t.second,
            .microsecond = microsecond orelse t.microsecond,
        };
    }

    /// isoformat() - return ISO format string
    pub fn isoformat(t: Time, allocator: std.mem.Allocator) ![]const u8 {
        return t.toString(allocator);
    }
};

// =============================================================================
// Datetime class attributes (min, max, resolution)
// =============================================================================

pub const MINYEAR: i64 = 1;
pub const MAXYEAR: i64 = 9999;

pub const datetime_min = Datetime{ .year = 1, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 };
pub const datetime_max = Datetime{ .year = 9999, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 59, .microsecond = 999999 };
pub const datetime_resolution = Timedelta.init(0, 0, 1);

pub const date_min = Date{ .year = 1, .month = 1, .day = 1 };
pub const date_max = Date{ .year = 9999, .month = 12, .day = 31 };
pub const date_resolution = Timedelta.fromDays(1);

pub const time_min = Time{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0 };
pub const time_max = Time{ .hour = 23, .minute = 59, .second = 59, .microsecond = 999999 };
pub const time_resolution = Timedelta.init(0, 0, 1);

pub const timedelta_min = Timedelta.init(-999999999, 0, 0);
pub const timedelta_max = Timedelta.init(999999999, 86399, 999999);
pub const timedelta_resolution = Timedelta.init(0, 0, 1);

// =============================================================================
// fromisocalendar - Create date/datetime from ISO year, week, day
// =============================================================================

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

/// datetime.fromisocalendar(year, week, day) -> datetime
/// Create a datetime from an ISO calendar date with time at midnight
pub fn datetimeFromIsocalendar(year: i64, week: i64, day: i64) !Datetime {
    const d = try dateFromIsocalendar(year, week, day);
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
// astimezone - Convert datetime to another timezone
// =============================================================================

/// datetime.astimezone(tz) -> datetime
/// Convert a datetime to a new timezone
/// This is a simplified implementation that assumes the input datetime is in UTC
/// when it has no timezone info, or uses the provided offset.
pub fn astimezone(dt: Datetime, tz: Timezone) Datetime {
    // Get the offset in seconds
    const offset = tz.utcoffset(dt);
    const offset_secs = offset.totalSeconds();

    // Convert current datetime to timestamp (assuming UTC)
    const ts = dt.toTimestamp();

    // Apply the timezone offset
    const new_ts: i64 = @intFromFloat(ts + offset_secs);

    // Convert back to datetime
    return Datetime.fromTimestamp(new_ts);
}

/// Create a timezone-aware datetime by attaching a timezone
pub const DatetimeWithTz = struct {
    datetime: Datetime,
    tzinfo: ?Timezone,

    pub fn init(dt: Datetime, tz: ?Timezone) DatetimeWithTz {
        return .{ .datetime = dt, .tzinfo = tz };
    }

    /// astimezone - Convert to another timezone
    pub fn astimezone_tz(self: DatetimeWithTz, target_tz: Timezone) DatetimeWithTz {
        if (self.tzinfo) |src_tz| {
            // Convert from source timezone to target timezone
            // First convert to UTC, then to target
            const src_offset = src_tz.offset.totalSeconds();
            const ts = self.datetime.toTimestamp() - src_offset;
            const target_offset = target_tz.offset.totalSeconds();
            const new_ts: i64 = @intFromFloat(ts + target_offset);
            return .{
                .datetime = Datetime.fromTimestamp(new_ts),
                .tzinfo = target_tz,
            };
        } else {
            // Assume local time, just apply target timezone
            return .{
                .datetime = astimezone(self.datetime, target_tz),
                .tzinfo = target_tz,
            };
        }
    }

    /// utcoffset() - Return UTC offset
    pub fn utcoffset(self: DatetimeWithTz) ?Timedelta {
        if (self.tzinfo) |tz| {
            return tz.offset;
        }
        return null;
    }

    /// tzname() - Return timezone name
    pub fn tzname(self: DatetimeWithTz, allocator: std.mem.Allocator) !?[]const u8 {
        if (self.tzinfo) |tz| {
            return try tz.tzname(self.datetime, allocator);
        }
        return null;
    }

    /// dst() - Return DST offset (always null for fixed offset timezones)
    pub fn dst(self: DatetimeWithTz) ?Timedelta {
        if (self.tzinfo) |tz| {
            return tz.dst(self.datetime);
        }
        return null;
    }

    /// isoformat() - Return ISO format string with timezone
    pub fn isoformat(self: DatetimeWithTz, allocator: std.mem.Allocator) ![]const u8 {
        const base = try self.datetime.toIsoformat(allocator);
        if (self.tzinfo) |tz| {
            const total_secs = tz.offset.totalSeconds();
            const hours = @divTrunc(@as(i64, @intFromFloat(total_secs)), 3600);
            const minutes = @abs(@divTrunc(@mod(@as(i64, @intFromFloat(total_secs)), 3600), 60));

            if (hours >= 0) {
                return std.fmt.allocPrint(allocator, "{s}+{d:0>2}:{d:0>2}", .{ base, hours, minutes });
            } else {
                return std.fmt.allocPrint(allocator, "{s}-{d:0>2}:{d:0>2}", .{ base, @abs(hours), minutes });
            }
        }
        return base;
    }
};

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
        .microsecond = 123456,
    };
    const str = try dt.toString(allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("2025-11-25 14:30:45.123456", str);
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
