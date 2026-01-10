//! test.test_zoneinfo.test_part2 - TZData parsing, zone rules, and leap seconds
//!
//! This module provides TZData handling functionality:
//! - TZif file format parsing (versions 1, 2, 3)
//! - Zone rules for DST transitions
//! - Leap second handling and correction
//! - POSIX TZ string parsing for future dates

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// TZif file magic number
pub const TZIF_MAGIC = [4]u8{ 'T', 'Z', 'i', 'f' };

/// TZif version identifiers
pub const TZifVersion = enum(u8) {
    v1 = 0,
    v2 = '2',
    v3 = '3',

    pub fn isExtended(self: TZifVersion) bool {
        return self == .v2 or self == .v3;
    }

    pub fn supports64BitTimes(self: TZifVersion) bool {
        return self.isExtended();
    }

    pub fn fromByte(byte: u8) ?TZifVersion {
        return switch (byte) {
            0 => .v1,
            '2' => .v2,
            '3' => .v3,
            else => null,
        };
    }
};

/// TZif file header (44 bytes)
pub const TZifHeader = struct {
    magic: [4]u8,
    version: u8,
    reserved: [15]u8,
    isut_count: u32,
    isstd_count: u32,
    leap_count: u32,
    time_count: u32,
    type_count: u32,
    char_count: u32,

    pub const SIZE: usize = 44;

    /// Parse header from bytes
    pub fn parse(data: []const u8) !TZifHeader {
        if (data.len < SIZE) {
            return error.TruncatedFile;
        }

        var header: TZifHeader = undefined;
        @memcpy(&header.magic, data[0..4]);

        if (!mem.eql(u8, &header.magic, &TZIF_MAGIC)) {
            return error.InvalidMagic;
        }

        header.version = data[4];
        @memcpy(&header.reserved, data[5..20]);
        header.isut_count = mem.readInt(u32, data[20..24], .big);
        header.isstd_count = mem.readInt(u32, data[24..28], .big);
        header.leap_count = mem.readInt(u32, data[28..32], .big);
        header.time_count = mem.readInt(u32, data[32..36], .big);
        header.type_count = mem.readInt(u32, data[36..40], .big);
        header.char_count = mem.readInt(u32, data[40..44], .big);

        return header;
    }

    /// Check if magic is valid
    pub fn isValid(self: *const TZifHeader) bool {
        return mem.eql(u8, &self.magic, &TZIF_MAGIC);
    }

    /// Get version enum
    pub fn getVersion(self: *const TZifHeader) ?TZifVersion {
        return TZifVersion.fromByte(self.version);
    }

    /// Calculate data block size for v1 format
    pub fn dataBlockSizeV1(self: *const TZifHeader) usize {
        return self.time_count * 4 + // transition times (32-bit)
            self.time_count + // transition types
            self.type_count * 6 + // ttinfo structs
            self.char_count + // timezone abbreviations
            self.leap_count * 8 + // leap second records (32-bit time + 32-bit correction)
            self.isstd_count + // std/wall indicators
            self.isut_count; // ut/local indicators
    }

    /// Calculate data block size for v2/v3 format
    pub fn dataBlockSizeV2(self: *const TZifHeader) usize {
        return self.time_count * 8 + // transition times (64-bit)
            self.time_count + // transition types
            self.type_count * 6 + // ttinfo structs
            self.char_count + // timezone abbreviations
            self.leap_count * 12 + // leap second records (64-bit time + 32-bit correction)
            self.isstd_count + // std/wall indicators
            self.isut_count; // ut/local indicators
    }
};

/// Leap second record
pub const LeapSecondRecord = struct {
    /// Unix timestamp when leap second occurs
    timestamp: i64,
    /// Cumulative correction after this leap second
    correction: i32,

    /// Parse from v1 format (8 bytes: 4-byte time + 4-byte correction)
    pub fn parseV1(data: []const u8) LeapSecondRecord {
        const time = @as(i64, @bitCast(@as(i32, @bitCast(mem.readInt(u32, data[0..4], .big)))));
        const correction = @as(i32, @bitCast(mem.readInt(u32, data[4..8], .big)));
        return .{ .timestamp = time, .correction = correction };
    }

    /// Parse from v2/v3 format (12 bytes: 8-byte time + 4-byte correction)
    pub fn parseV2(data: []const u8) LeapSecondRecord {
        const time = @bitCast(mem.readInt(u64, data[0..8], .big));
        const correction = @as(i32, @bitCast(mem.readInt(u32, data[8..12], .big)));
        return .{ .timestamp = time, .correction = correction };
    }

    /// Check if this leap second applies to a given timestamp
    pub fn appliesTo(self: LeapSecondRecord, timestamp: i64) bool {
        return timestamp >= self.timestamp;
    }
};

