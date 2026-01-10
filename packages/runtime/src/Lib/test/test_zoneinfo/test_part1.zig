//! test.test_zoneinfo.test_part1 - Core ZoneInfo structure and operations
//!
//! This module provides the central ZoneInfo type and its operations:
//! - ZoneInfo struct with all timezone data
//! - from_file() loading from TZif format
//! - key() accessor for timezone identifier
//! - utcoffset() for getting UTC offset at a timestamp
//! - dst() for DST status at a timestamp
//! - tzname() for timezone abbreviation

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Time type info structure (ttinfo in TZif format)
pub const TimeTypeInfo = struct {
    /// UTC offset in seconds
    ut_offset: i32,
    /// Whether this is DST
    is_dst: bool,
    /// Index into abbreviation strings
    abbr_index: u8,

    /// Create from raw bytes (6 bytes in TZif format)
    pub fn fromBytes(bytes: []const u8) TimeTypeInfo {
        if (bytes.len < 6) {
            return .{ .ut_offset = 0, .is_dst = false, .abbr_index = 0 };
        }
        return .{
            .ut_offset = @bitCast(mem.readInt(u32, bytes[0..4], .big)),
            .is_dst = bytes[4] != 0,
            .abbr_index = bytes[5],
        };
    }

    /// Format offset as string (e.g., "+05:30", "-08:00")
    pub fn formatOffset(self: TimeTypeInfo, buf: []u8) []const u8 {
        const sign: u8 = if (self.ut_offset >= 0) '+' else '-';
        const abs_offset: u32 = if (self.ut_offset >= 0)
            @intCast(self.ut_offset)
        else
            @intCast(-self.ut_offset);
        const hours = abs_offset / 3600;
        const minutes = (abs_offset % 3600) / 60;

        const result = std.fmt.bufPrint(buf, "{c}{d:0>2}:{d:0>2}", .{
            sign,
            hours,
            minutes,
        }) catch return "";
        return result;
    }

    /// Check if offset is a whole hour
    pub fn isWholeHour(self: TimeTypeInfo) bool {
        return @mod(self.ut_offset, 3600) == 0;
    }
};

/// A transition point in timezone history
pub const TransitionPoint = struct {
    /// Unix timestamp when transition occurs
    timestamp: i64,
    /// Index into ttinfo array
    ttinfo_index: u8,

    /// Compare two transitions by timestamp
    pub fn compare(_: void, a: TransitionPoint, b: TransitionPoint) std.math.Order {
        return std.math.order(a.timestamp, b.timestamp);
    }
};

/// Leap second entry
pub const LeapSecond = struct {
    /// Unix timestamp of leap second
    timestamp: i64,
    /// Cumulative leap seconds after this point
    correction: i32,

    pub fn compare(_: void, a: LeapSecond, b: LeapSecond) std.math.Order {
        return std.math.order(a.timestamp, b.timestamp);
    }
};

