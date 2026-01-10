//! zoneinfo._zoneinfo - Core ZoneInfo implementation
//! Reference: cpython/Lib/zoneinfo/_zoneinfo.py (internal C accelerator)
//!
//! Core timezone implementation using IANA timezone database.

const std = @import("std");
const common = @import("_common.zig");
const tzpath = @import("_tzpath.zig");

/// ZoneInfo timezone object
pub const ZoneInfo = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    key: []const u8,
    transitions: std.ArrayList(i64),
    trans_types: std.ArrayList(u8),
    ttinfos: std.ArrayList(common.TTInfo),
    abbrevs: []const u8,
    posix_rule: ?[]const u8,

    /// Create a ZoneInfo from an IANA timezone name
    pub fn init(allocator: std.mem.Allocator, key: []const u8) !Self {
        // Find timezone file
        const path = try tzpath.findTzFile(allocator, key) orelse return error.ZoneNotFound;
        defer allocator.free(path);

        // Read and parse file
        const data = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(data);

        const tz_data = try common.loadTZif(allocator, data);

        return .{
            .allocator = allocator,
            .key = try allocator.dupe(u8, key),
            .transitions = tz_data.transitions,
            .trans_types = tz_data.trans_types,
            .ttinfos = tz_data.ttinfos,
            .abbrevs = tz_data.abbrevs,
            .posix_rule = null,
        };
    }

    /// Create a ZoneInfo from raw data
    pub fn fromData(allocator: std.mem.Allocator, key: []const u8, data: []const u8) !Self {
        const tz_data = try common.loadTZif(allocator, data);

        return .{
            .allocator = allocator,
            .key = try allocator.dupe(u8, key),
            .transitions = tz_data.transitions,
            .trans_types = tz_data.trans_types,
            .ttinfos = tz_data.ttinfos,
            .abbrevs = tz_data.abbrevs,
            .posix_rule = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.key);
        self.transitions.deinit(self.allocator);
        self.trans_types.deinit(self.allocator);
        self.ttinfos.deinit(self.allocator);
    }

    /// Get UTC offset for a given timestamp
    pub fn utcoffset(self: *const Self, timestamp: i64) i32 {
        const idx = self.findTransitionIndex(timestamp);
        if (idx < self.trans_types.items.len) {
            const type_idx = self.trans_types.items[idx];
            if (type_idx < self.ttinfos.items.len) {
                return self.ttinfos.items[type_idx].utoff;
            }
        }
        // Default to first ttinfo
        if (self.ttinfos.items.len > 0) {
            return self.ttinfos.items[0].utoff;
        }
        return 0;
    }

    /// Check if DST is in effect for a given timestamp
    pub fn dst(self: *const Self, timestamp: i64) bool {
        const idx = self.findTransitionIndex(timestamp);
        if (idx < self.trans_types.items.len) {
            const type_idx = self.trans_types.items[idx];
            if (type_idx < self.ttinfos.items.len) {
                return self.ttinfos.items[type_idx].dst;
            }
        }
        return false;
    }

    /// Get timezone abbreviation for a given timestamp
    pub fn tzname(self: *const Self, timestamp: i64) []const u8 {
        const idx = self.findTransitionIndex(timestamp);
        if (idx < self.trans_types.items.len) {
            const type_idx = self.trans_types.items[idx];
            if (type_idx < self.ttinfos.items.len) {
                const abbr_idx = self.ttinfos.items[type_idx].abbr_idx;
                if (abbr_idx < self.abbrevs.len) {
                    // Find null terminator
                    var end = abbr_idx;
                    while (end < self.abbrevs.len and self.abbrevs[end] != 0) {
                        end += 1;
                    }
                    return self.abbrevs[abbr_idx..end];
                }
            }
        }
        return "UTC";
    }

    /// Find the transition index for a timestamp using binary search
    fn findTransitionIndex(self: *const Self, timestamp: i64) usize {
        if (self.transitions.items.len == 0) return 0;

        var lo: usize = 0;
        var hi: usize = self.transitions.items.len;

        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.transitions.items[mid] <= timestamp) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }

        return if (lo > 0) lo - 1 else 0;
    }

    /// String representation
    pub fn toString(self: *const Self) []const u8 {
        return self.key;
    }
};

