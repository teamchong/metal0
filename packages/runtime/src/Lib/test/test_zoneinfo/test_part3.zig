//! test.test_zoneinfo.test_part3 - Aware datetime with timezone support
//!
//! This module provides timezone-aware datetime functionality:
//! - AwareDatetime struct with timezone attachment
//! - replace() for modifying datetime components
//! - Arithmetic operations (add/subtract timedelta)
//! - Comparison between aware datetimes

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Time components for a datetime
pub const TimeComponents = struct {
    hour: u8 = 0,
    minute: u8 = 0,
    second: u8 = 0,
    microsecond: u32 = 0,

    /// Validate time components
    pub fn isValid(self: TimeComponents) bool {
        return self.hour < 24 and
            self.minute < 60 and
            self.second < 60 and
            self.microsecond < 1_000_000;
    }

    /// Total seconds since midnight
    pub fn totalSeconds(self: TimeComponents) u32 {
        return @as(u32, self.hour) * 3600 +
            @as(u32, self.minute) * 60 +
            @as(u32, self.second);
    }

    /// Create from total seconds
    pub fn fromTotalSeconds(total: u32, microsecond: u32) TimeComponents {
        return .{
            .hour = @intCast(total / 3600),
            .minute = @intCast((total % 3600) / 60),
            .second = @intCast(total % 60),
            .microsecond = microsecond,
        };
    }

    /// Format as HH:MM:SS
    pub fn format(self: TimeComponents, buf: []u8) []const u8 {
        const result = std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{
            self.hour,
            self.minute,
            self.second,
        }) catch return "";
        return result;
    }

    /// Format with microseconds
    pub fn formatFull(self: TimeComponents, buf: []u8) []const u8 {
        if (self.microsecond == 0) {
            return self.format(buf);
        }
        const result = std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
            self.hour,
            self.minute,
            self.second,
            self.microsecond,
        }) catch return "";
        return result;
    }
};

/// Date components for a datetime
pub const DateComponents = struct {
    year: i32,
    month: u8 = 1,
    day: u8 = 1,

    /// Validate date components
    pub fn isValid(self: DateComponents) bool {
        if (self.month < 1 or self.month > 12) return false;
        if (self.day < 1) return false;
        const max_day = daysInMonth(self.year, self.month);
        return self.day <= max_day;
    }

    /// Convert to ordinal day number
    pub fn toOrdinal(self: DateComponents) i64 {
        var days: i64 = 0;

        if (self.year >= 1) {
            const y = self.year - 1;
            days = @as(i64, y) * 365 + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400);
        } else {
            const y = -self.year;
            days = -(@as(i64, y) * 365 + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400)) - 366;
        }

        var m: u8 = 1;
        while (m < self.month) : (m += 1) {
            days += daysInMonth(self.year, m);
        }

        days += self.day;

        return days;
    }

    /// Create from ordinal day number
    pub fn fromOrdinal(ordinal: i64) DateComponents {
        var year: i32 = @intCast(@divFloor(ordinal * 400, 146097));
        var remaining = ordinal;

        while (true) {
            const year_start = DateComponents{ .year = year, .month = 1, .day = 1 };
            const ord = year_start.toOrdinal();
            if (ord <= ordinal) {
                remaining = ordinal - ord + 1;
                const days_in_year: i64 = if (isLeapYear(year)) 366 else 365;
                if (remaining <= days_in_year) break;
                year += 1;
            } else {
                year -= 1;
            }
        }

        var month: u8 = 1;
        var day_in_year = remaining;
        while (month <= 12) {
            const dim = daysInMonth(year, month);
            if (day_in_year <= dim) break;
            day_in_year -= dim;
            month += 1;
        }

        return .{
            .year = year,
            .month = month,
            .day = @intCast(day_in_year),
        };
    }

    /// Format as YYYY-MM-DD
    pub fn format(self: DateComponents, buf: []u8) []const u8 {
        const result = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            self.year,
            self.month,
            self.day,
        }) catch return "";
        return result;
    }

    /// Day of week (0=Monday, 6=Sunday)
    pub fn weekday(self: DateComponents) u8 {
        const ord = self.toOrdinal();
        return @intCast(@mod(ord + 6, 7));
    }
};

