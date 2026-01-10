//! test.test_zoneinfo.test_part5 - fromutc() conversion
//!
//! This module handles conversion from UTC to local time:
//! - fromutc() implementation for timezone objects
//! - Handling of DST transitions during conversion
//! - Edge cases around transition boundaries

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// UTC to local time converter
pub const FromUTCConverter = struct {
    /// UTC offset in seconds
    base_offset: i32,
    /// DST offset in seconds (added to base when in DST)
    dst_offset: i32,
    /// Transitions (UTC timestamps)
    transitions: []const i64,
    /// Is DST active after each transition?
    is_dst_after: []const bool,

    /// Convert UTC timestamp to local
    pub fn convert(self: FromUTCConverter, utc_timestamp: i64) LocalTimeResult {
        const dst_active = self.isDstAt(utc_timestamp);
        const total_offset = if (dst_active)
            self.base_offset + self.dst_offset
        else
            self.base_offset;

        return LocalTimeResult{
            .local_timestamp = utc_timestamp + total_offset,
            .utc_offset = total_offset,
            .is_dst = dst_active,
            .fold = self.calculateFold(utc_timestamp),
        };
    }

    /// Check if DST is active at UTC timestamp
    pub fn isDstAt(self: FromUTCConverter, utc_timestamp: i64) bool {
        if (self.transitions.len == 0) return false;

        var idx: usize = 0;
        for (self.transitions, 0..) |trans_time, i| {
            if (utc_timestamp >= trans_time) {
                idx = i;
            } else {
                break;
            }
        }

        if (idx < self.is_dst_after.len) {
            return self.is_dst_after[idx];
        }
        return false;
    }

    /// Calculate fold value (0 or 1 for ambiguous times)
    fn calculateFold(self: FromUTCConverter, utc_timestamp: i64) u1 {
        // Find if we're in a fall-back transition
        for (self.transitions, 0..) |trans_time, i| {
            if (i >= self.is_dst_after.len) break;

            // Check if this is a fall-back (DST -> STD)
            const was_dst = if (i == 0) false else self.is_dst_after[i - 1];
            const is_dst = self.is_dst_after[i];

            if (was_dst and !is_dst) {
                // Fall-back transition
                const dst_total = self.base_offset + self.dst_offset;
                const std_total = self.base_offset;

                // Period after fall-back where times repeat
                const repeat_start = trans_time + std_total;
                const repeat_end = trans_time + dst_total;

                const local_time = utc_timestamp + std_total;
                if (local_time >= repeat_start and local_time < repeat_end) {
                    // In the repeated hour, this is the second occurrence (fold=1)
                    return 1;
                }
            }
        }
        return 0;
    }

    /// Get the offset at a specific UTC time
    pub fn offsetAt(self: FromUTCConverter, utc_timestamp: i64) i32 {
        const dst_active = self.isDstAt(utc_timestamp);
        return if (dst_active)
            self.base_offset + self.dst_offset
        else
            self.base_offset;
    }
};

/// Result of UTC to local conversion
pub const LocalTimeResult = struct {
    /// Local timestamp
    local_timestamp: i64,
    /// Total UTC offset used
    utc_offset: i32,
    /// Whether DST is active
    is_dst: bool,
    /// Fold value for ambiguous times
    fold: u1,

    /// Format the local time offset
    pub fn formatOffset(self: LocalTimeResult, buf: []u8) []const u8 {
        const sign: u8 = if (self.utc_offset >= 0) '+' else '-';
        const abs: u32 = if (self.utc_offset >= 0)
            @intCast(self.utc_offset)
        else
            @intCast(-self.utc_offset);
        const hours = abs / 3600;
        const mins = (abs % 3600) / 60;

        return std.fmt.bufPrint(buf, "{c}{d:0>2}:{d:0>2}", .{
            sign,
            hours,
            mins,
        }) catch "";
    }
};