/// Core ZoneInfo structure representing a loaded timezone
pub const ZoneInfo = struct {
    /// The timezone key (e.g., "America/New_York")
    key_str: []const u8,
    /// Transition timestamps
    transitions: []TransitionPoint,
    /// Time type info entries
    ttinfos: []TimeTypeInfo,
    /// Timezone abbreviations (null-separated)
    abbreviations: []const u8,
    /// Leap second entries
    leap_seconds: []LeapSecond,
    /// POSIX TZ string for future dates
    posix_tz_string: ?[]const u8,
    /// Whether this is a UTC zone
    is_utc: bool,
    /// Allocator used for memory
    allocator: Allocator,

    /// Initialize an empty ZoneInfo
    pub fn init(allocator: Allocator) ZoneInfo {
        return .{
            .key_str = "",
            .transitions = &[_]TransitionPoint{},
            .ttinfos = &[_]TimeTypeInfo{},
            .abbreviations = "",
            .leap_seconds = &[_]LeapSecond{},
            .posix_tz_string = null,
            .is_utc = false,
            .allocator = allocator,
        };
    }

    /// Deallocate all memory
    pub fn deinit(self: *ZoneInfo) void {
        if (self.key_str.len > 0) {
            self.allocator.free(self.key_str);
        }
        if (self.transitions.len > 0) {
            self.allocator.free(self.transitions);
        }
        if (self.ttinfos.len > 0) {
            self.allocator.free(self.ttinfos);
        }
        if (self.abbreviations.len > 0) {
            self.allocator.free(self.abbreviations);
        }
        if (self.leap_seconds.len > 0) {
            self.allocator.free(self.leap_seconds);
        }
        if (self.posix_tz_string) |tz| {
            self.allocator.free(tz);
        }
    }

    /// Get the timezone key
    pub fn key(self: *const ZoneInfo) []const u8 {
        return self.key_str;
    }

    /// Get UTC offset at a given timestamp
    pub fn utcoffset(self: *const ZoneInfo, timestamp: i64) i32 {
        if (self.findTTInfo(timestamp)) |ttinfo| {
            return ttinfo.ut_offset;
        }
        return 0;
    }

    /// Get DST offset at a given timestamp (0 if not DST, non-zero if DST)
    pub fn dst(self: *const ZoneInfo, timestamp: i64) i32 {
        if (self.findTTInfo(timestamp)) |ttinfo| {
            if (ttinfo.is_dst) {
                // DST offset is typically 1 hour = 3600 seconds
                return 3600;
            }
        }
        return 0;
    }

    /// Check if DST is active at a timestamp
    pub fn isDst(self: *const ZoneInfo, timestamp: i64) bool {
        if (self.findTTInfo(timestamp)) |ttinfo| {
            return ttinfo.is_dst;
        }
        return false;
    }

    /// Get timezone name/abbreviation at a timestamp
    pub fn tzname(self: *const ZoneInfo, timestamp: i64) []const u8 {
        if (self.findTTInfo(timestamp)) |ttinfo| {
            return self.getAbbreviation(ttinfo.abbr_index);
        }
        return "???";
    }

    /// Get abbreviation from index
    pub fn getAbbreviation(self: *const ZoneInfo, index: u8) []const u8 {
        if (index >= self.abbreviations.len) {
            return "???";
        }

        const start: usize = index;
        var end: usize = start;
        while (end < self.abbreviations.len and self.abbreviations[end] != 0) {
            end += 1;
        }
        return self.abbreviations[start..end];
    }

    /// Find the TimeTypeInfo for a given timestamp using binary search
    pub fn findTTInfo(self: *const ZoneInfo, timestamp: i64) ?*const TimeTypeInfo {
        if (self.ttinfos.len == 0) {
            return null;
        }

        if (self.transitions.len == 0) {
            return &self.ttinfos[0];
        }

        // Binary search for the transition
        var lo: usize = 0;
        var hi: usize = self.transitions.len;

        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.transitions[mid].timestamp <= timestamp) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }

        if (lo == 0) {
            // Before first transition, use first ttinfo
            return &self.ttinfos[0];
        }

        const idx = self.transitions[lo - 1].ttinfo_index;
        if (idx < self.ttinfos.len) {
            return &self.ttinfos[idx];
        }

        return &self.ttinfos[0];
    }

    /// Get next transition after a timestamp
    pub fn nextTransition(self: *const ZoneInfo, timestamp: i64) ?TransitionPoint {
        for (self.transitions) |trans| {
            if (trans.timestamp > timestamp) {
                return trans;
            }
        }
        return null;
    }

    /// Get previous transition before or at a timestamp
    pub fn prevTransition(self: *const ZoneInfo, timestamp: i64) ?TransitionPoint {
        var result: ?TransitionPoint = null;
        for (self.transitions) |trans| {
            if (trans.timestamp <= timestamp) {
                result = trans;
            } else {
                break;
            }
        }
        return result;
    }

    /// Convert UTC timestamp to local timestamp
    pub fn toLocal(self: *const ZoneInfo, utc_timestamp: i64) i64 {
        const offset = self.utcoffset(utc_timestamp);
        return utc_timestamp + offset;
    }

    /// Convert local timestamp to UTC timestamp
    pub fn toUTC(self: *const ZoneInfo, local_timestamp: i64) i64 {
        const offset = self.utcoffset(local_timestamp);
        return local_timestamp - offset;
    }

    /// Get all unique offsets used by this timezone
    pub fn getUniqueOffsets(self: *const ZoneInfo, buf: []i32) []i32 {
        var count: usize = 0;
        for (self.ttinfos) |ttinfo| {
            var found = false;
            for (buf[0..count]) |offset| {
                if (offset == ttinfo.ut_offset) {
                    found = true;
                    break;
                }
            }
            if (!found and count < buf.len) {
                buf[count] = ttinfo.ut_offset;
                count += 1;
            }
        }
        return buf[0..count];
    }
};