/// Timezone info for aware datetime
pub const TimezoneInfo = struct {
    name: []const u8,
    utc_offset: i32,
    dst_offset: i32,
    abbreviation: []const u8,

    pub fn utc() TimezoneInfo {
        return .{
            .name = "UTC",
            .utc_offset = 0,
            .dst_offset = 0,
            .abbreviation = "UTC",
        };
    }

    pub fn totalOffset(self: TimezoneInfo) i32 {
        return self.utc_offset + self.dst_offset;
    }

    pub fn isDst(self: TimezoneInfo) bool {
        return self.dst_offset != 0;
    }

    pub fn formatOffset(self: TimezoneInfo, buf: []u8) []const u8 {
        const total = self.totalOffset();
        const sign: u8 = if (total >= 0) '+' else '-';
        const abs_offset: u32 = if (total >= 0) @intCast(total) else @intCast(-total);
        const hours = abs_offset / 3600;
        const minutes = (abs_offset % 3600) / 60;

        const result = std.fmt.bufPrint(buf, "{c}{d:0>2}:{d:0>2}", .{
            sign,
            hours,
            minutes,
        }) catch return "";
        return result;
    }
};

/// Timedelta for datetime arithmetic
pub const Timedelta = struct {
    days: i64 = 0,
    seconds: i32 = 0,
    microseconds: i32 = 0,

    pub fn fromSeconds(total_seconds: i64) Timedelta {
        const days = @divFloor(total_seconds, 86400);
        const secs: i32 = @intCast(@mod(total_seconds, 86400));
        return .{ .days = days, .seconds = secs };
    }

    pub fn fromHMS(hours: i64, minutes: i64, seconds: i64) Timedelta {
        const total = hours * 3600 + minutes * 60 + seconds;
        return fromSeconds(total);
    }

    pub fn totalSeconds(self: Timedelta) i64 {
        return self.days * 86400 + self.seconds;
    }

    pub fn totalMicroseconds(self: Timedelta) i128 {
        return @as(i128, self.totalSeconds()) * 1_000_000 + self.microseconds;
    }

    pub fn negate(self: Timedelta) Timedelta {
        return .{
            .days = -self.days,
            .seconds = -self.seconds,
            .microseconds = -self.microseconds,
        };
    }

    pub fn add(self: Timedelta, other: Timedelta) Timedelta {
        var total_us = self.totalMicroseconds() + other.totalMicroseconds();
        const us: i32 = @intCast(@mod(total_us, 1_000_000));
        total_us = @divFloor(total_us, 1_000_000);
        const secs: i32 = @intCast(@mod(total_us, 86400));
        const days: i64 = @intCast(@divFloor(total_us, 86400));
        return .{ .days = days, .seconds = secs, .microseconds = us };
    }

    pub fn sub(self: Timedelta, other: Timedelta) Timedelta {
        return self.add(other.negate());
    }
};

