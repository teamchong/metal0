//! CPython source: Lib/pstats.py
//!
//! Provides statistics browser for profiler data.
//!
//! Mirrors: CPython Lib/pstats.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Sort Keys
// ============================================================================

/// Sort keys for profile statistics
pub const SortKey = enum {
    calls,
    cumulative,
    cumtime,
    file,
    filename,
    module,
    ncalls,
    pcalls,
    line,
    name,
    nfl,
    stdname,
    time,
    tottime,

    /// Convert string to sort key
    pub fn fromString(s: []const u8) ?SortKey {
        const mapping = .{
            .{ "calls", .calls },
            .{ "cumulative", .cumulative },
            .{ "cumtime", .cumtime },
            .{ "file", .file },
            .{ "filename", .filename },
            .{ "module", .module },
            .{ "ncalls", .ncalls },
            .{ "pcalls", .pcalls },
            .{ "line", .line },
            .{ "name", .name },
            .{ "nfl", .nfl },
            .{ "stdname", .stdname },
            .{ "time", .time },
            .{ "tottime", .tottime },
        };

        inline for (mapping) |pair| {
            if (std.mem.eql(u8, s, pair[0])) {
                return pair[1];
            }
        }
        return null;
    }
};

// ============================================================================
// Function Statistics
// ============================================================================

/// Statistics for a single function
pub const FuncStat = struct {
    /// (filename, line, function)
    func_id: FuncId,
    /// Number of primitive calls (not recursive)
    primitive_calls: usize,
    /// Total calls (including recursive)
    total_calls: usize,
    /// Total time spent in function (excluding subcalls)
    total_time: f64,
    /// Cumulative time (including subcalls)
    cumulative_time: f64,
    /// Callers info
    callers: std.AutoHashMap(FuncId, CallerInfo),

    pub fn init(allocator: std.mem.Allocator, func_id: FuncId) FuncStat {
        return .{
            .func_id = func_id,
            .primitive_calls = 0,
            .total_calls = 0,
            .total_time = 0.0,
            .cumulative_time = 0.0,
            .callers = std.AutoHashMap(FuncId, CallerInfo).init(allocator),
        };
    }

    pub fn deinit(self: *FuncStat) void {
        self.callers.deinit();
    }
};

/// Function identifier
pub const FuncId = struct {
    filename: []const u8,
    lineno: usize,
    name: []const u8,

    pub fn format(self: FuncId, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}:{d}({s})", .{
            self.filename,
            self.lineno,
            self.name,
        });
    }
};

/// Caller information
pub const CallerInfo = struct {
    calls: usize,
    total_time: f64,
    cumulative_time: f64,
};

// ============================================================================
// Stats - Profile Statistics
// ============================================================================