/// Known leap seconds from the IANA database
pub const KnownLeapSeconds = struct {
    /// List of all leap seconds since 1972
    pub const LEAP_SECONDS = [_]LeapSecondRecord{
        .{ .timestamp = 78796800, .correction = 1 }, // 1972-07-01
        .{ .timestamp = 94694400, .correction = 2 }, // 1973-01-01
        .{ .timestamp = 126230400, .correction = 3 }, // 1974-01-01
        .{ .timestamp = 157766400, .correction = 4 }, // 1975-01-01
        .{ .timestamp = 189302400, .correction = 5 }, // 1976-01-01
        .{ .timestamp = 220924800, .correction = 6 }, // 1977-01-01
        .{ .timestamp = 252460800, .correction = 7 }, // 1978-01-01
        .{ .timestamp = 283996800, .correction = 8 }, // 1979-01-01
        .{ .timestamp = 315532800, .correction = 9 }, // 1980-01-01
        .{ .timestamp = 362793600, .correction = 10 }, // 1981-07-01
        .{ .timestamp = 394329600, .correction = 11 }, // 1982-07-01
        .{ .timestamp = 425865600, .correction = 12 }, // 1983-07-01
        .{ .timestamp = 489024000, .correction = 13 }, // 1985-07-01
        .{ .timestamp = 567993600, .correction = 14 }, // 1988-01-01
        .{ .timestamp = 631152000, .correction = 15 }, // 1990-01-01
        .{ .timestamp = 662688000, .correction = 16 }, // 1991-01-01
        .{ .timestamp = 709948800, .correction = 17 }, // 1992-07-01
        .{ .timestamp = 741484800, .correction = 18 }, // 1993-07-01
        .{ .timestamp = 773020800, .correction = 19 }, // 1994-07-01
        .{ .timestamp = 820454400, .correction = 20 }, // 1996-01-01
        .{ .timestamp = 867715200, .correction = 21 }, // 1997-07-01
        .{ .timestamp = 915148800, .correction = 22 }, // 1999-01-01
        .{ .timestamp = 1136073600, .correction = 23 }, // 2006-01-01
        .{ .timestamp = 1230768000, .correction = 24 }, // 2009-01-01
        .{ .timestamp = 1341100800, .correction = 25 }, // 2012-07-01
        .{ .timestamp = 1435708800, .correction = 26 }, // 2015-07-01
        .{ .timestamp = 1483228800, .correction = 27 }, // 2017-01-01
    };

    /// Get cumulative leap second correction for a timestamp
    pub fn getCorrection(timestamp: i64) i32 {
        var correction: i32 = 0;
        for (LEAP_SECONDS) |ls| {
            if (timestamp >= ls.timestamp) {
                correction = ls.correction;
            } else {
                break;
            }
        }
        return correction;
    }

    /// Get the number of leap seconds
    pub fn count() usize {
        return LEAP_SECONDS.len;
    }
};