/// Timezone-aware datetime
pub const AwareDatetime = struct {
    date: DateComponents,
    time: TimeComponents,
    tzinfo: TimezoneInfo,
    fold: u1 = 0,

    pub fn create(
        year: i32,
        month: u8,
        day: u8,
        hour: u8,
        minute: u8,
        second: u8,
        microsecond: u32,
        tzinfo: TimezoneInfo,
    ) AwareDatetime {
        return .{
            .date = .{ .year = year, .month = month, .day = day },
            .time = .{ .hour = hour, .minute = minute, .second = second, .microsecond = microsecond },
            .tzinfo = tzinfo,
        };
    }

    pub fn fromTimestamp(timestamp: i64, tzinfo: TimezoneInfo) AwareDatetime {
        const local_ts = timestamp + tzinfo.totalOffset();
        const days = @divFloor(local_ts, 86400);
        const day_seconds: u32 = @intCast(@mod(local_ts, 86400));
        const epoch_ordinal: i64 = 719163;
        const date = DateComponents.fromOrdinal(epoch_ordinal + days);
        const time = TimeComponents.fromTotalSeconds(day_seconds, 0);

        return .{ .date = date, .time = time, .tzinfo = tzinfo };
    }

    pub fn toTimestamp(self: AwareDatetime) i64 {
        const epoch_ordinal: i64 = 719163;
        const days = self.date.toOrdinal() - epoch_ordinal;
        const local_ts = days * 86400 + self.time.totalSeconds();
        return local_ts - self.tzinfo.totalOffset();
    }

    pub fn replace(
        self: AwareDatetime,
        year: ?i32,
        month: ?u8,
        day: ?u8,
        hour: ?u8,
        minute: ?u8,
        second: ?u8,
        microsecond: ?u32,
        tzinfo: ?TimezoneInfo,
        fold: ?u1,
    ) AwareDatetime {
        return .{
            .date = .{
                .year = year orelse self.date.year,
                .month = month orelse self.date.month,
                .day = day orelse self.date.day,
            },
            .time = .{
                .hour = hour orelse self.time.hour,
                .minute = minute orelse self.time.minute,
                .second = second orelse self.time.second,
                .microsecond = microsecond orelse self.time.microsecond,
            },
            .tzinfo = tzinfo orelse self.tzinfo,
            .fold = fold orelse self.fold,
        };
    }

    pub fn addTimedelta(self: AwareDatetime, delta: Timedelta) AwareDatetime {
        const ts = self.toTimestamp();
        const new_ts = ts + delta.totalSeconds();
        var result = fromTimestamp(new_ts, self.tzinfo);
        var us = @as(i64, self.time.microsecond) + delta.microseconds;
        if (us < 0) {
            us += 1_000_000;
        } else if (us >= 1_000_000) {
            us -= 1_000_000;
        }
        result.time.microsecond = @intCast(us);
        return result;
    }

    pub fn subTimedelta(self: AwareDatetime, delta: Timedelta) AwareDatetime {
        return self.addTimedelta(delta.negate());
    }

    pub fn diff(self: AwareDatetime, other: AwareDatetime) Timedelta {
        const ts1 = self.toTimestamp();
        const ts2 = other.toTimestamp();
        var delta = Timedelta.fromSeconds(ts1 - ts2);
        delta.microseconds = @as(i32, @intCast(self.time.microsecond)) -
            @as(i32, @intCast(other.time.microsecond));
        return delta;
    }

    pub fn compare(self: AwareDatetime, other: AwareDatetime) std.math.Order {
        const ts1 = self.toTimestamp();
        const ts2 = other.toTimestamp();
        if (ts1 != ts2) return std.math.order(ts1, ts2);
        return std.math.order(self.time.microsecond, other.time.microsecond);
    }

    pub fn astimezone(self: AwareDatetime, new_tzinfo: TimezoneInfo) AwareDatetime {
        const ts = self.toTimestamp();
        return fromTimestamp(ts, new_tzinfo);
    }

    pub fn utcoffset(self: AwareDatetime) Timedelta {
        return Timedelta.fromSeconds(self.tzinfo.totalOffset());
    }

    pub fn dst(self: AwareDatetime) Timedelta {
        return Timedelta.fromSeconds(self.tzinfo.dst_offset);
    }

    pub fn tzname(self: AwareDatetime) []const u8 {
        return self.tzinfo.abbreviation;
    }

    pub fn isValid(self: AwareDatetime) bool {
        return self.date.isValid() and self.time.isValid();
    }

    pub fn formatISO(self: AwareDatetime, buf: []u8) []const u8 {
        var date_buf: [16]u8 = undefined;
        var time_buf: [16]u8 = undefined;
        var tz_buf: [8]u8 = undefined;

        const date_str = self.date.format(&date_buf);
        const time_str = self.time.format(&time_buf);
        const tz_str = self.tzinfo.formatOffset(&tz_buf);

        const result = std.fmt.bufPrint(buf, "{s}T{s}{s}", .{
            date_str,
            time_str,
            tz_str,
        }) catch return "";
        return result;
    }
};

fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;
    return false;
}

fn daysInMonth(year: i32, month: u8) u8 {
    const days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 and isLeapYear(year)) return 29;
    return days[month - 1];
}

// ============================================================================
// Tests
// ============================================================================

test "time_components_is_valid" {
    const valid = TimeComponents{ .hour = 12, .minute = 30, .second = 45, .microsecond = 500000 };
    try testing.expect(valid.isValid());

    const invalid_hour = TimeComponents{ .hour = 24, .minute = 0, .second = 0, .microsecond = 0 };
    try testing.expect(!invalid_hour.isValid());
}

test "time_components_total_seconds" {
    const time = TimeComponents{ .hour = 14, .minute = 30, .second = 45, .microsecond = 0 };
    try testing.expectEqual(@as(u32, 14 * 3600 + 30 * 60 + 45), time.totalSeconds());
}

test "time_components_from_total_seconds" {
    const time = TimeComponents.fromTotalSeconds(52245, 123456);
    try testing.expectEqual(@as(u8, 14), time.hour);
    try testing.expectEqual(@as(u8, 30), time.minute);
    try testing.expectEqual(@as(u8, 45), time.second);
}

test "time_components_format" {
    const time = TimeComponents{ .hour = 9, .minute = 5, .second = 3, .microsecond = 0 };
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("09:05:03", time.format(&buf));
}

test "date_components_is_valid" {
    const valid = DateComponents{ .year = 2023, .month = 7, .day = 15 };
    try testing.expect(valid.isValid());

    const invalid_month = DateComponents{ .year = 2023, .month = 13, .day = 1 };
    try testing.expect(!invalid_month.isValid());
}

