//! zoneinfo._common - Common utilities for timezone handling
//! Reference: cpython/Lib/zoneinfo/_common.py
//!
//! Internal utilities shared between zoneinfo modules.

const std = @import("std");

/// TZif file magic bytes
pub const TZIF_MAGIC = "TZif";

/// TZif version 2 indicator
pub const TZIF_V2 = '2';

/// TZif version 3 indicator
pub const TZIF_V3 = '3';

/// Read a big-endian 32-bit signed integer
pub fn readBE32(data: []const u8) i32 {
    if (data.len < 4) return 0;
    return @bitCast(std.mem.readInt(u32, data[0..4], .big));
}

/// Read a big-endian 64-bit signed integer
pub fn readBE64(data: []const u8) i64 {
    if (data.len < 8) return 0;
    return @bitCast(std.mem.readInt(u64, data[0..8], .big));
}

/// TZif file header structure
pub const TZifHeader = struct {
    magic: [4]u8,
    version: u8,
    reserved: [15]u8,
    isutcnt: u32,
    isstdcnt: u32,
    leapcnt: u32,
    timecnt: u32,
    typecnt: u32,
    charcnt: u32,

    pub fn parse(data: []const u8) ?TZifHeader {
        if (data.len < 44) return null;

        return .{
            .magic = data[0..4].*,
            .version = data[4],
            .reserved = data[5..20].*,
            .isutcnt = std.mem.readInt(u32, data[20..24], .big),
            .isstdcnt = std.mem.readInt(u32, data[24..28], .big),
            .leapcnt = std.mem.readInt(u32, data[28..32], .big),
            .timecnt = std.mem.readInt(u32, data[32..36], .big),
            .typecnt = std.mem.readInt(u32, data[36..40], .big),
            .charcnt = std.mem.readInt(u32, data[40..44], .big),
        };
    }

    pub fn isValid(self: *const TZifHeader) bool {
        return std.mem.eql(u8, &self.magic, TZIF_MAGIC);
    }

    /// Get total data block size for v1 format
    pub fn v1DataSize(self: *const TZifHeader) usize {
        return self.timecnt * 4 + // transition times
            self.timecnt + // transition types
            self.typecnt * 6 + // ttinfo structs
            self.charcnt + // timezone abbreviations
            self.leapcnt * 8 + // leap seconds
            self.isstdcnt + // std/wall indicators
            self.isutcnt; // ut/local indicators
    }
};

/// Transition type info
pub const TTInfo = struct {
    utoff: i32, // UTC offset in seconds
    dst: bool, // Is DST?
    abbr_idx: u8, // Abbreviation index

    pub fn parse(data: []const u8) TTInfo {
        return .{
            .utoff = readBE32(data[0..4]),
            .dst = data[4] != 0,
            .abbr_idx = data[5],
        };
    }
};

/// Leap second entry
pub const LeapSecond = struct {
    timestamp: i64,
    correction: i32,
};

/// Load timezone data from a TZif file
pub fn loadTZif(allocator: std.mem.Allocator, data: []const u8) !struct {
    transitions: std.ArrayList(i64),
    trans_types: std.ArrayList(u8),
    ttinfos: std.ArrayList(TTInfo),
    abbrevs: []const u8,
} {
    const header = TZifHeader.parse(data) orelse return error.InvalidTZif;
    if (!header.isValid()) return error.InvalidTZif;

    var transitions = std.ArrayList(i64).init(allocator);
    var trans_types = std.ArrayList(u8).init(allocator);
    var ttinfos = std.ArrayList(TTInfo).init(allocator);

    // Parse based on version
    var pos: usize = 44;

    if (header.version == TZIF_V2 or header.version == TZIF_V3) {
        // Skip v1 data, use v2/v3 data
        pos += header.v1DataSize();

        // Parse second header
        const header2 = TZifHeader.parse(data[pos..]) orelse return error.InvalidTZif;
        pos += 44;

        // Read 64-bit transition times
        var i: usize = 0;
        while (i < header2.timecnt) : (i += 1) {
            try transitions.append(allocator, readBE64(data[pos .. pos + 8]));
            pos += 8;
        }

        // Read transition types
        i = 0;
        while (i < header2.timecnt) : (i += 1) {
            try trans_types.append(allocator, data[pos]);
            pos += 1;
        }

        // Read ttinfo structs
        i = 0;
        while (i < header2.typecnt) : (i += 1) {
            try ttinfos.append(allocator, TTInfo.parse(data[pos .. pos + 6]));
            pos += 6;
        }

        return .{
            .transitions = transitions,
            .trans_types = trans_types,
            .ttinfos = ttinfos,
            .abbrevs = data[pos .. pos + header2.charcnt],
        };
    } else {
        // Parse v1 data (32-bit timestamps)
        var i: usize = 0;
        while (i < header.timecnt) : (i += 1) {
            try transitions.append(allocator, readBE32(data[pos .. pos + 4]));
            pos += 4;
        }

        i = 0;
        while (i < header.timecnt) : (i += 1) {
            try trans_types.append(allocator, data[pos]);
            pos += 1;
        }

        i = 0;
        while (i < header.typecnt) : (i += 1) {
            try ttinfos.append(allocator, TTInfo.parse(data[pos .. pos + 6]));
            pos += 6;
        }

        return .{
            .transitions = transitions,
            .trans_types = trans_types,
            .ttinfos = ttinfos,
            .abbrevs = data[pos .. pos + header.charcnt],
        };
    }
}

/// Parse POSIX TZ string
pub fn parsePosixTZ(tz_str: []const u8) !struct {
    std_abbr: []const u8,
    std_offset: i32,
    dst_abbr: ?[]const u8,
    dst_offset: ?i32,
} {
    // Simple parsing - full implementation would handle DST rules
    var offset: i32 = 0;
    var pos: usize = 0;

    // Find std abbreviation
    while (pos < tz_str.len and !std.ascii.isDigit(tz_str[pos]) and tz_str[pos] != '-' and tz_str[pos] != '+') {
        pos += 1;
    }
    const std_abbr = tz_str[0..pos];

    // Parse offset
    if (pos < tz_str.len) {
        const negative = tz_str[pos] == '-';
        if (tz_str[pos] == '-' or tz_str[pos] == '+') pos += 1;

        while (pos < tz_str.len and std.ascii.isDigit(tz_str[pos])) {
            offset = offset * 10 + (tz_str[pos] - '0');
            pos += 1;
        }
        offset *= 3600; // Convert hours to seconds
        if (negative) offset = -offset;
    }

    return .{
        .std_abbr = std_abbr,
        .std_offset = offset,
        .dst_abbr = null,
        .dst_offset = null,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "readBE32" {
    const data = [_]u8{ 0x00, 0x00, 0x01, 0x00 };
    try std.testing.expectEqual(@as(i32, 256), readBE32(&data));
}

test "readBE64" {
    const data = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00 };
    try std.testing.expectEqual(@as(i64, 256), readBE64(&data));
}

test "TZifHeader parse" {
    var data: [44]u8 = undefined;
    @memcpy(data[0..4], "TZif");
    data[4] = '2';
    @memset(data[5..44], 0);

    const header = TZifHeader.parse(&data);
    try std.testing.expect(header != null);
    try std.testing.expect(header.?.isValid());
}