/// POSIX TZ string rule for DST transitions
pub const TZRule = struct {
    /// Month (1-12) for M format, or day-of-year for J/n format
    value: u16,
    /// Week of month (1-5) for M format
    week: u8 = 0,
    /// Day of week (0-6, 0=Sunday) for M format
    day_of_week: u8 = 0,
    /// Time of day in seconds
    time: i32 = 7200, // Default 2:00 AM
    /// Rule type
    rule_type: RuleType,

    pub const RuleType = enum {
        julian, // Jn (1-365, no leap day)
        day_of_year, // n (0-365)
        month_week_day, // Mm.w.d
    };

    /// Parse from string like "M3.2.0" or "J60" or "150"
    pub fn parse(str: []const u8) ?TZRule {
        if (str.len == 0) return null;

        // Check for time suffix
        var main_part = str;
        var time: i32 = 7200;

        if (mem.indexOf(u8, str, "/")) |slash_idx| {
            main_part = str[0..slash_idx];
            time = parseTime(str[slash_idx + 1 ..]) orelse 7200;
        }

        if (main_part[0] == 'M') {
            return parseMFormat(main_part[1..], time);
        } else if (main_part[0] == 'J') {
            const day = std.fmt.parseInt(u16, main_part[1..], 10) catch return null;
            return TZRule{
                .value = day,
                .rule_type = .julian,
                .time = time,
            };
        } else {
            const day = std.fmt.parseInt(u16, main_part, 10) catch return null;
            return TZRule{
                .value = day,
                .rule_type = .day_of_year,
                .time = time,
            };
        }
    }

    fn parseMFormat(str: []const u8, time: i32) ?TZRule {
        var iter = mem.splitScalar(u8, str, '.');
        const month_str = iter.next() orelse return null;
        const week_str = iter.next() orelse return null;
        const day_str = iter.next() orelse return null;

        return TZRule{
            .value = std.fmt.parseInt(u16, month_str, 10) catch return null,
            .week = std.fmt.parseInt(u8, week_str, 10) catch return null,
            .day_of_week = std.fmt.parseInt(u8, day_str, 10) catch return null,
            .rule_type = .month_week_day,
            .time = time,
        };
    }

    fn parseTime(str: []const u8) ?i32 {
        var iter = mem.splitScalar(u8, str, ':');
        const hours_str = iter.next() orelse return null;
        const hours = std.fmt.parseInt(i32, hours_str, 10) catch return null;

        var result = hours * 3600;

        if (iter.next()) |mins_str| {
            const mins = std.fmt.parseInt(i32, mins_str, 10) catch return null;
            result += mins * 60;

            if (iter.next()) |secs_str| {
                const secs = std.fmt.parseInt(i32, secs_str, 10) catch return null;
                result += secs;
            }
        }

        return result;
    }

    /// Calculate the timestamp of this rule for a given year
    pub fn toTimestamp(self: TZRule, year: i32, utc_offset: i32) i64 {
        const days = switch (self.rule_type) {
            .julian => self.julianToDays(year),
            .day_of_year => @as(i64, self.value),
            .month_week_day => self.mwdToDays(year),
        };

        const year_start = yearToTimestamp(year);
        return year_start + days * 86400 + self.time - utc_offset;
    }

    fn julianToDays(self: TZRule, year: i32) i64 {
        var day: i64 = self.value;
        // Julian format doesn't count Feb 29, so adjust for leap years
        if (day > 59 and isLeapYear(year)) {
            day += 1;
        }
        return day - 1; // Convert 1-based to 0-based
    }

    fn mwdToDays(self: TZRule, year: i32) i64 {
        // Find first day of month
        var days: i64 = 0;
        var m: u8 = 1;
        while (m < self.value) : (m += 1) {
            days += daysInMonth(year, m);
        }

        // Find day of week of first of month
        const jan1_dow = dayOfWeek(year, 1, 1);
        const month_start_dow = @mod(jan1_dow + @as(i32, @intCast(days)), 7);

        // Find first occurrence of target day
        var day: i32 = 1;
        const target: i32 = @intCast(self.day_of_week);
        if (month_start_dow <= target) {
            day += target - month_start_dow;
        } else {
            day += 7 - month_start_dow + target;
        }

        // Add weeks
        if (self.week <= 4) {
            day += (@as(i32, self.week) - 1) * 7;
        } else {
            // Week 5 means last occurrence
            const dim = daysInMonth(year, @intCast(self.value));
            while (day + 7 <= dim) {
                day += 7;
            }
        }

        return days + day - 1;
    }
};

