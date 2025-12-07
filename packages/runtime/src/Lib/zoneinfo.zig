//! Python 'zoneinfo' module - IANA time zone support
//!
//! Provides concrete time zone implementation using IANA time zone database.
//!
//! Mirrors: CPython Lib/zoneinfo/

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const ZoneInfoError = error{
    InvalidTZFile,
    NoTZData,
    InvalidTimezone,
    OutOfMemory,
};

// ============================================================================
// ZoneInfo
// ============================================================================

/// IANA time zone implementation
pub const ZoneInfo = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Time zone key (e.g., "America/New_York")
    key: []const u8,
    /// UTC offset in seconds
    utcoff: i32 = 0,
    /// DST offset in seconds
    dstoff: i32 = 0,
    /// Timezone abbreviation (e.g., "EST", "EDT")
    tzname: []const u8 = "UTC",
    /// Transition times
    transitions: std.ArrayList(Transition),

    const Transition = struct {
        timestamp: i64,
        utcoff: i32,
        dstoff: i32,
        abbr: []const u8,
    };

    /// Create a ZoneInfo from a time zone key
    pub fn init(allocator: std.mem.Allocator, key: []const u8) !Self {
        var zone = Self{
            .allocator = allocator,
            .key = try allocator.dupe(u8, key),
            .transitions = std.ArrayList(Transition).init(allocator),
        };

        // Try to load from TZDATA
        zone.loadFromTZData() catch {
            // Fall back to common time zones
            zone.loadCommonZone() catch {};
        };

        return zone;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.key);
        self.transitions.deinit();
    }

    fn loadFromTZData(self: *Self) !void {
        // Standard locations for tzdata
        const tzdata_paths = [_][]const u8{
            "/usr/share/zoneinfo",
            "/usr/lib/zoneinfo",
            "/etc/zoneinfo",
        };

        for (tzdata_paths) |base_path| {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ base_path, self.key }) catch continue;

            const file = std.fs.cwd().openFile(path, .{}) catch continue;
            defer file.close();

            try self.parseTZFile(file);
            return;
        }

        return error.NoTZData;
    }

    fn parseTZFile(self: *Self, file: std.fs.File) !void {
        // TZif file format
        var header: [44]u8 = undefined;
        _ = try file.read(&header);

        // Check magic number "TZif"
        if (!std.mem.eql(u8, header[0..4], "TZif")) {
            return error.InvalidTZFile;
        }

        // Version (0, '2', or '3')
        const version = header[4];
        _ = version;

        // Read counts from header
        const tzh_ttisutcnt = std.mem.readInt(u32, header[20..24], .big);
        const tzh_ttisstdcnt = std.mem.readInt(u32, header[24..28], .big);
        const tzh_leapcnt = std.mem.readInt(u32, header[28..32], .big);
        const tzh_timecnt = std.mem.readInt(u32, header[32..36], .big);
        const tzh_typecnt = std.mem.readInt(u32, header[36..40], .big);
        const tzh_charcnt = std.mem.readInt(u32, header[40..44], .big);
        _ = tzh_ttisutcnt;
        _ = tzh_ttisstdcnt;
        _ = tzh_leapcnt;
        _ = tzh_typecnt;
        _ = tzh_charcnt;

        // Skip transition times and types for now (simplified)
        _ = tzh_timecnt;

        // In a full implementation, we would parse:
        // - Transition times (tzh_timecnt * 4 bytes)
        // - Transition types (tzh_timecnt bytes)
        // - Local time type records (tzh_typecnt * 6 bytes)
        // - Time zone designations (tzh_charcnt bytes)
        // - Leap second records (tzh_leapcnt * 8 bytes)
        // - Standard/wall indicators (tzh_ttisstdcnt bytes)
        // - UT/local indicators (tzh_ttisutcnt bytes)
    }

    fn loadCommonZone(self: *Self) !void {
        // Common time zones with static offsets
        const zones = std.StaticStringMap(struct { off: i32, abbr: []const u8 }).initComptime(.{
            .{ "UTC", .{ .off = 0, .abbr = "UTC" } },
            .{ "GMT", .{ .off = 0, .abbr = "GMT" } },
            .{ "US/Eastern", .{ .off = -5 * 3600, .abbr = "EST" } },
            .{ "US/Central", .{ .off = -6 * 3600, .abbr = "CST" } },
            .{ "US/Mountain", .{ .off = -7 * 3600, .abbr = "MST" } },
            .{ "US/Pacific", .{ .off = -8 * 3600, .abbr = "PST" } },
            .{ "America/New_York", .{ .off = -5 * 3600, .abbr = "EST" } },
            .{ "America/Chicago", .{ .off = -6 * 3600, .abbr = "CST" } },
            .{ "America/Denver", .{ .off = -7 * 3600, .abbr = "MST" } },
            .{ "America/Los_Angeles", .{ .off = -8 * 3600, .abbr = "PST" } },
            .{ "Europe/London", .{ .off = 0, .abbr = "GMT" } },
            .{ "Europe/Paris", .{ .off = 1 * 3600, .abbr = "CET" } },
            .{ "Europe/Berlin", .{ .off = 1 * 3600, .abbr = "CET" } },
            .{ "Asia/Tokyo", .{ .off = 9 * 3600, .abbr = "JST" } },
            .{ "Asia/Shanghai", .{ .off = 8 * 3600, .abbr = "CST" } },
            .{ "Australia/Sydney", .{ .off = 10 * 3600, .abbr = "AEST" } },
        });

        if (zones.get(self.key)) |zone| {
            self.utcoff = zone.off;
            self.tzname = zone.abbr;
        }
    }

    /// Get UTC offset for a timestamp
    pub fn utcoffset(self: *const Self, timestamp: ?i64) i32 {
        if (timestamp) |ts| {
            // Find the applicable transition
            var offset = self.utcoff;
            for (self.transitions.items) |trans| {
                if (trans.timestamp <= ts) {
                    offset = trans.utcoff;
                } else {
                    break;
                }
            }
            return offset;
        }
        return self.utcoff;
    }

    /// Get DST offset for a timestamp
    pub fn dst(self: *const Self, timestamp: ?i64) i32 {
        if (timestamp) |ts| {
            for (self.transitions.items) |trans| {
                if (trans.timestamp <= ts) {
                    return trans.dstoff;
                }
            }
        }
        return self.dstoff;
    }

    /// Get time zone name for a timestamp
    pub fn tzname_at(self: *const Self, timestamp: ?i64) []const u8 {
        if (timestamp) |ts| {
            for (self.transitions.items) |trans| {
                if (trans.timestamp <= ts) {
                    return trans.abbr;
                }
            }
        }
        return self.tzname;
    }

    /// Get the time zone key
    pub fn getKey(self: *const Self) []const u8 {
        return self.key;
    }

    /// String representation
    pub fn repr(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "ZoneInfo(key='{s}')", .{self.key});
    }
};