test "date_components_to_ordinal" {
    const date1 = DateComponents{ .year = 1, .month = 1, .day = 1 };
    try testing.expectEqual(@as(i64, 1), date1.toOrdinal());

    const date2 = DateComponents{ .year = 1970, .month = 1, .day = 1 };
    try testing.expectEqual(@as(i64, 719163), date2.toOrdinal());
}

test "date_components_from_ordinal" {
    const date = DateComponents.fromOrdinal(719163);
    try testing.expectEqual(@as(i32, 1970), date.year);
    try testing.expectEqual(@as(u8, 1), date.month);
    try testing.expectEqual(@as(u8, 1), date.day);
}

test "timezone_info_utc" {
    const tz = TimezoneInfo.utc();
    try testing.expectEqualStrings("UTC", tz.name);
    try testing.expectEqual(@as(i32, 0), tz.totalOffset());
}

test "timezone_info_total_offset" {
    const tz = TimezoneInfo{
        .name = "America/New_York",
        .utc_offset = -18000,
        .dst_offset = 3600,
        .abbreviation = "EDT",
    };
    try testing.expectEqual(@as(i32, -14400), tz.totalOffset());
}

test "timedelta_from_seconds" {
    const td = Timedelta.fromSeconds(90061);
    try testing.expectEqual(@as(i64, 1), td.days);
    try testing.expectEqual(@as(i32, 3661), td.seconds);
}

test "timedelta_total_seconds" {
    const td = Timedelta{ .days = 2, .seconds = 3600, .microseconds = 0 };
    try testing.expectEqual(@as(i64, 2 * 86400 + 3600), td.totalSeconds());
}

test "aware_datetime_create" {
    const tz = TimezoneInfo.utc();
    const dt = AwareDatetime.create(2023, 7, 15, 14, 30, 45, 123456, tz);
    try testing.expectEqual(@as(i32, 2023), dt.date.year);
    try testing.expectEqual(@as(u8, 7), dt.date.month);
}

test "aware_datetime_from_timestamp_utc" {
    const tz = TimezoneInfo.utc();
    const dt = AwareDatetime.fromTimestamp(1689430245, tz);
    try testing.expectEqual(@as(i32, 2023), dt.date.year);
}

test "aware_datetime_to_timestamp" {
    const tz = TimezoneInfo.utc();
    const dt = AwareDatetime.create(1970, 1, 1, 0, 0, 0, 0, tz);
    try testing.expectEqual(@as(i64, 0), dt.toTimestamp());
}

test "aware_datetime_replace" {
    const tz = TimezoneInfo.utc();
    const dt = AwareDatetime.create(2023, 7, 15, 14, 30, 45, 0, tz);
    const replaced = dt.replace(2024, null, null, 10, null, null, null, null, null);
    try testing.expectEqual(@as(i32, 2024), replaced.date.year);
    try testing.expectEqual(@as(u8, 10), replaced.time.hour);
}

test "aware_datetime_add_timedelta" {
    const tz = TimezoneInfo.utc();
    const dt = AwareDatetime.create(2023, 7, 15, 14, 30, 45, 0, tz);
    const delta = Timedelta{ .days = 1, .seconds = 3600, .microseconds = 0 };
    const result = dt.addTimedelta(delta);
    try testing.expectEqual(@as(u8, 16), result.date.day);
}

test "aware_datetime_compare" {
    const tz = TimezoneInfo.utc();
    const dt1 = AwareDatetime.create(2023, 7, 15, 14, 30, 45, 0, tz);
    const dt2 = AwareDatetime.create(2023, 7, 15, 14, 30, 46, 0, tz);
    try testing.expectEqual(std.math.Order.lt, dt1.compare(dt2));
}

test "aware_datetime_astimezone" {
    const utc = TimezoneInfo.utc();
    const jst = TimezoneInfo{
        .name = "Asia/Tokyo",
        .utc_offset = 32400,
        .dst_offset = 0,
        .abbreviation = "JST",
    };
    const dt_utc = AwareDatetime.create(2023, 7, 15, 0, 0, 0, 0, utc);
    const dt_jst = dt_utc.astimezone(jst);
    try testing.expectEqual(@as(u8, 9), dt_jst.time.hour);
}

test "aware_datetime_format_iso" {
    const tz = TimezoneInfo.utc();
    const dt = AwareDatetime.create(2023, 7, 15, 14, 30, 45, 0, tz);
    var buf: [32]u8 = undefined;
    const formatted = dt.formatISO(&buf);
    try testing.expectEqualStrings("2023-07-15T14:30:45+00:00", formatted);
}