/// Simple datetime structure for fromutc operations
pub const UTCDatetime = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,

    /// Convert to Unix timestamp (assuming UTC)
    pub fn toTimestamp(self: UTCDatetime) i64 {
        const epoch_ordinal: i64 = 719163;
        const ordinal = self.dateToOrdinal();
        const days = ordinal - epoch_ordinal;
        return days * 86400 +
            @as(i64, self.hour) * 3600 +
            @as(i64, self.minute) * 60 +
            @as(i64, self.second);
    }

    /// Convert date components to ordinal
    fn dateToOrdinal(self: UTCDatetime) i64 {
        var days: i64 = 0;
        if (self.year >= 1) {
            const y = self.year - 1;
            days = @as(i64, y) * 365 + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400);
        }

        const month_days = [_]u8{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var m: u8 = 1;
        while (m < self.month) : (m += 1) {
            days += month_days[m];
            if (m == 2 and isLeapYear(self.year)) {
                days += 1;
            }
        }

        days += self.day;
        return days;
    }

    /// Create from Unix timestamp
    pub fn fromTimestamp(ts: i64) UTCDatetime {
        const epoch_ordinal: i64 = 719163;
        const days = @divFloor(ts, 86400);
        const day_secs: u32 = @intCast(@mod(ts, 86400));

        const ordinal = epoch_ordinal + days;
        const date = ordinalToDate(ordinal);

        return .{
            .year = date.year,
            .month = date.month,
            .day = date.day,
            .hour = @intCast(day_secs / 3600),
            .minute = @intCast((day_secs % 3600) / 60),
            .second = @intCast(day_secs % 60),
        };
    }

    const DateParts = struct { year: i32, month: u8, day: u8 };

    fn ordinalToDate(ordinal: i64) DateParts {
        var year: i32 = @intCast(@divFloor(ordinal * 400, 146097));
        var remaining = ordinal;

        while (true) {
            var start_days: i64 = 0;
            if (year >= 1) {
                const y = year - 1;
                start_days = @as(i64, y) * 365 + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) + 1;
            }

            if (start_days <= ordinal) {
                remaining = ordinal - start_days + 1;
                const year_len: i64 = if (isLeapYear(year)) 366 else 365;
                if (remaining <= year_len) break;
                year += 1;
            } else {
                year -= 1;
            }
        }

        const month_days = [_]u8{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var month: u8 = 1;
        var day_in_year = remaining;

        while (month <= 12) {
            var mlen: u8 = month_days[month];
            if (month == 2 and isLeapYear(year)) mlen = 29;
            if (day_in_year <= mlen) break;
            day_in_year -= mlen;
            month += 1;
        }

        return .{
            .year = year,
            .month = month,
            .day = @intCast(day_in_year),
        };
    }
};

/// fromutc implementation that returns a new datetime
pub const FromUTC = struct {
    /// Convert a UTC datetime to local datetime
    pub fn convert(
        utc_dt: UTCDatetime,
        converter: FromUTCConverter,
    ) LocalDatetimeResult {
        const utc_ts = utc_dt.toTimestamp();
        const result = converter.convert(utc_ts);
        const local_dt = UTCDatetime.fromTimestamp(result.local_timestamp);

        return .{
            .datetime = local_dt,
            .utc_offset = result.utc_offset,
            .is_dst = result.is_dst,
            .fold = result.fold,
        };
    }
};

/// Result of fromutc conversion with datetime
pub const LocalDatetimeResult = struct {
    datetime: UTCDatetime,
    utc_offset: i32,
    is_dst: bool,
    fold: u1,
};