// ============================================================================
// TZPATH
// ============================================================================

/// Default search paths for time zone data
pub const TZPATH: []const []const u8 = &.{
    "/usr/share/zoneinfo",
    "/usr/lib/zoneinfo",
    "/usr/share/lib/zoneinfo",
    "/etc/zoneinfo",
};

/// Reset the TZPATH (used for testing)
pub fn reset_tzpath() void {
    // Would reset to default
}

// ============================================================================
// available_timezones
// ============================================================================

/// Get a set of available time zone keys
pub fn available_timezones(allocator: std.mem.Allocator) !hashmap_helper.StringHashMap(void) {
    var zones = hashmap_helper.StringHashMap(void).init(allocator);

    // Add common time zones
    const common = [_][]const u8{
        "UTC",
        "GMT",
        "US/Eastern",
        "US/Central",
        "US/Mountain",
        "US/Pacific",
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Los_Angeles",
        "Europe/London",
        "Europe/Paris",
        "Europe/Berlin",
        "Asia/Tokyo",
        "Asia/Shanghai",
        "Australia/Sydney",
    };

    for (common) |tz| {
        try zones.put(tz, {});
    }

    return zones;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "ZoneInfo UTC" {
    const allocator = std.testing.allocator;
    var zone = try ZoneInfo.init(allocator, "UTC");
    defer zone.deinit();

    try std.testing.expectEqualStrings("UTC", zone.key);
    try std.testing.expectEqual(@as(i32, 0), zone.utcoffset(null));
}

test "ZoneInfo common zone" {
    const allocator = std.testing.allocator;
    var zone = try ZoneInfo.init(allocator, "America/New_York");
    defer zone.deinit();

    try std.testing.expectEqualStrings("America/New_York", zone.key);
    // EST is UTC-5
    try std.testing.expectEqual(@as(i32, -5 * 3600), zone.utcoffset(null));
}

test "ZoneInfo repr" {
    const allocator = std.testing.allocator;
    var zone = try ZoneInfo.init(allocator, "Europe/London");
    defer zone.deinit();

    const s = try zone.repr(allocator);
    defer allocator.free(s);

    try std.testing.expectEqualStrings("ZoneInfo(key='Europe/London')", s);
}

test "available_timezones" {
    const allocator = std.testing.allocator;
    var zones = try available_timezones(allocator);
    defer zones.deinit();

    try std.testing.expect(zones.contains("UTC"));
    try std.testing.expect(zones.contains("America/New_York"));
    try std.testing.expect(zones.contains("Europe/London"));
}

test "TZPATH" {
    try std.testing.expect(TZPATH.len > 0);
    try std.testing.expectEqualStrings("/usr/share/zoneinfo", TZPATH[0]);
}