/// POSIX TZ string representing a timezone
pub const POSIXTZString = struct {
    /// Standard time abbreviation
    std_abbr: []const u8,
    /// Standard time UTC offset in seconds
    std_offset: i32,
    /// DST abbreviation (null if no DST)
    dst_abbr: ?[]const u8 = null,
    /// DST UTC offset in seconds (default: std - 3600)
    dst_offset: ?i32 = null,
    /// DST start rule
    dst_start: ?TZRule = null,
    /// DST end rule
    dst_end: ?TZRule = null,

    /// Check if this timezone observes DST
    pub fn hasDst(self: POSIXTZString) bool {
        return self.dst_abbr != null;
    }

    /// Get effective DST offset (std - 1 hour if not specified)
    pub fn getDstOffset(self: POSIXTZString) i32 {
        return self.dst_offset orelse (self.std_offset - 3600);
    }

    /// Check if DST is active at a given timestamp
    pub fn isDstActive(self: POSIXTZString, timestamp: i64, year: i32) bool {
        if (!self.hasDst()) return false;

        const start = self.dst_start orelse return false;
        const end = self.dst_end orelse return false;

        const start_ts = start.toTimestamp(year, self.std_offset);
        const end_ts = end.toTimestamp(year, self.getDstOffset());

        // Northern hemisphere: start < end
        // Southern hemisphere: start > end
        if (start_ts < end_ts) {
            return timestamp >= start_ts and timestamp < end_ts;
        } else {
            return timestamp >= start_ts or timestamp < end_ts;
        }
    }

    /// Get offset at a given timestamp
    pub fn getOffset(self: POSIXTZString, timestamp: i64, year: i32) i32 {
        if (self.isDstActive(timestamp, year)) {
            return self.getDstOffset();
        }
        return self.std_offset;
    }

    /// Get abbreviation at a given timestamp
    pub fn getAbbr(self: POSIXTZString, timestamp: i64, year: i32) []const u8 {
        if (self.isDstActive(timestamp, year)) {
            return self.dst_abbr orelse self.std_abbr;
        }
        return self.std_abbr;
    }
};

/// TZData parsing result
pub const TZDataParseResult = struct {
    header: TZifHeader,
    transitions: []i64,
    transition_types: []u8,
    ttinfos: []TTInfo,
    abbreviations: []const u8,
    leap_seconds: []LeapSecondRecord,
    posix_tz: ?[]const u8,
    allocator: Allocator,

    pub const TTInfo = struct {
        ut_offset: i32,
        is_dst: bool,
        abbr_index: u8,
    };

    pub fn deinit(self: *TZDataParseResult) void {
        self.allocator.free(self.transitions);
        self.allocator.free(self.transition_types);
        self.allocator.free(self.ttinfos);
        self.allocator.free(self.abbreviations);
        self.allocator.free(self.leap_seconds);
        if (self.posix_tz) |tz| {
            self.allocator.free(tz);
        }
    }
};

// Helper functions

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

fn dayOfWeek(year: i32, month: u8, day: u8) i32 {
    var y = year;
    var m: i32 = month;
    if (m < 3) {
        m += 12;
        y -= 1;
    }
    const k: i32 = @mod(y, 100);
    const j: i32 = @divFloor(y, 100);
    const d: i32 = day;
    const h = @mod(d + @divFloor(13 * (m + 1), 5) + k + @divFloor(k, 4) + @divFloor(j, 4) - 2 * j, 7);
    return @mod(h + 6, 7);
}

fn yearToTimestamp(year: i32) i64 {
    var days: i64 = 0;
    if (year >= 1970) {
        var y: i32 = 1970;
        while (y < year) : (y += 1) {
            days += if (isLeapYear(y)) 366 else 365;
        }
    } else {
        var y: i32 = 1969;
        while (y >= year) : (y -= 1) {
            days -= if (isLeapYear(y)) 366 else 365;
        }
    }
    return days * 86400;
}

// ============================================================================
// Tests
// ============================================================================

test "tzif_version_enum" {
    try testing.expect(TZifVersion.v1.isExtended() == false);
    try testing.expect(TZifVersion.v2.isExtended() == true);
    try testing.expect(TZifVersion.v3.isExtended() == true);

    try testing.expect(TZifVersion.v1.supports64BitTimes() == false);
    try testing.expect(TZifVersion.v2.supports64BitTimes() == true);
}

test "tzif_version_from_byte" {
    try testing.expectEqual(TZifVersion.v1, TZifVersion.fromByte(0).?);
    try testing.expectEqual(TZifVersion.v2, TZifVersion.fromByte('2').?);
    try testing.expectEqual(TZifVersion.v3, TZifVersion.fromByte('3').?);
    try testing.expect(TZifVersion.fromByte('4') == null);
}

test "tzif_header_parse_valid" {
    var data: [44]u8 = undefined;
    @memcpy(data[0..4], "TZif");
    data[4] = '2';
    @memset(data[5..20], 0);
    mem.writeInt(u32, data[20..24], 2, .big);
    mem.writeInt(u32, data[24..28], 2, .big);
    mem.writeInt(u32, data[28..32], 1, .big);
    mem.writeInt(u32, data[32..36], 10, .big);
    mem.writeInt(u32, data[36..40], 3, .big);
    mem.writeInt(u32, data[40..44], 16, .big);

    const header = try TZifHeader.parse(&data);
    try testing.expect(header.isValid());
    try testing.expectEqual(TZifVersion.v2, header.getVersion().?);
    try testing.expectEqual(@as(u32, 10), header.time_count);
    try testing.expectEqual(@as(u32, 3), header.type_count);
}