/// Timezone-aware fromutc wrapper
pub const TimezoneFromUTC = struct {
    name: []const u8,
    converter: FromUTCConverter,

    /// Create for a fixed-offset timezone
    pub fn fixedOffset(name: []const u8, offset: i32) TimezoneFromUTC {
        return .{
            .name = name,
            .converter = .{
                .base_offset = offset,
                .dst_offset = 0,
                .transitions = &[_]i64{},
                .is_dst_after = &[_]bool{},
            },
        };
    }

    /// Convert UTC to local
    pub fn fromutc(self: TimezoneFromUTC, utc_dt: UTCDatetime) LocalDatetimeResult {
        return FromUTC.convert(utc_dt, self.converter);
    }

    /// Get timezone name
    pub fn tzname(self: TimezoneFromUTC) []const u8 {
        return self.name;
    }
};

// Helper

fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "from_utc_converter_no_transitions" {
    const converter = FromUTCConverter{
        .base_offset = -18000, // EST
        .dst_offset = 3600,
        .transitions = &[_]i64{},
        .is_dst_after = &[_]bool{},
    };

    const result = converter.convert(0);
    try testing.expectEqual(@as(i64, -18000), result.local_timestamp);
    try testing.expectEqual(@as(i32, -18000), result.utc_offset);
    try testing.expect(!result.is_dst);
}

test "from_utc_converter_with_dst" {
    // Simplified: DST starts at timestamp 1000, ends at 2000
    const transitions = [_]i64{ 1000, 2000 };
    const is_dst = [_]bool{ true, false };

    const converter = FromUTCConverter{
        .base_offset = -18000,
        .dst_offset = 3600,
        .transitions = &transitions,
        .is_dst_after = &is_dst,
    };

    // Before DST
    const before = converter.convert(500);
    try testing.expect(!before.is_dst);
    try testing.expectEqual(@as(i32, -18000), before.utc_offset);

    // During DST
    const during = converter.convert(1500);
    try testing.expect(during.is_dst);
    try testing.expectEqual(@as(i32, -14400), during.utc_offset);

    // After DST
    const after = converter.convert(2500);
    try testing.expect(!after.is_dst);
    try testing.expectEqual(@as(i32, -18000), after.utc_offset);
}

test "from_utc_converter_is_dst_at" {
    const transitions = [_]i64{ 1000, 2000 };
    const is_dst = [_]bool{ true, false };

    const converter = FromUTCConverter{
        .base_offset = 0,
        .dst_offset = 3600,
        .transitions = &transitions,
        .is_dst_after = &is_dst,
    };

    try testing.expect(!converter.isDstAt(500));
    try testing.expect(converter.isDstAt(1000));
    try testing.expect(converter.isDstAt(1500));
    try testing.expect(!converter.isDstAt(2000));
    try testing.expect(!converter.isDstAt(2500));
}

test "from_utc_converter_offset_at" {
    const transitions = [_]i64{ 1000, 2000 };
    const is_dst = [_]bool{ true, false };

    const converter = FromUTCConverter{
        .base_offset = -18000,
        .dst_offset = 3600,
        .transitions = &transitions,
        .is_dst_after = &is_dst,
    };

    try testing.expectEqual(@as(i32, -18000), converter.offsetAt(500));
    try testing.expectEqual(@as(i32, -14400), converter.offsetAt(1500));
    try testing.expectEqual(@as(i32, -18000), converter.offsetAt(2500));
}

test "local_time_result_format_offset" {
    var buf: [8]u8 = undefined;

    const positive = LocalTimeResult{
        .local_timestamp = 0,
        .utc_offset = 32400,
        .is_dst = false,
        .fold = 0,
    };
    try testing.expectEqualStrings("+09:00", positive.formatOffset(&buf));

    const negative = LocalTimeResult{
        .local_timestamp = 0,
        .utc_offset = -18000,
        .is_dst = false,
        .fold = 0,
    };
    try testing.expectEqualStrings("-05:00", negative.formatOffset(&buf));

    const utc = LocalTimeResult{
        .local_timestamp = 0,
        .utc_offset = 0,
        .is_dst = false,
        .fold = 0,
    };
    try testing.expectEqualStrings("+00:00", utc.formatOffset(&buf));
}

