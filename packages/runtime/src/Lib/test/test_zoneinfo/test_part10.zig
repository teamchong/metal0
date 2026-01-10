//! test.test_zoneinfo.test_part10 - zoneinfo leap seconds and TAI tests
const std = @import("std");

/// Leap second entry
pub const LeapSecond = struct {
    timestamp: i64,    // Unix timestamp when leap second occurs
    correction: i32,   // Cumulative leap second correction

    pub fn init(timestamp: i64, correction: i32) LeapSecond {
        return .{ .timestamp = timestamp, .correction = correction };
    }

    pub fn isPositive(self: *const LeapSecond) bool {
        return self.correction > 0;
    }
};

/// Leap second table
pub const LeapSecondTable = struct {
    entries: std.ArrayList(LeapSecond),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LeapSecondTable {
        return .{
            .entries = std.ArrayList(LeapSecond).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LeapSecondTable) void {
        self.entries.deinit();
    }

    pub fn add(self: *LeapSecondTable, entry: LeapSecond) !void {
        try self.entries.append(entry);
    }

    pub fn count(self: *const LeapSecondTable) usize {
        return self.entries.items.len;
    }

    pub fn getCorrection(self: *const LeapSecondTable, timestamp: i64) i32 {
        var correction: i32 = 0;
        for (self.entries.items) |entry| {
            if (entry.timestamp <= timestamp) {
                correction = entry.correction;
            } else {
                break;
            }
        }
        return correction;
    }

    pub fn totalLeapSeconds(self: *const LeapSecondTable) i32 {
        if (self.entries.items.len == 0) return 0;
        return self.entries.items[self.entries.items.len - 1].correction;
    }
};

/// TAI (International Atomic Time) offset from UTC
pub const TAIOffset = struct {
    base_offset: i32 = 10,  // TAI-UTC at epoch (1972-01-01)
    leap_table: ?*LeapSecondTable = null,

    pub fn init() TAIOffset {
        return .{};
    }

    pub fn withLeapTable(self: TAIOffset, table: *LeapSecondTable) TAIOffset {
        var copy = self;
        copy.leap_table = table;
        return copy;
    }

    pub fn getTAIOffset(self: *const TAIOffset, utc_timestamp: i64) i32 {
        var offset = self.base_offset;
        if (self.leap_table) |table| {
            offset += table.getCorrection(utc_timestamp);
        }
        return offset;
    }

    pub fn utcToTAI(self: *const TAIOffset, utc_timestamp: i64) i64 {
        return utc_timestamp + self.getTAIOffset(utc_timestamp);
    }

    pub fn taiToUTC(self: *const TAIOffset, tai_timestamp: i64) i64 {
        // Simplified - actual conversion needs iteration for leap seconds
        return tai_timestamp - self.base_offset;
    }
};

/// GPS time offset (constant offset from TAI)
pub const GPSTime = struct {
    tai_gps_offset: i32 = 19,  // TAI - GPS = 19 seconds

    pub fn utcToGPS(self: *const GPSTime, utc_timestamp: i64, tai_offset: *const TAIOffset) i64 {
        const tai = tai_offset.utcToTAI(utc_timestamp);
        return tai - self.tai_gps_offset;
    }

    pub fn gpsToUTC(self: *const GPSTime, gps_timestamp: i64, tai_offset: *const TAIOffset) i64 {
        const tai = gps_timestamp + self.tai_gps_offset;
        return tai_offset.taiToUTC(tai);
    }
};

/// Time scale enumeration
pub const TimeScale = enum {
    utc,    // Coordinated Universal Time
    tai,    // International Atomic Time
    gps,    // GPS Time
    ut1,    // Universal Time (rotation-based)

    pub fn toString(self: TimeScale) []const u8 {
        return switch (self) {
            .utc => "UTC",
            .tai => "TAI",
            .gps => "GPS",
            .ut1 => "UT1",
        };
    }

    pub fn hasLeapSeconds(self: TimeScale) bool {
        return self == .utc;
    }
};

/// Known leap second dates (simplified list)
pub const KNOWN_LEAP_SECONDS = [_]struct { year: u16, month: u8, is_positive: bool }{
    .{ .year = 1972, .month = 6, .is_positive = true },
    .{ .year = 1972, .month = 12, .is_positive = true },
    .{ .year = 1973, .month = 12, .is_positive = true },
    .{ .year = 2012, .month = 6, .is_positive = true },
    .{ .year = 2015, .month = 6, .is_positive = true },
    .{ .year = 2016, .month = 12, .is_positive = true },
};

/// Check if a year had any leap seconds
pub fn yearHasLeapSecond(year: u16) bool {
    for (KNOWN_LEAP_SECONDS) |ls| {
        if (ls.year == year) return true;
    }
    return false;
}

/// IERS bulletin info (simplified)
pub const IERSBulletin = struct {
    bulletin_type: BulletinType,
    issue_date: i64,
    next_leap_second: ?i64 = null,

    pub const BulletinType = enum { A, B, C, D };

    pub fn hasScheduledLeapSecond(self: *const IERSBulletin) bool {
        return self.next_leap_second != null;
    }
};

/// UT1-UTC difference tracking
pub const UT1Correction = struct {
    date: i64,       // MJD or timestamp
    dut1: f64,       // UT1-UTC in seconds

    pub fn init(date: i64, dut1: f64) UT1Correction {
        return .{ .date = date, .dut1 = dut1 };
    }

    pub fn isPositive(self: *const UT1Correction) bool {
        return self.dut1 > 0;
    }
};

/// Right-continuous vs left-continuous timestamp handling
pub const LeapSecondFold = enum {
    prefer_before,   // Use time before leap second
    prefer_after,    // Use time after leap second
    prefer_leap,     // Use 23:59:60 if possible
};

test "LeapSecond" {
    const ls = LeapSecond.init(78796800, 1);  // 1972-06-30
    try std.testing.expectEqual(@as(i64, 78796800), ls.timestamp);
    try std.testing.expectEqual(@as(i32, 1), ls.correction);
    try std.testing.expect(ls.isPositive());
}

test "LeapSecondTable" {
    const allocator = std.testing.allocator;
    var table = LeapSecondTable.init(allocator);
    defer table.deinit();

    try table.add(LeapSecond.init(78796800, 1));   // 1972-06-30
    try table.add(LeapSecond.init(94694400, 2));   // 1972-12-31
    try table.add(LeapSecond.init(126230400, 3));  // 1973-12-31

    try std.testing.expectEqual(@as(usize, 3), table.count());
    try std.testing.expectEqual(@as(i32, 3), table.totalLeapSeconds());

    // Before first leap second
    try std.testing.expectEqual(@as(i32, 0), table.getCorrection(50000000));

    // After first, before second
    try std.testing.expectEqual(@as(i32, 1), table.getCorrection(80000000));

    // After all
    try std.testing.expectEqual(@as(i32, 3), table.getCorrection(200000000));
}

test "TAIOffset" {
    const allocator = std.testing.allocator;
    var table = LeapSecondTable.init(allocator);
    defer table.deinit();

    try table.add(LeapSecond.init(78796800, 1));
    try table.add(LeapSecond.init(94694400, 2));

    const tai = TAIOffset.init().withLeapTable(&table);

    // Base offset is 10
    try std.testing.expectEqual(@as(i32, 10), tai.getTAIOffset(0));

    // After leap seconds: 10 + 2 = 12
    try std.testing.expectEqual(@as(i32, 12), tai.getTAIOffset(100000000));

    // UTC to TAI conversion
    const utc_ts: i64 = 100000000;
    try std.testing.expectEqual(@as(i64, 100000012), tai.utcToTAI(utc_ts));
}

test "GPSTime" {
    const tai = TAIOffset.init();
    const gps = GPSTime{};

    const utc_ts: i64 = 1000000000;
    const gps_ts = gps.utcToGPS(utc_ts, &tai);

    // GPS = TAI - 19, TAI = UTC + 10 (base)
    // GPS = UTC + 10 - 19 = UTC - 9
    try std.testing.expectEqual(utc_ts + 10 - 19, gps_ts);
}

test "TimeScale" {
    try std.testing.expectEqualStrings("UTC", TimeScale.utc.toString());
    try std.testing.expect(TimeScale.utc.hasLeapSeconds());
    try std.testing.expect(!TimeScale.tai.hasLeapSeconds());
    try std.testing.expect(!TimeScale.gps.hasLeapSeconds());
}

test "yearHasLeapSecond" {
    try std.testing.expect(yearHasLeapSecond(1972));
    try std.testing.expect(yearHasLeapSecond(2016));
    try std.testing.expect(!yearHasLeapSecond(2020));
}

test "UT1Correction" {
    const corr = UT1Correction.init(60000, 0.3);
    try std.testing.expectEqual(@as(f64, 0.3), corr.dut1);
    try std.testing.expect(corr.isPositive());

    const neg_corr = UT1Correction.init(60000, -0.2);
    try std.testing.expect(!neg_corr.isPositive());
}

test "IERSBulletin" {
    const bulletin = IERSBulletin{
        .bulletin_type = .C,
        .issue_date = 1600000000,
        .next_leap_second = 1609459200,
    };
    try std.testing.expect(bulletin.hasScheduledLeapSecond());

    const no_leap = IERSBulletin{
        .bulletin_type = .C,
        .issue_date = 1600000000,
    };
    try std.testing.expect(!no_leap.hasScheduledLeapSecond());
}