/// Profile statistics container
pub const Stats = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stats: hashmap_helper.StringHashMap(FuncStat),
    total_calls: usize,
    primitive_calls: usize,
    total_time: f64,
    sort_keys: std.ArrayList(SortKey),
    sort_ascending: bool,
    stream: std.fs.File,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .stats = hashmap_helper.StringHashMap(FuncStat).init(allocator),
            .total_calls = 0,
            .primitive_calls = 0,
            .total_time = 0.0,
            .sort_keys = std.ArrayList(SortKey).init(allocator),
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
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        // Read marshaled data
        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        try self.loadMarshaledData(content);
    }

    /// Load marshaled profile data
    fn loadMarshaledData(self: *Self, data: []const u8) !void {
        // Simplified marshal format parsing
        // Real implementation would parse Python marshal format
        _ = data;
        _ = self;
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
        var new_stats = hashmap_helper.StringHashMap(FuncStat).init(self.allocator);

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
    pub fn sortStats(self: *Self, keys: []const SortKey) *Self {
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
            if (SortKey.fromString(s)) |key| {
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
        const writer = self.stream.writer();

        // Header
        try writer.print("         {d} function calls", .{self.total_calls});
        if (self.primitive_calls != self.total_calls) {
            try writer.print(" ({d} primitive calls)", .{self.primitive_calls});
        }
        try writer.print(" in {d:.3} seconds\n\n", .{self.total_time});

        // Column headers
        try writer.writeAll("   ncalls  tottime  percall  cumtime  percall filename:lineno(function)\n");

        // Get sorted stats
        var entries = std.ArrayList(Entry).init(self.allocator);
        defer entries.deinit();

        var it = self.stats.iterator();
        while (it.next()) |entry| {
            try entries.append(.{
                .key = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            });
        }

        // Sort by current sort keys
        const sort_ctx = SortContext{ .keys = self.sort_keys.items };
        std.mem.sort(Entry, entries.items, sort_ctx, SortContext.lessThan);

        // Apply restrictions
        var count: usize = 0;
        for (entries.items) |entry| {
            if (restrictions) |r| {
                var matches = false;
                for (r) |pattern| {
                    if (std.mem.indexOf(u8, entry.key, pattern) != null) {
                        matches = true;
                        break;
                    }
                }
                if (!matches) continue;
            }

            const stat = entry.value;
            const percall_tot = if (stat.primitive_calls > 0)
                stat.total_time / @as(f64, @floatFromInt(stat.primitive_calls))
            else
                0;
            const percall_cum = if (stat.primitive_calls > 0)
                stat.cumulative_time / @as(f64, @floatFromInt(stat.primitive_calls))
            else
                0;

            if (stat.total_calls == stat.primitive_calls) {
                try writer.print("{d:9}", .{stat.total_calls});
            } else {
                try writer.print("{d}/{d}", .{ stat.total_calls, stat.primitive_calls });
            }

            try writer.print("  {d:7.3}  {d:7.3}  {d:7.3}  {d:7.3}  {s}\n", .{
                stat.total_time,
                percall_tot,
                stat.cumulative_time,
                percall_cum,
                entry.key,
            });

            count += 1;
        }

        try writer.print("\n{d} entries printed\n", .{count});
    }

    const Entry = struct {
        key: []const u8,
        value: FuncStat,
    };

    const SortContext = struct {
        keys: []const SortKey,

        fn lessThan(ctx: @This(), a: Entry, b: Entry) bool {
            for (ctx.keys) |key| {
                const cmp = compareByKey(key, a.value, b.value);
                if (cmp != 0) return cmp < 0;
            }
            // Default: sort by name
            return std.mem.order(u8, a.key, b.key) == .lt;
        }

        fn compareByKey(key: SortKey, a: FuncStat, b: FuncStat) i32 {
            return switch (key) {
                .calls, .ncalls, .pcalls => compare(a.total_calls, b.total_calls),
                .cumulative, .cumtime => compareFloat(b.cumulative_time, a.cumulative_time), // descending
                .time, .tottime => compareFloat(b.total_time, a.total_time), // descending
                .line => compare(a.func_id.lineno, b.func_id.lineno),
                else => 0,
            };
        }

        fn compare(a: usize, b: usize) i32 {
            if (a < b) return -1;
            if (a > b) return 1;
            return 0;
        }

        fn compareFloat(a: f64, b: f64) i32 {
            if (a < b) return -1;
            if (a > b) return 1;
            return 0;
        }
    };

    /// Print callers of functions
    pub fn printCallers(self: *Self, restrictions: ?[]const []const u8) !void {
        const writer = self.stream.writer();
        try writer.writeAll("   Ordered by: standard name\n\n");
        try writer.writeAll("Function                          was called by...\n");
        try writer.writeAll("                                      ncalls  tottime  cumtime\n");

        var it = self.stats.iterator();
        while (it.next()) |entry| {
            if (restrictions) |r| {
                var matches = false;
                for (r) |pattern| {
                    if (std.mem.indexOf(u8, entry.key_ptr.*, pattern) != null) {
                        matches = true;
                        break;
                    }
                }
                if (!matches) continue;
            }

            try writer.print("{s}\n", .{entry.key_ptr.*});

            var callers_it = entry.value_ptr.callers.iterator();
            while (callers_it.next()) |caller_entry| {
                const caller_id = caller_entry.key_ptr.*;
                const caller_info = caller_entry.value_ptr.*;

                const caller_str = try caller_id.format(self.allocator);
                defer self.allocator.free(caller_str);

                try writer.print("    {s}  {d}  {d:.3}  {d:.3}\n", .{
                    caller_str,
                    caller_info.calls,
                    caller_info.total_time,
                    caller_info.cumulative_time,
                });
            }
        }
    }

    /// Print what functions call (callee statistics)
    pub fn printCallees(self: *Self, restrictions: ?[]const []const u8) !void {
        const writer = self.stream.writer();
        try writer.writeAll("   Ordered by: standard name\n\n");
        try writer.writeAll("Function                          called...\n");
        try writer.writeAll("                                      ncalls  tottime  cumtime\n");

        _ = restrictions;

        // Iterate through all functions and print their callee info
        var it = self.stats.iterator();
        while (it.next()) |entry| {
            const stat = entry.value_ptr.*;
            try writer.print("{s}\n", .{entry.key_ptr.*});

            // Print callers (which represents who called this function)
            // In pstats, we need to reverse this to show callees
            var caller_it = stat.callers.iterator();
            while (caller_it.next()) |caller_entry| {
                const caller_id = caller_entry.key_ptr.*;
                const info = caller_entry.value_ptr.*;
                try writer.print("    <- {s}:{d}({s})  {d}  {d:.6}  {d:.6}\n", .{
                    caller_id.filename,
                    caller_id.lineno,
                    caller_id.name,
                    info.calls,
                    info.total_time,
                    info.cumulative_time,
                });
            }
        }
    }

    /// Dump statistics to file
    pub fn dumpStats(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        // Write header
        try file.writeAll("# pstats dump\n");

        // Write stats
        var it = self.stats.iterator();
        while (it.next()) |entry| {
            const stat = entry.value_ptr.*;
            var buf: [256]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "{s},{d},{d},{d:.6},{d:.6}\n", .{
                entry.key_ptr.*,
                stat.primitive_calls,
                stat.total_calls,
                stat.total_time,
                stat.cumulative_time,
            }) catch continue;
            try file.writeAll(line);
        }
    }

    /// Get function entries, sorted
    pub fn getTopFunctions(self: *Self, count: usize) ![]FuncStat {
        var entries = std.ArrayList(FuncStat).init(self.allocator);

        var it = self.stats.iterator();
        while (it.next()) |entry| {
            try entries.append(entry.value_ptr.*);
        }

        // Sort by cumulative time
        std.mem.sort(FuncStat, entries.items, {}, struct {
            fn lessThan(_: void, a: FuncStat, b: FuncStat) bool {
                return b.cumulative_time < a.cumulative_time;
            }
        }.lessThan);

        const limit = @min(count, entries.items.len);
        return entries.items[0..limit];
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Create a function key from components
pub fn funcKey(allocator: std.mem.Allocator, filename: []const u8, lineno: usize, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{d}({s})", .{ filename, lineno, name });
}

/// Strip common prefix from filenames
pub fn stripPath(filename: []const u8) []const u8 {
    return std.fs.path.basename(filename);
}

/// Format time value for display
pub fn formatTime(value: f64) [12]u8 {
    var buf: [12]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{d:8.3}", .{value}) catch {};
    return buf;
}

/// Format call count for display
pub fn formatCalls(primitive: usize, total: usize) [12]u8 {
    var buf: [12]u8 = undefined;
    if (primitive == total) {
        _ = std.fmt.bufPrint(&buf, "{d:8}", .{total}) catch {};
    } else {
        _ = std.fmt.bufPrint(&buf, "{d}/{d}", .{ total, primitive }) catch {};
    }
    return buf;
}

// ============================================================================
// Tests
// ============================================================================

test "SortKey fromString" {
    try std.testing.expectEqual(SortKey.calls, SortKey.fromString("calls").?);
    try std.testing.expectEqual(SortKey.cumulative, SortKey.fromString("cumulative").?);
    try std.testing.expectEqual(SortKey.time, SortKey.fromString("time").?);
    try std.testing.expect(SortKey.fromString("invalid") == null);
}

test "FuncStat init" {
    const allocator = std.testing.allocator;
    const func_id = FuncId{
        .filename = "test.py",
        .lineno = 10,
        .name = "test_func",
    };

    var stat = FuncStat.init(allocator, func_id);
    defer stat.deinit();

    try std.testing.expectEqual(@as(usize, 0), stat.total_calls);
    try std.testing.expectEqual(@as(f64, 0.0), stat.total_time);
}

test "FuncId format" {
    const allocator = std.testing.allocator;
    const func_id = FuncId{
        .filename = "test.py",
        .lineno = 10,
        .name = "test_func",
    };

    const formatted = try func_id.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("test.py:10(test_func)", formatted);
}

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

test "funcKey" {
    const allocator = std.testing.allocator;
    const key = try funcKey(allocator, "test.py", 10, "func");
    defer allocator.free(key);
    try std.testing.expectEqualStrings("test.py:10(func)", key);
}

test "stripPath" {
    const result = stripPath("/path/to/file.py");
    try std.testing.expectEqualStrings("file.py", result);
}

test "formatTime" {
    const result = formatTime(1.234);
    try std.testing.expect(std.mem.indexOf(u8, &result, "1.234") != null);
}
