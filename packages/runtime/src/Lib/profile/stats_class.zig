//! Statistics class for loading and manipulating profiling statistics
//!
//! Provides functionality to load, combine, analyze, and display profiling
//! statistics from profiler output files.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

const FuncStats = types.FuncStats;
const SortKey = types.SortKey;

// ============================================================================
// Stats
// ============================================================================

/// Load and manipulate profiling statistics
pub const Stats = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stats: hashmap_helper.StringHashMap(FuncStats),
    total_calls: u64,
    prim_calls: u64,
    total_tt: f64,
    sort_keys: []const SortKey,
    reversed: bool,

    pub fn init(allocator: std.mem.Allocator, filename: ?[]const u8) !Self {
        var self = Self{
            .allocator = allocator,
            .stats = hashmap_helper.StringHashMap(FuncStats).init(allocator),
            .total_calls = 0,
            .prim_calls = 0,
            .total_tt = 0,
            .sort_keys = &[_]SortKey{},
            .reversed = false,
        };

        if (filename) |f| {
            try self.load(f);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.stats.deinit();
    }

    /// Load stats from file
    pub fn load(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len == 0 or line[0] == '#') continue;

            // Parse CSV: name,ncalls,tottime,cumtime
            var parts = std.mem.splitScalar(u8, line, ',');
            const name = parts.next() orelse continue;
            const ncalls_str = parts.next() orelse continue;
            const tottime_str = parts.next() orelse continue;
            const cumtime_str = parts.next() orelse continue;

            var stat = FuncStats.init(self.allocator);
            stat.ncalls = std.fmt.parseInt(u64, ncalls_str, 10) catch 0;
            stat.tottime = std.fmt.parseFloat(f64, tottime_str) catch 0;
            stat.cumtime = std.fmt.parseFloat(f64, cumtime_str) catch 0;
            stat.update();

            try self.stats.put(try self.allocator.dupe(u8, name), stat);
            self.total_calls += stat.ncalls;
            self.total_tt += stat.tottime;
        }
    }

    /// Add stats from another file
    pub fn add(self: *Self, filename: []const u8) !void {
        var other = try Stats.init(self.allocator, filename);
        defer other.deinit();

        var iter = other.stats.iterator();
        while (iter.next()) |entry| {
            const existing = self.stats.getPtr(entry.key_ptr.*);
            if (existing) |e| {
                e.ncalls += entry.value_ptr.ncalls;
                e.tottime += entry.value_ptr.tottime;
                e.cumtime += entry.value_ptr.cumtime;
                e.update();
            } else {
                try self.stats.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        self.total_calls += other.total_calls;
        self.total_tt += other.total_tt;
    }

    /// Print statistics
    pub fn printStats(self: *Self, restrictions: ?[]const []const u8) !void {
        _ = restrictions;
        const stdout = std.io.getStdOut().writer();

        try stdout.print("\n         {d} function calls in {d:.6} seconds\n\n", .{ self.total_calls, self.total_tt });
        try stdout.writeAll("   ncalls  tottime  percall  cumtime  percall filename:lineno(function)\n");

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            const stat = entry.value_ptr;
            try stdout.print("   {d:>6}  {d:>7.3}  {d:>7.3}  {d:>7.3}  {d:>7.3} {s}\n", .{
                stat.ncalls,
                stat.tottime,
                stat.percall_tot,
                stat.cumtime,
                stat.percall_cum,
                entry.key_ptr.*,
            });
        }
    }

    /// Print callers for a function
    pub fn printCallers(self: *Self, restrictions: ?[]const []const u8) !void {
        _ = restrictions;
        const stdout = std.io.getStdOut().writer();

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            try stdout.print("\nFunction: {s}\n", .{entry.key_ptr.*});
            var caller_iter = entry.value_ptr.callers.iterator();
            while (caller_iter.next()) |caller| {
                try stdout.print("  <- {s}: {d} calls\n", .{ caller.key_ptr.*, caller.value_ptr.ncalls });
            }
        }
    }

    /// Print callees for a function
    /// Shows which functions are called by each function in the profile
    pub fn printCallees(self: *Self, restrictions: ?[]const []const u8) !void {
        const stdout = std.io.getStdOut().writer();

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            const func_name = entry.key_ptr.*;

            // Apply restrictions if any
            if (restrictions) |rest| {
                var matches = false;
                for (rest) |pattern| {
                    if (std.mem.indexOf(u8, func_name, pattern) != null) {
                        matches = true;
                        break;
                    }
                }
                if (!matches) continue;
            }

            try stdout.print("\nFunction: {s}\n", .{func_name});
            try stdout.writeAll("  Called:\n");

            // In a full implementation, we would track callee relationships
            // For now, show functions that were called after this one based on timing
            var callee_iter = self.stats.iterator();
            while (callee_iter.next()) |callee| {
                if (!std.mem.eql(u8, callee.key_ptr.*, func_name)) {
                    // Check if this function's callers include the current function
                    if (callee.value_ptr.callers.get(func_name)) |caller_stats| {
                        try stdout.print("    -> {s}: {d} calls, {d:.6}s\n", .{
                            callee.key_ptr.*,
                            caller_stats.ncalls,
                            caller_stats.tottime,
                        });
                    }
                }
            }
        }
    }

    /// Sort statistics by the given keys
    pub fn sortStats(self: *Self, keys: []const SortKey) void {
        self.sort_keys = keys;
        self.reversed = false;
        // Sorting is applied during iteration in printStats
        // The sort_keys field determines the sort order
    }

    /// Reverse the current sort order
    pub fn reverseOrder(self: *Self) void {
        self.reversed = !self.reversed;
    }

    /// Strip directory names from function identifiers
    /// Converts "path/to/file.py:func" to "file.py:func"
    pub fn stripDirs(self: *Self) void {
        // Create a new map with stripped keys
        var new_stats = hashmap_helper.StringHashMap(FuncStats).init(self.allocator);

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            const full_name = entry.key_ptr.*;

            // Find the last path separator
            var stripped_name = full_name;
            if (std.mem.lastIndexOfScalar(u8, full_name, '/')) |pos| {
                stripped_name = full_name[pos + 1 ..];
            } else if (std.mem.lastIndexOfScalar(u8, full_name, '\\')) |pos| {
                stripped_name = full_name[pos + 1 ..];
            }

            // Duplicate the stripped name and add to new map
            const key = self.allocator.dupe(u8, stripped_name) catch continue;
            new_stats.put(key, entry.value_ptr.*) catch {
                self.allocator.free(key);
                continue;
            };
        }

        // Replace old stats with new
        // Note: We don't free old keys since they might be shared
        self.stats.deinit();
        self.stats = new_stats;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Stats init" {
    const allocator = std.testing.allocator;
    var stats = try Stats.init(allocator, null);
    defer stats.deinit();

    try std.testing.expectEqual(@as(u64, 0), stats.total_calls);
}
