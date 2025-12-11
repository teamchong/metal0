//! Statistics viewer and formatter
//!
//! Provides statistics aggregation, sorting, and display.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const SortKey = @import("sort.zig").SortKey;

const ProfileEntry = types.ProfileEntry;

// ============================================================================
// Stats
// ============================================================================

/// Statistics viewer and formatter
pub const Stats = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    entries: std.ArrayList(ProfileEntry),
    total_calls: u64 = 0,
    total_time: f64 = 0.0,
    prim_calls: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, stats: *hashmap_helper.StringHashMap(ProfileEntry)) Self {
        var entries = std.ArrayList(ProfileEntry).init(allocator);
        var total_calls: u64 = 0;
        var total_time: f64 = 0.0;

        var iter = stats.iterator();
        while (iter.next()) |entry| {
            entries.append(entry.value_ptr.*) catch continue;
            total_calls += entry.value_ptr.ncalls;
            total_time += entry.value_ptr.tottime;
        }

        return .{
            .allocator = allocator,
            .entries = entries,
            .total_calls = total_calls,
            .total_time = total_time,
            .prim_calls = total_calls,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit();
    }

    /// Sort by given key
    pub fn sortStats(self: *Self, key: SortKey) !void {
        const Context = struct {
            key: SortKey,

            pub fn lessThan(ctx: @This(), a: ProfileEntry, b: ProfileEntry) bool {
                return switch (ctx.key) {
                    .calls, .ncalls => a.ncalls > b.ncalls,
                    .cumulative => a.cumtime > b.cumtime,
                    .time, .tottime => a.tottime > b.tottime,
                    .name, .stdname => std.mem.lessThan(u8, a.name, b.name),
                    .filename => std.mem.lessThan(u8, a.filename, b.filename),
                    .line => a.lineno < b.lineno,
                    .pcalls => a.percallCum() > b.percallCum(),
                };
            }
        };

        std.mem.sort(ProfileEntry, self.entries.items, Context{ .key = key }, Context.lessThan);
    }

    /// Print statistics to stdout
    pub fn printStats(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("\n         {d} function calls in {d:.3} seconds\n\n", .{
            self.total_calls,
            self.total_time,
        });

        try stdout.print("   ncalls  tottime  percall  cumtime  percall filename:lineno(function)\n", .{});

        for (self.entries.items) |entry| {
            try stdout.print("{d:>9}  {d:>7.3}  {d:>7.3}  {d:>7.3}  {d:>7.3}  {s}:{d}({s})\n", .{
                entry.ncalls,
                entry.tottime,
                entry.percallTot(),
                entry.cumtime,
                entry.percallCum(),
                entry.filename,
                entry.lineno,
                entry.name,
            });
        }
    }

    /// Strip directory information from filenames
    pub fn stripDirs(self: *Self) void {
        for (self.entries.items) |*entry| {
            if (std.mem.lastIndexOf(u8, entry.filename, "/")) |idx| {
                entry.filename = entry.filename[idx + 1 ..];
            }
        }
    }

    /// Reverse the sort order
    pub fn reverseOrder(self: *Self) void {
        std.mem.reverse(ProfileEntry, self.entries.items);
    }

    /// Print callers of a function
    /// Shows which functions called the specified function
    pub fn printCallers(self: *Self, stats: *hashmap_helper.StringHashMap(ProfileEntry), name: []const u8) !void {
        const stdout = std.io.getStdOut().writer();

        // Find the entry for this function
        const entry = stats.get(name) orelse {
            try stdout.print("No profile entry found for: {s}\n", .{name});
            return;
        };

        try stdout.print("\nCallers of {s}:\n", .{name});
        try stdout.print("  ncalls: {d}\n", .{entry.ncalls});
        try stdout.print("  tottime: {d:.6}\n", .{entry.tottime});
        try stdout.print("  cumtime: {d:.6}\n", .{entry.cumtime});

        // In a full implementation, we would track caller relationships
        // For now, show aggregate stats
        if (entry.callers.count() > 0) {
            try stdout.print("\n  Called by:\n");
            var iter = entry.callers.iterator();
            while (iter.next()) |caller| {
                try stdout.print("    {s}: {d} calls\n", .{ caller.key_ptr.*, caller.value_ptr.* });
            }
        }
    }

    /// Print functions called by a function
    /// Shows which functions the specified function calls
    pub fn printCallees(self: *Self, stats: *hashmap_helper.StringHashMap(ProfileEntry), name: []const u8) !void {
        const stdout = std.io.getStdOut().writer();

        // Find the entry for this function
        const entry = stats.get(name) orelse {
            try stdout.print("No profile entry found for: {s}\n", .{name});
            return;
        };

        try stdout.print("\nCallees of {s}:\n", .{name});

        // In a full implementation, we would track callee relationships
        // For now, show aggregate stats
        if (entry.callees.count() > 0) {
            var iter = entry.callees.iterator();
            while (iter.next()) |callee| {
                try stdout.print("  -> {s}: {d} calls\n", .{ callee.key_ptr.*, callee.value_ptr.* });
            }
        } else {
            try stdout.print("  (no subcalls recorded)\n", .{});
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Stats init" {
    const allocator = std.testing.allocator;
    var stats_map = hashmap_helper.StringHashMap(ProfileEntry).init(allocator);
    defer stats_map.deinit();

    var entry = ProfileEntry.init("test", "test.py", 10);
    entry.ncalls = 5;
    entry.tottime = 0.5;
    try stats_map.put("test", entry);

    var stats = Stats.init(allocator, &stats_map);
    defer stats.deinit();

    try std.testing.expectEqual(@as(u64, 5), stats.total_calls);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), stats.total_time, 0.001);
}
