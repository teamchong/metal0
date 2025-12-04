/// DateTime module - Python datetime.datetime, datetime.date, datetime.timedelta support
const std = @import("std");
const runtime = @import("runtime.zig");
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