test "tzif_header_parse_truncated" {
    const data = [_]u8{ 'T', 'Z', 'i', 'f' };
    const result = TZifHeader.parse(&data);
    try testing.expectError(error.TruncatedFile, result);
}

test "tzif_header_parse_invalid_magic" {
    var data: [44]u8 = [_]u8{0} ** 44;
    @memcpy(data[0..4], "XXXX");
    const result = TZifHeader.parse(&data);
    try testing.expectError(error.InvalidMagic, result);
}

test "tzif_header_data_block_size" {
    var data: [44]u8 = undefined;
    @memcpy(data[0..4], "TZif");
    data[4] = '2';
    @memset(data[5..20], 0);
    mem.writeInt(u32, data[20..24], 2, .big); // isut
    mem.writeInt(u32, data[24..28], 2, .big); // isstd
    mem.writeInt(u32, data[28..32], 1, .big); // leap
    mem.writeInt(u32, data[32..36], 5, .big); // time
    mem.writeInt(u32, data[36..40], 2, .big); // type
    mem.writeInt(u32, data[40..44], 8, .big); // char

    const header = try TZifHeader.parse(&data);

    // V1: 5*4 + 5 + 2*6 + 8 + 1*8 + 2 + 2 = 20 + 5 + 12 + 8 + 8 + 2 + 2 = 57
    try testing.expectEqual(@as(usize, 57), header.dataBlockSizeV1());

    // V2: 5*8 + 5 + 2*6 + 8 + 1*12 + 2 + 2 = 40 + 5 + 12 + 8 + 12 + 2 + 2 = 81
    try testing.expectEqual(@as(usize, 81), header.dataBlockSizeV2());
}

test "leap_second_record_parse_v1" {
    // timestamp = 78796800, correction = 1
    const data = [_]u8{
        0x04, 0xB2, 0x58, 0x00, // 78796800
        0x00, 0x00, 0x00, 0x01, // 1
    };
    const ls = LeapSecondRecord.parseV1(&data);
    try testing.expectEqual(@as(i64, 78796800), ls.timestamp);
    try testing.expectEqual(@as(i32, 1), ls.correction);
}

test "leap_second_record_parse_v2" {
    const data = [_]u8{
        0x00, 0x00, 0x00, 0x00, 0x04, 0xB2, 0x58, 0x00, // 78796800
        0x00, 0x00, 0x00, 0x01, // 1
    };
    const ls = LeapSecondRecord.parseV2(&data);
    try testing.expectEqual(@as(i64, 78796800), ls.timestamp);
    try testing.expectEqual(@as(i32, 1), ls.correction);
}

test "leap_second_record_applies_to" {
    const ls = LeapSecondRecord{ .timestamp = 1000, .correction = 1 };
    try testing.expect(ls.appliesTo(1000));
    try testing.expect(ls.appliesTo(2000));
    try testing.expect(!ls.appliesTo(999));
}

test "known_leap_seconds_count" {
    try testing.expect(KnownLeapSeconds.count() >= 27);
}

test "known_leap_seconds_get_correction" {
    // Before any leap seconds
    try testing.expectEqual(@as(i32, 0), KnownLeapSeconds.getCorrection(0));

    // After first leap second (1972-07-01)
    try testing.expectEqual(@as(i32, 1), KnownLeapSeconds.getCorrection(78796800));

    // After several leap seconds (2017-01-01)
    try testing.expectEqual(@as(i32, 27), KnownLeapSeconds.getCorrection(1483228800));

    // Well into the future
    try testing.expectEqual(@as(i32, 27), KnownLeapSeconds.getCorrection(2000000000));
}

test "tz_rule_parse_m_format" {
    const rule = TZRule.parse("M3.2.0");
    try testing.expect(rule != null);
    try testing.expectEqual(@as(u16, 3), rule.?.value);
    try testing.expectEqual(@as(u8, 2), rule.?.week);
    try testing.expectEqual(@as(u8, 0), rule.?.day_of_week);
    try testing.expectEqual(TZRule.RuleType.month_week_day, rule.?.rule_type);
}