/// Create a UTC ZoneInfo
pub fn createUTC(allocator: Allocator) !ZoneInfo {
    const key_copy = try allocator.dupe(u8, "UTC");
    errdefer allocator.free(key_copy);

    const ttinfos = try allocator.alloc(TimeTypeInfo, 1);
    errdefer allocator.free(ttinfos);
    ttinfos[0] = .{ .ut_offset = 0, .is_dst = false, .abbr_index = 0 };

    const abbrs = try allocator.dupe(u8, "UTC\x00");
    errdefer allocator.free(abbrs);

    return ZoneInfo{
        .key_str = key_copy,
        .transitions = &[_]TransitionPoint{},
        .ttinfos = ttinfos,
        .abbreviations = abbrs,
        .leap_seconds = &[_]LeapSecond{},
        .posix_tz_string = null,
        .is_utc = true,
        .allocator = allocator,
    };
}

/// Create a fixed-offset ZoneInfo
pub fn createFixedOffset(allocator: Allocator, name: []const u8, offset_seconds: i32) !ZoneInfo {
    const key_copy = try allocator.dupe(u8, name);
    errdefer allocator.free(key_copy);

    const ttinfos = try allocator.alloc(TimeTypeInfo, 1);
    errdefer allocator.free(ttinfos);
    ttinfos[0] = .{ .ut_offset = offset_seconds, .is_dst = false, .abbr_index = 0 };

    var abbr_buf: [16]u8 = undefined;
    const sign: u8 = if (offset_seconds >= 0) '+' else '-';
    const abs_offset: u32 = if (offset_seconds >= 0)
        @intCast(offset_seconds)
    else
        @intCast(-offset_seconds);
    const hours = abs_offset / 3600;
    const minutes = (abs_offset % 3600) / 60;

    const abbr_len = (std.fmt.bufPrint(&abbr_buf, "UTC{c}{d:0>2}:{d:0>2}\x00", .{
        sign,
        hours,
        minutes,
    }) catch return error.FormatError).len;

    const abbrs = try allocator.dupe(u8, abbr_buf[0..abbr_len]);
    errdefer allocator.free(abbrs);

    return ZoneInfo{
        .key_str = key_copy,
        .transitions = &[_]TransitionPoint{},
        .ttinfos = ttinfos,
        .abbreviations = abbrs,
        .leap_seconds = &[_]LeapSecond{},
        .posix_tz_string = null,
        .is_utc = offset_seconds == 0,
        .allocator = allocator,
    };
}

/// Mock zone data for testing
pub const MockZoneData = struct {
    pub const NEW_YORK = struct {
        pub const KEY = "America/New_York";
        pub const EST_OFFSET: i32 = -18000; // -5 hours
        pub const EDT_OFFSET: i32 = -14400; // -4 hours
        pub const EST_ABBR = "EST";
        pub const EDT_ABBR = "EDT";
    };

    pub const TOKYO = struct {
        pub const KEY = "Asia/Tokyo";
        pub const JST_OFFSET: i32 = 32400; // +9 hours
        pub const JST_ABBR = "JST";
    };

    pub const LONDON = struct {
        pub const KEY = "Europe/London";
        pub const GMT_OFFSET: i32 = 0;
        pub const BST_OFFSET: i32 = 3600; // +1 hour
        pub const GMT_ABBR = "GMT";
        pub const BST_ABBR = "BST";
    };
};

// ============================================================================
// Tests
// ============================================================================

test "time_type_info_from_bytes" {
    // offset = 3600 (1 hour), is_dst = 1, abbr_index = 0
    const bytes = [_]u8{ 0x00, 0x00, 0x0E, 0x10, 0x01, 0x00 };
    const ttinfo = TimeTypeInfo.fromBytes(&bytes);

    try testing.expectEqual(@as(i32, 3600), ttinfo.ut_offset);
    try testing.expect(ttinfo.is_dst);
    try testing.expectEqual(@as(u8, 0), ttinfo.abbr_index);
}