/// Cache of loaded ZoneInfo objects
var zone_cache: ?std.StringHashMap(*ZoneInfo) = null;
var cache_allocator: ?std.mem.Allocator = null;

/// Get or create a ZoneInfo (cached)
pub fn getZoneInfo(allocator: std.mem.Allocator, key: []const u8) !*ZoneInfo {
    // Initialize cache if needed
    if (zone_cache == null) {
        zone_cache = std.StringHashMap(*ZoneInfo).init(allocator);
        cache_allocator = allocator;
    }

    // Check cache
    if (zone_cache.?.get(key)) |cached| {
        return cached;
    }

    // Create new ZoneInfo
    const zone = try allocator.create(ZoneInfo);
    zone.* = try ZoneInfo.init(allocator, key);

    // Cache it
    try zone_cache.?.put(zone.key, zone);

    return zone;
}

/// Clear the zone cache
pub fn clearCache() void {
    if (zone_cache) |*cache| {
        var iter = cache.valueIterator();
        while (iter.next()) |zone| {
            zone.*.deinit();
            cache_allocator.?.destroy(zone.*);
        }
        cache.deinit();
        zone_cache = null;
        cache_allocator = null;
    }
}

/// UTC timezone constant
pub var UTC: ?*ZoneInfo = null;

/// Get UTC timezone
pub fn getUTC(allocator: std.mem.Allocator) !*ZoneInfo {
    if (UTC) |utc| return utc;

    UTC = try allocator.create(ZoneInfo);
    UTC.?.* = .{
        .allocator = allocator,
        .key = "UTC",
        .transitions = std.ArrayList(i64).init(allocator),
        .trans_types = std.ArrayList(u8).init(allocator),
        .ttinfos = std.ArrayList(common.TTInfo).init(allocator),
        .abbrevs = "UTC\x00",
        .posix_rule = null,
    };

    try UTC.?.ttinfos.append(allocator, .{ .utoff = 0, .dst = false, .abbr_idx = 0 });

    return UTC.?;
}

// ============================================================================
// Tests
// ============================================================================

test "ZoneInfo basic" {
    const allocator = std.testing.allocator;

    // Test UTC
    var utc = try getUTC(allocator);
    try std.testing.expectEqualStrings("UTC", utc.key);
    try std.testing.expectEqual(@as(i32, 0), utc.utcoffset(0));
    try std.testing.expect(!utc.dst(0));

    // Clean up
    clearCache();
    if (UTC) |u| {
        u.deinit();
        allocator.destroy(u.*);
        UTC = null;
    }
}

test "findTransitionIndex" {
    const allocator = std.testing.allocator;

    var zone = ZoneInfo{
        .allocator = allocator,
        .key = "Test",
        .transitions = std.ArrayList(i64).init(allocator),
        .trans_types = std.ArrayList(u8).init(allocator),
        .ttinfos = std.ArrayList(common.TTInfo).init(allocator),
        .abbrevs = "",
        .posix_rule = null,
    };
    defer zone.deinit();

    try zone.transitions.append(allocator, 100);
    try zone.transitions.append(allocator, 200);
    try zone.transitions.append(allocator, 300);

    try std.testing.expectEqual(@as(usize, 0), zone.findTransitionIndex(50));
    try std.testing.expectEqual(@as(usize, 0), zone.findTransitionIndex(100));
    try std.testing.expectEqual(@as(usize, 1), zone.findTransitionIndex(150));
    try std.testing.expectEqual(@as(usize, 2), zone.findTransitionIndex(350));
}