test "tz_rule_parse_m_format_with_time" {
    const rule = TZRule.parse("M11.1.0/2:00");
    try testing.expect(rule != null);
    try testing.expectEqual(@as(u16, 11), rule.?.value);
    try testing.expectEqual(@as(i32, 7200), rule.?.time);
}

test "tz_rule_parse_julian" {
    const rule = TZRule.parse("J60");
    try testing.expect(rule != null);
    try testing.expectEqual(@as(u16, 60), rule.?.value);
    try testing.expectEqual(TZRule.RuleType.julian, rule.?.rule_type);
}

test "tz_rule_parse_day_of_year" {
    const rule = TZRule.parse("150");
    try testing.expect(rule != null);
    try testing.expectEqual(@as(u16, 150), rule.?.value);
    try testing.expectEqual(TZRule.RuleType.day_of_year, rule.?.rule_type);
}

test "tz_rule_parse_invalid" {
    try testing.expect(TZRule.parse("") == null);
    try testing.expect(TZRule.parse("X123") == null);
}

test "posix_tz_string_no_dst" {
    const tz = POSIXTZString{
        .std_abbr = "UTC",
        .std_offset = 0,
    };

    try testing.expect(!tz.hasDst());
    try testing.expectEqual(@as(i32, 0), tz.getOffset(1000000000, 2001));
    try testing.expectEqualStrings("UTC", tz.getAbbr(1000000000, 2001));
}

test "posix_tz_string_with_dst" {
    const tz = POSIXTZString{
        .std_abbr = "EST",
        .std_offset = -18000,
        .dst_abbr = "EDT",
        .dst_offset = -14400,
        .dst_start = TZRule.parse("M3.2.0"),
        .dst_end = TZRule.parse("M11.1.0"),
    };

    try testing.expect(tz.hasDst());
    try testing.expectEqual(@as(i32, -14400), tz.getDstOffset());
}

test "posix_tz_string_default_dst_offset" {
    const tz = POSIXTZString{
        .std_abbr = "CET",
        .std_offset = 3600, // +1 hour
        .dst_abbr = "CEST",
        // No explicit dst_offset
    };

    // Default DST offset is std - 3600 = 0
    try testing.expectEqual(@as(i32, 0), tz.getDstOffset());
}

test "is_leap_year" {
    try testing.expect(isLeapYear(2000));
    try testing.expect(isLeapYear(2024));
    try testing.expect(!isLeapYear(1900));
    try testing.expect(!isLeapYear(2023));
}

test "days_in_month" {
    try testing.expectEqual(@as(u8, 31), daysInMonth(2023, 1));
    try testing.expectEqual(@as(u8, 28), daysInMonth(2023, 2));
    try testing.expectEqual(@as(u8, 29), daysInMonth(2024, 2));
    try testing.expectEqual(@as(u8, 30), daysInMonth(2023, 4));
}

test "day_of_week" {
    // 2023-01-01 was Sunday
    try testing.expectEqual(@as(i32, 0), dayOfWeek(2023, 1, 1));
    // 1970-01-01 was Thursday
    try testing.expectEqual(@as(i32, 4), dayOfWeek(1970, 1, 1));
}

test "year_to_timestamp" {
    try testing.expectEqual(@as(i64, 0), yearToTimestamp(1970));
    try testing.expectEqual(@as(i64, 365 * 86400), yearToTimestamp(1971));
    try testing.expectEqual(@as(i64, -365 * 86400), yearToTimestamp(1969));
}

test "tz_rule_to_timestamp" {
    // Test US DST start (2nd Sunday March 2023 = March 12)
    const rule = TZRule{
        .value = 3,
        .week = 2,
        .day_of_week = 0,
        .time = 7200,
        .rule_type = .month_week_day,
    };

    const ts = rule.toTimestamp(2023, -18000);
    // March 12, 2023 2:00 AM EST = March 12, 2023 7:00 AM UTC
    try testing.expectEqual(@as(i64, 1678608000), ts);
}

test "leap_second_chronological_order" {
    var prev_ts: i64 = 0;
    for (KnownLeapSeconds.LEAP_SECONDS) |ls| {
        try testing.expect(ls.timestamp > prev_ts);
        prev_ts = ls.timestamp;
    }
}

test "leap_second_corrections_increasing" {
    var prev_corr: i32 = 0;
    for (KnownLeapSeconds.LEAP_SECONDS) |ls| {
        try testing.expect(ls.correction > prev_corr);
        prev_corr = ls.correction;
    }
}