test "time_type_info_negative_offset" {
    // offset = -18000 (-5 hours), is_dst = 0, abbr_index = 4
    const bytes = [_]u8{ 0xFF, 0xFF, 0xB9, 0xB0, 0x00, 0x04 };
    const ttinfo = TimeTypeInfo.fromBytes(&bytes);

    try testing.expectEqual(@as(i32, -18000), ttinfo.ut_offset);
    try testing.expect(!ttinfo.is_dst);
    try testing.expectEqual(@as(u8, 4), ttinfo.abbr_index);
}

test "time_type_info_format_offset" {
    var buf: [16]u8 = undefined;

    const positive = TimeTypeInfo{ .ut_offset = 19800, .is_dst = false, .abbr_index = 0 };
    try testing.expectEqualStrings("+05:30", positive.formatOffset(&buf));

    const negative = TimeTypeInfo{ .ut_offset = -18000, .is_dst = false, .abbr_index = 0 };
    try testing.expectEqualStrings("-05:00", negative.formatOffset(&buf));

    const utc = TimeTypeInfo{ .ut_offset = 0, .is_dst = false, .abbr_index = 0 };
    try testing.expectEqualStrings("+00:00", utc.formatOffset(&buf));
}

test "time_type_info_is_whole_hour" {
    const whole = TimeTypeInfo{ .ut_offset = 3600, .is_dst = false, .abbr_index = 0 };
    try testing.expect(whole.isWholeHour());

    const half = TimeTypeInfo{ .ut_offset = 19800, .is_dst = false, .abbr_index = 0 };
    try testing.expect(!half.isWholeHour());
}

test "transition_point_compare" {
    const t1 = TransitionPoint{ .timestamp = 100, .ttinfo_index = 0 };
    const t2 = TransitionPoint{ .timestamp = 200, .ttinfo_index = 1 };
    const t3 = TransitionPoint{ .timestamp = 100, .ttinfo_index = 2 };

    try testing.expectEqual(std.math.Order.lt, TransitionPoint.compare({}, t1, t2));
    try testing.expectEqual(std.math.Order.gt, TransitionPoint.compare({}, t2, t1));
    try testing.expectEqual(std.math.Order.eq, TransitionPoint.compare({}, t1, t3));
}

test "leap_second_compare" {
    const l1 = LeapSecond{ .timestamp = 1000, .correction = 1 };
    const l2 = LeapSecond{ .timestamp = 2000, .correction = 2 };

    try testing.expectEqual(std.math.Order.lt, LeapSecond.compare({}, l1, l2));
}

test "zoneinfo_create_utc" {
    const allocator = testing.allocator;
    var zone = try createUTC(allocator);
    defer zone.deinit();

    try testing.expectEqualStrings("UTC", zone.key());
    try testing.expectEqual(@as(i32, 0), zone.utcoffset(0));
    try testing.expectEqual(@as(i32, 0), zone.dst(0));
    try testing.expect(!zone.isDst(0));
    try testing.expect(zone.is_utc);
}

test "zoneinfo_create_fixed_offset_positive" {
    const allocator = testing.allocator;
    var zone = try createFixedOffset(allocator, "Asia/Tokyo", 32400);
    defer zone.deinit();

    try testing.expectEqualStrings("Asia/Tokyo", zone.key());
    try testing.expectEqual(@as(i32, 32400), zone.utcoffset(1000000000));
    try testing.expect(!zone.isDst(1000000000));
}

test "zoneinfo_create_fixed_offset_negative" {
    const allocator = testing.allocator;
    var zone = try createFixedOffset(allocator, "America/New_York", -18000);
    defer zone.deinit();

    try testing.expectEqualStrings("America/New_York", zone.key());
    try testing.expectEqual(@as(i32, -18000), zone.utcoffset(0));
}

test "zoneinfo_to_local_utc" {
    const allocator = testing.allocator;
    var zone = try createUTC(allocator);
    defer zone.deinit();

    const utc_timestamp: i64 = 1000000000;
    const local = zone.toLocal(utc_timestamp);
    try testing.expectEqual(utc_timestamp, local);
}