test "utc_datetime_to_timestamp" {
    const epoch = UTCDatetime{
        .year = 1970,
        .month = 1,
        .day = 1,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };
    try testing.expectEqual(@as(i64, 0), epoch.toTimestamp());

    const later = UTCDatetime{
        .year = 1970,
        .month = 1,
        .day = 2,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };
    try testing.expectEqual(@as(i64, 86400), later.toTimestamp());
}

test "utc_datetime_from_timestamp" {
    const dt = UTCDatetime.fromTimestamp(0);
    try testing.expectEqual(@as(i32, 1970), dt.year);
    try testing.expectEqual(@as(u8, 1), dt.month);
    try testing.expectEqual(@as(u8, 1), dt.day);
    try testing.expectEqual(@as(u8, 0), dt.hour);
}

test "utc_datetime_roundtrip" {
    const original = UTCDatetime{
        .year = 2023,
        .month = 7,
        .day = 15,
        .hour = 14,
        .minute = 30,
        .second = 45,
    };

    const ts = original.toTimestamp();
    const restored = UTCDatetime.fromTimestamp(ts);

    try testing.expectEqual(original.year, restored.year);
    try testing.expectEqual(original.month, restored.month);
    try testing.expectEqual(original.day, restored.day);
    try testing.expectEqual(original.hour, restored.hour);
    try testing.expectEqual(original.minute, restored.minute);
    try testing.expectEqual(original.second, restored.second);
}

test "from_utc_convert" {
    const converter = FromUTCConverter{
        .base_offset = 32400, // JST
        .dst_offset = 0,
        .transitions = &[_]i64{},
        .is_dst_after = &[_]bool{},
    };

    const utc_dt = UTCDatetime{
        .year = 2023,
        .month = 7,
        .day = 15,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };

    const result = FromUTC.convert(utc_dt, converter);

    try testing.expectEqual(@as(u8, 9), result.datetime.hour);
    try testing.expectEqual(@as(i32, 32400), result.utc_offset);
    try testing.expect(!result.is_dst);
}

test "timezone_from_utc_fixed_offset" {
    const tz = TimezoneFromUTC.fixedOffset("JST", 32400);
    try testing.expectEqualStrings("JST", tz.tzname());

    const utc_dt = UTCDatetime{
        .year = 2023,
        .month = 7,
        .day = 15,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };

    const result = tz.fromutc(utc_dt);
    try testing.expectEqual(@as(u8, 9), result.datetime.hour);
}

test "timezone_from_utc_negative_offset" {
    const tz = TimezoneFromUTC.fixedOffset("EST", -18000);

    const utc_dt = UTCDatetime{
        .year = 2023,
        .month = 7,
        .day = 15,
        .hour = 5,
        .minute = 0,
        .second = 0,
    };

    const result = tz.fromutc(utc_dt);
    try testing.expectEqual(@as(u8, 0), result.datetime.hour);
    try testing.expectEqual(@as(u8, 15), result.datetime.day);
}

test "from_utc_converter_fold_calculation" {
    // Test fold=1 during fall-back
    // Transition at UTC 1000, DST->STD
    const transitions = [_]i64{ 0, 1000 };
    const is_dst = [_]bool{ true, false };

    const converter = FromUTCConverter{
        .base_offset = 0,
        .dst_offset = 3600,
        .transitions = &transitions,
        .is_dst_after = &is_dst,
    };

    // Just after fall-back, in the repeated hour
    const result = converter.convert(1001);
    // Should have fold=1 since this is in the repeated hour
    try testing.expectEqual(@as(u1, 1), result.fold);
}

test "is_leap_year" {
    try testing.expect(isLeapYear(2000));
    try testing.expect(isLeapYear(2024));
    try testing.expect(!isLeapYear(1900));
    try testing.expect(!isLeapYear(2023));
}
