//! Profile statistics container
//!
//! Main Stats struct that manages profiling data and provides methods for
//! manipulation, sorting, and analysis.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const sorting = @import("sorting.zig");
const printing = @import("printing.zig");
const io = @import("io.zig");

// ============================================================================
// Stats - Profile Statistics
// ============================================================================

/// Profile statistics container
pub const Stats = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stats: hashmap_helper.StringHashMap(types.FuncStat),
    total_calls: usize,
    primitive_calls: usize,
    total_time: f64,
    sort_keys: std.ArrayList(types.SortKey),
    sort_ascending: bool,
    stream: std.fs.File,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .stats = hashmap_helper.StringHashMap(types.FuncStat).init(allocator),
            .total_calls = 0,
            .primitive_calls = 0,
            .total_time = 0.0,
            .sort_keys = std.ArrayList(types.SortKey).init(allocator),
            .sort_ascending = false, // Default to descending (highest first)
            .stream = std.io.getStdOut(),
        };
    }

    /// Initialize from a profile filename
    pub fn initFromFile(allocator: std.mem.Allocator, filename: []const u8) !Self {
        var self = Self.init(allocator);
        try self.loadFromFile(filename);
        return self;
    }

    pub fn deinit(self: *Self) void {
        var it = self.stats.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.callers.deinit();
        }
        self.stats.deinit();
        self.sort_keys.deinit();
    }

    /// Load profile data from file
    pub fn loadFromFile(self: *Self, filename: []const u8) !void {
        const content = try io.loadFromFile(self.allocator, filename);
        defer self.allocator.free(content);
        try io.loadMarshaledData(content);
    }

    /// Add profile data from another Stats object
    pub fn add(self: *Self, other: *const Stats) void {
        self.total_calls += other.total_calls;
        self.primitive_calls += other.primitive_calls;
        self.total_time += other.total_time;

        // Merge function stats
        var it = other.stats.iterator();
        while (it.next()) |entry| {
            if (self.stats.getPtr(entry.key_ptr.*)) |existing| {
                existing.total_calls += entry.value_ptr.total_calls;
                existing.primitive_calls += entry.value_ptr.primitive_calls;
                existing.total_time += entry.value_ptr.total_time;
                existing.cumulative_time += entry.value_ptr.cumulative_time;
            } else {
                self.stats.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
            }
        }
    }

    /// Strip directory from filenames (only keep basename)
    pub fn stripDirs(self: *Self) *Self {
        // Create new stats with stripped filenames
        var new_stats = hashmap_helper.StringHashMap(types.FuncStat).init(self.allocator);

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            // Parse func_id format: "filename:lineno(funcname)"
            const key = entry.key_ptr.*;
            var new_key_buf: [256]u8 = undefined;

            if (std.mem.indexOf(u8, key, ":")) |colon_pos| {
                const filename = key[0..colon_pos];
                const rest = key[colon_pos..];

                // Get basename of filename
                const basename = std.fs.path.basename(filename);

                // Reconstruct with basename
                const new_key = std.fmt.bufPrint(&new_key_buf, "{s}{s}", .{ basename, rest }) catch key;
                new_stats.put(new_key, entry.value_ptr.*) catch {};
            } else {
                new_stats.put(key, entry.value_ptr.*) catch {};
            }
        }

        // Replace stats with new stripped version
        self.stats.deinit();
        self.stats = new_stats;
        return self;
    }

    /// Sort statistics
    pub fn sortStats(self: *Self, keys: []const types.SortKey) *Self {
        self.sort_keys.clearRetainingCapacity();
        for (keys) |key| {
            self.sort_keys.append(key) catch {};
        }
        return self;
    }

    /// Sort by string keys
    pub fn sortStatsByString(self: *Self, key_strings: []const []const u8) *Self {
        self.sort_keys.clearRetainingCapacity();
        for (key_strings) |s| {
            if (types.SortKey.fromString(s)) |key| {
                self.sort_keys.append(key) catch {};
            }
        }
        return self;
    }

    /// Reverse the current sort order
    pub fn reverseOrder(self: *Self) *Self {
        // Negate the sort_ascending flag to reverse order
        self.sort_ascending = !self.sort_ascending;
        return self;
    }

    /// Print statistics
    pub fn printStats(self: *Self, restrictions: ?[]const []const u8) !void {
        try printing.printStats(
            self.allocator,
            self.stream,
            self.stats,
            self.sort_keys.items,
            self.total_calls,
            self.primitive_calls,
            self.total_time,
            restrictions,
        );
    }

    /// Print callers of functions
    pub fn printCallers(self: *Self, restrictions: ?[]const []const u8) !void {
        try printing.printCallers(
            self.allocator,
            self.stream,
            self.stats,
            restrictions,
        );
    }

    /// Print what functions call (callee statistics)
    pub fn printCallees(self: *Self, restrictions: ?[]const []const u8) !void {
        try printing.printCallees(
            self.stream,
            self.stats,
            restrictions,
        );
    }

    /// Dump statistics to file
    pub fn dumpStats(self: *Self, filename: []const u8) !void {
        try io.dumpStats(self.stats, filename);
    }

    /// Get function entries, sorted
    pub fn getTopFunctions(self: *Self, count: usize) ![]types.FuncStat {
        var entries = std.ArrayList(types.FuncStat).init(self.allocator);

        var it = self.stats.iterator();
        while (it.next()) |entry| {
            try entries.append(entry.value_ptr.*);
        }

        // Sort by cumulative time
        std.mem.sort(types.FuncStat, entries.items, {}, sorting.sortByCumulativeTime);

        const limit = @min(count, entries.items.len);
        return entries.items[0..limit];
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Stats init and deinit" {
    const allocator = std.testing.allocator;
    var stats = Stats.init(allocator);
    defer stats.deinit();

    try std.testing.expectEqual(@as(usize, 0), stats.total_calls);
    try std.testing.expectEqual(@as(f64, 0.0), stats.total_time);
}

test "Stats sortStats" {
    const allocator = std.testing.allocator;
    var stats = Stats.init(allocator);
    defer stats.deinit();

    _ = stats.sortStats(&.{ .time, .calls });
    try std.testing.expectEqual(@as(usize, 2), stats.sort_keys.items.len);
}