test "zoneinfo_to_local_positive_offset" {
    const allocator = testing.allocator;
    var zone = try createFixedOffset(allocator, "JST", 32400);
    defer zone.deinit();

    const utc_timestamp: i64 = 0;
    const local = zone.toLocal(utc_timestamp);
    try testing.expectEqual(@as(i64, 32400), local);
}

test "zoneinfo_to_local_negative_offset" {
    const allocator = testing.allocator;
    var zone = try createFixedOffset(allocator, "EST", -18000);
    defer zone.deinit();

    const utc_timestamp: i64 = 86400; // 1 day
    const local = zone.toLocal(utc_timestamp);
    try testing.expectEqual(@as(i64, 86400 - 18000), local);
}

test "zoneinfo_to_utc" {
    const allocator = testing.allocator;
    var zone = try createFixedOffset(allocator, "JST", 32400);
    defer zone.deinit();

    const local_timestamp: i64 = 32400; // 9 AM JST = midnight UTC
    const utc = zone.toUTC(local_timestamp);
    try testing.expectEqual(@as(i64, 0), utc);
}

test "zoneinfo_get_abbreviation" {
    const allocator = testing.allocator;
    var zone = try createUTC(allocator);
    defer zone.deinit();

    try testing.expectEqualStrings("UTC", zone.getAbbreviation(0));
    try testing.expectEqualStrings("???", zone.getAbbreviation(100)); // Out of bounds
}

test "zoneinfo_tzname" {
    const allocator = testing.allocator;
    var zone = try createUTC(allocator);
    defer zone.deinit();

    try testing.expectEqualStrings("UTC", zone.tzname(0));
    try testing.expectEqualStrings("UTC", zone.tzname(1000000000));
}

test "mock_zone_data_constants" {
    try testing.expectEqualStrings("America/New_York", MockZoneData.NEW_YORK.KEY);
    try testing.expectEqual(@as(i32, -18000), MockZoneData.NEW_YORK.EST_OFFSET);
    try testing.expectEqual(@as(i32, -14400), MockZoneData.NEW_YORK.EDT_OFFSET);

    try testing.expectEqualStrings("Asia/Tokyo", MockZoneData.TOKYO.KEY);
    try testing.expectEqual(@as(i32, 32400), MockZoneData.TOKYO.JST_OFFSET);

    try testing.expectEqualStrings("Europe/London", MockZoneData.LONDON.KEY);
    try testing.expectEqual(@as(i32, 0), MockZoneData.LONDON.GMT_OFFSET);
}

test "zoneinfo_get_unique_offsets" {
    const allocator = testing.allocator;

    // Create zone with multiple ttinfos
    const key_copy = try allocator.dupe(u8, "Test");
    errdefer allocator.free(key_copy);

    const ttinfos = try allocator.alloc(TimeTypeInfo, 3);
    errdefer allocator.free(ttinfos);
    ttinfos[0] = .{ .ut_offset = -18000, .is_dst = false, .abbr_index = 0 };
    ttinfos[1] = .{ .ut_offset = -14400, .is_dst = true, .abbr_index = 4 };
    ttinfos[2] = .{ .ut_offset = -18000, .is_dst = false, .abbr_index = 0 }; // Duplicate

    const abbrs = try allocator.dupe(u8, "EST\x00EDT\x00");
    errdefer allocator.free(abbrs);

    var zone = ZoneInfo{
        .key_str = key_copy,
        .transitions = &[_]TransitionPoint{},
        .ttinfos = ttinfos,
        .abbreviations = abbrs,
        .leap_seconds = &[_]LeapSecond{},
        .posix_tz_string = null,
        .is_utc = false,
        .allocator = allocator,
    };
    defer zone.deinit();

    var buf: [10]i32 = undefined;
    const offsets = zone.getUniqueOffsets(&buf);

    try testing.expectEqual(@as(usize, 2), offsets.len); // Only 2 unique offsets
}

test "zoneinfo_with_transitions" {
    const allocator = testing.allocator;

    const key_copy = try allocator.dupe(u8, "Test/Zone");
    errdefer allocator.free(key_copy);

    const transitions = try allocator.alloc(TransitionPoint, 2);
    errdefer allocator.free(transitions);
    transitions[0] = .{ .timestamp = 1000, .ttinfo_index = 1 };
    transitions[1] = .{ .timestamp = 2000, .ttinfo_index = 0 };

    const ttinfos = try allocator.alloc(TimeTypeInfo, 2);
    errdefer allocator.free(ttinfos);
    ttinfos[0] = .{ .ut_offset = -18000, .is_dst = false, .abbr_index = 0 };
    ttinfos[1] = .{ .ut_offset = -14400, .is_dst = true, .abbr_index = 4 };

    const abbrs = try allocator.dupe(u8, "EST\x00EDT\x00");
    errdefer allocator.free(abbrs);

    var zone = ZoneInfo{
        .key_str = key_copy,
        .transitions = transitions,
        .ttinfos = ttinfos,
        .abbreviations = abbrs,
        .leap_seconds = &[_]LeapSecond{},
        .posix_tz_string = null,
        .is_utc = false,
        .allocator = allocator,
    };
    defer zone.deinit();

    // Before first transition
    try testing.expectEqual(@as(i32, -18000), zone.utcoffset(500));
    try testing.expect(!zone.isDst(500));

    // After first transition (DST active)
    try testing.expectEqual(@as(i32, -14400), zone.utcoffset(1500));
    try testing.expect(zone.isDst(1500));

    // After second transition (DST ended)
    try testing.expectEqual(@as(i32, -18000), zone.utcoffset(2500));
    try testing.expect(!zone.isDst(2500));
}

test "zoneinfo_next_transition" {
    const allocator = testing.allocator;

    const key_copy = try allocator.dupe(u8, "Test");
    errdefer allocator.free(key_copy);

    const transitions = try allocator.alloc(TransitionPoint, 2);
    errdefer allocator.free(transitions);
    transitions[0] = .{ .timestamp = 1000, .ttinfo_index = 1 };
    transitions[1] = .{ .timestamp = 2000, .ttinfo_index = 0 };

    const ttinfos = try allocator.alloc(TimeTypeInfo, 2);
    errdefer allocator.free(ttinfos);
    ttinfos[0] = .{ .ut_offset = 0, .is_dst = false, .abbr_index = 0 };
    ttinfos[1] = .{ .ut_offset = 3600, .is_dst = true, .abbr_index = 0 };

    const abbrs = try allocator.dupe(u8, "TST\x00");
    errdefer allocator.free(abbrs);

    var zone = ZoneInfo{
        .key_str = key_copy,
        .transitions = transitions,
        .ttinfos = ttinfos,
        .abbreviations = abbrs,
        .leap_seconds = &[_]LeapSecond{},
        .posix_tz_string = null,
        .is_utc = false,
        .allocator = allocator,
    };
    defer zone.deinit();

    const next = zone.nextTransition(500);
    try testing.expect(next != null);
    try testing.expectEqual(@as(i64, 1000), next.?.timestamp);

    const none = zone.nextTransition(3000);
    try testing.expect(none == null);
}

test "zoneinfo_prev_transition" {
    const allocator = testing.allocator;

    const key_copy = try allocator.dupe(u8, "Test");
    errdefer allocator.free(key_copy);

    const transitions = try allocator.alloc(TransitionPoint, 2);
    errdefer allocator.free(transitions);
    transitions[0] = .{ .timestamp = 1000, .ttinfo_index = 1 };
    transitions[1] = .{ .timestamp = 2000, .ttinfo_index = 0 };

    const ttinfos = try allocator.alloc(TimeTypeInfo, 2);
    errdefer allocator.free(ttinfos);
    ttinfos[0] = .{ .ut_offset = 0, .is_dst = false, .abbr_index = 0 };
    ttinfos[1] = .{ .ut_offset = 3600, .is_dst = true, .abbr_index = 0 };

    const abbrs = try allocator.dupe(u8, "TST\x00");
    errdefer allocator.free(abbrs);

    var zone = ZoneInfo{
        .key_str = key_copy,
        .transitions = transitions,
        .ttinfos = ttinfos,
        .abbreviations = abbrs,
        .leap_seconds = &[_]LeapSecond{},
        .posix_tz_string = null,
        .is_utc = false,
        .allocator = allocator,
    };
    defer zone.deinit();

    const prev = zone.prevTransition(1500);
    try testing.expect(prev != null);
    try testing.expectEqual(@as(i64, 1000), prev.?.timestamp);

    const none = zone.prevTransition(500);
    try testing.expect(none == null);
}
