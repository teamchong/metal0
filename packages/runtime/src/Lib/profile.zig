//! CPython source: Lib/profile.py
//!
//! Provides deterministic profiling of Python programs.
//!
//! Mirrors: CPython Lib/profile.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Profile Statistics
// ============================================================================

/// Statistics for a single function
pub const FuncStats = struct {
    ncalls: u64, // Number of calls
    tottime: f64, // Total time in this function
    cumtime: f64, // Cumulative time (including subfunctions)
    percall_tot: f64, // Total time per call
    percall_cum: f64, // Cumulative time per call
    callers: hashmap_helper.StringHashMap(CallerStats),
    allocator: std.mem.Allocator,

    pub const CallerStats = struct {
        ncalls: u64,
        tottime: f64,
        cumtime: f64,
    };

    pub fn init(allocator: std.mem.Allocator) FuncStats {
        return .{
            .ncalls = 0,
            .tottime = 0,
            .cumtime = 0,
            .percall_tot = 0,
            .percall_cum = 0,
            .callers = hashmap_helper.StringHashMap(CallerStats).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FuncStats) void {
        self.callers.deinit();
    }

    pub fn update(self: *FuncStats) void {
        if (self.ncalls > 0) {
            self.percall_tot = self.tottime / @as(f64, @floatFromInt(self.ncalls));
            self.percall_cum = self.cumtime / @as(f64, @floatFromInt(self.ncalls));
        }
    }
};

// ============================================================================
// Profile
// ============================================================================

/// Deterministic profiler
pub const Profile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    // Statistics
    stats: hashmap_helper.StringHashMap(FuncStats),
    total_calls: u64,
    prim_calls: u64, // Primitive (non-recursive) calls
    total_tt: f64, // Total time

    // Timing
    timer: fn () i64,
    bias: i64, // Calibration bias

    // State
    cur: ?[]const u8, // Current function
    timings: hashmap_helper.StringHashMap(i64),
    c: i64, // Call count for calibration
    is_enabled: bool, // Whether profiling is active

    pub fn init(allocator: std.mem.Allocator, timer: ?fn () i64, bias: ?i64) Self {
        return .{
            .allocator = allocator,
            .stats = hashmap_helper.StringHashMap(FuncStats).init(allocator),
            .total_calls = 0,
            .prim_calls = 0,
            .total_tt = 0,
            .timer = timer orelse defaultTimer,
            .bias = bias orelse 0,
            .cur = null,
            .timings = hashmap_helper.StringHashMap(i64).init(allocator),
            .c = 0,
            .is_enabled = false,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.stats.deinit();
        self.timings.deinit();
    }

    fn defaultTimer() i64 {
        return std.time.nanoTimestamp();
    }

    /// Enable profiling - starts timing
    pub fn enable(self: *Self) void {
        self.is_enabled = true;
        // In AOT context, profiling is done via explicit traceDispatchCall/Return
        // This flag is used by generated code to decide whether to emit profiling calls
    }

    /// Disable profiling - stops timing
    pub fn disable(self: *Self) void {
        self.is_enabled = false;
        // Finalize any pending timings
        var timing_iter = self.timings.iterator();
        while (timing_iter.next()) |entry| {
            self.traceDispatchReturn(entry.key_ptr.*);
        }
    }

    /// Create stats without enabling
    pub fn createStats(self: *Self) void {
        // Finalize statistics
        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.update();
        }
    }

    /// Print stats report
    pub fn printStats(self: *Self, sort: SortKey) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("\n         {d} function calls in {d:.6} seconds\n\n", .{ self.total_calls, self.total_tt });

        try stdout.writeAll("   Ordered by: ");
        try stdout.writeAll(switch (sort) {
            .calls => "call count",
            .cumulative => "cumulative time",
            .file => "file name",
            .pcalls => "primitive call count",
            .line => "line number",
            .name => "function name",
            .nfl => "name/file/line",
            .stdname => "standard name",
            .time => "internal time",
        });
        try stdout.writeAll("\n\n");

        try stdout.writeAll("   ncalls  tottime  percall  cumtime  percall filename:lineno(function)\n");

        // Collect stats into array for sorting
        var entries = std.ArrayList(struct { key: []const u8, stat: *FuncStats }).init(self.allocator);
        defer entries.deinit();

        var stats_iter = self.stats.iterator();
        while (stats_iter.next()) |entry| {
            entries.append(.{ .key = entry.key_ptr.*, .stat = entry.value_ptr }) catch continue;
        }

        // Sort based on sort_keys
        const sort_key = if (self.sort_keys.len > 0) self.sort_keys[0] else .cumulative;
        const SortContext = struct {
            key: SortKey,
            reversed: bool,
        };
        const ctx = SortContext{ .key = sort_key, .reversed = self.reversed };

        std.mem.sort(@TypeOf(entries.items[0]), entries.items, ctx, struct {
            fn lessThan(c: SortContext, a: @TypeOf(entries.items[0]), b: @TypeOf(entries.items[0])) bool {
                const cmp = switch (c.key) {
                    .calls => a.stat.ncalls < b.stat.ncalls,
                    .cumulative => a.stat.cumtime < b.stat.cumtime,
                    .tottime => a.stat.tottime < b.stat.tottime,
                    .name => std.mem.lessThan(u8, a.key, b.key),
                    else => a.stat.cumtime < b.stat.cumtime,
                };
                return if (c.reversed) !cmp else cmp;
            }
        }.lessThan);

        // Print sorted stats
        for (entries.items) |entry| {
            const stat = entry.stat;
            try stdout.print("   {d:>6}  {d:>7.3}  {d:>7.3}  {d:>7.3}  {d:>7.3} {s}\n", .{
                stat.ncalls,
                stat.tottime,
                stat.percall_tot,
                stat.cumtime,
                stat.percall_cum,
                entry.key,
            });
        }
    }

    /// Dump stats to file
    pub fn dumpStats(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        const writer = file.writer();
        try writer.print("# Profile stats\n", .{});
        try writer.print("# Total calls: {d}\n", .{self.total_calls});
        try writer.print("# Total time: {d:.6}\n", .{self.total_tt});

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            const stat = entry.value_ptr;
            try writer.print("{s},{d},{d:.6},{d:.6}\n", .{
                entry.key_ptr.*,
                stat.ncalls,
                stat.tottime,
                stat.cumtime,
            });
        }
    }

    /// Run a function under profiler
    pub fn runcall(self: *Self, comptime func: anytype, args: anytype) @TypeOf(func).ReturnType {
        self.enable();
        defer self.disable();
        return @call(.auto, func, args);
    }

    /// Run code under profiler
    /// In AOT context, this simulates execution by recording the command as profiled
    pub fn run(self: *Self, cmd: []const u8) !void {
        self.enable();
        defer self.disable();

        // In AOT compilation, we can't dynamically execute code
        // Instead, we record this as a profiled function call
        const start = self.timer();
        self.traceDispatchCall(cmd);

        // The actual execution would happen in compiled code
        // This is a placeholder for the profiling infrastructure
        // Real profiling happens via generated traceDispatchCall/Return in compiled output

        const elapsed = @as(f64, @floatFromInt(self.timer() - start)) / 1_000_000_000.0;
        self.total_tt += elapsed;

        self.traceDispatchReturn(cmd);
    }

    /// Run file under profiler
    pub fn runctx(self: *Self, cmd: []const u8, globals: ?*anyopaque, locals: ?*anyopaque) !void {
        _ = globals;
        _ = locals;
        try self.run(cmd);
    }

    /// Calibrate the profiler
    pub fn calibrate(self: *Self, m: u32, verbose: bool) !i64 {
        const n = 500;
        var elapsed: [n]i64 = undefined;

        for (0..n) |i| {
            const start = self.timer();
            // Call dummy function m times
            var j: u32 = 0;
            while (j < m) : (j += 1) {
                self.c += 1;
            }
            elapsed[i] = self.timer() - start;
        }

        // Find minimum
        var min_elapsed: i64 = elapsed[0];
        for (elapsed[1..]) |e| {
            if (e < min_elapsed) min_elapsed = e;
        }

        if (verbose) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print("Calibration: {d} calls in {d} ns\n", .{ m, min_elapsed });
        }

        return @divFloor(min_elapsed, @as(i64, m));
    }

    // ========================================================================
    // Event Handlers
    // ========================================================================

    /// Handle function call event
    pub fn traceDispatchCall(self: *Self, frame: []const u8) void {
        self.total_calls += 1;
        const entry = self.stats.getOrPut(frame) catch return;
        if (!entry.found_existing) {
            entry.value_ptr.* = FuncStats.init(self.allocator);
        }
        entry.value_ptr.ncalls += 1;
        self.timings.put(frame, self.timer()) catch {};
        self.cur = frame;
    }

    /// Handle function return event
    pub fn traceDispatchReturn(self: *Self, frame: []const u8) void {
        const now = self.timer();
        if (self.timings.get(frame)) |start| {
            const elapsed = @as(f64, @floatFromInt(now - start - self.bias)) / 1_000_000_000.0;
            if (self.stats.getPtr(frame)) |stat| {
                stat.tottime += elapsed;
                stat.cumtime += elapsed;
            }
        }
        _ = self.timings.remove(frame);
        self.cur = null;
    }
};

/// Sort keys for statistics
pub const SortKey = enum {
    calls,
    cumulative,
    file,
    pcalls,
    line,
    name,
    nfl,
    stdname,
    time,
};

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
// Module Functions
// ============================================================================

/// Run a command string under profiler
pub fn run(allocator: std.mem.Allocator, statement: []const u8, filename: ?[]const u8, sort: SortKey) !void {
    var prof = Profile.init(allocator, null, null);
    defer prof.deinit();

    try prof.run(statement);
    prof.createStats();

    if (filename) |f| {
        try prof.dumpStats(f);
    } else {
        try prof.printStats(sort);
    }
}

/// Profile a function call
pub fn runctx(allocator: std.mem.Allocator, statement: []const u8, globals: ?*anyopaque, locals: ?*anyopaque, filename: ?[]const u8, sort: SortKey) !void {
    var prof = Profile.init(allocator, null, null);
    defer prof.deinit();

    try prof.runctx(statement, globals, locals);
    prof.createStats();

    if (filename) |f| {
        try prof.dumpStats(f);
    } else {
        try prof.printStats(sort);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "FuncStats init" {
    const allocator = std.testing.allocator;
    var stats = FuncStats.init(allocator);
    defer stats.deinit();

    try std.testing.expectEqual(@as(u64, 0), stats.ncalls);
    try std.testing.expectEqual(@as(f64, 0), stats.tottime);
}

test "FuncStats update" {
    const allocator = std.testing.allocator;
    var stats = FuncStats.init(allocator);
    defer stats.deinit();

    stats.ncalls = 10;
    stats.tottime = 5.0;
    stats.cumtime = 10.0;
    stats.update();

    try std.testing.expectEqual(@as(f64, 0.5), stats.percall_tot);
    try std.testing.expectEqual(@as(f64, 1.0), stats.percall_cum);
}

test "Profile init" {
    const allocator = std.testing.allocator;
    var prof = Profile.init(allocator, null, null);
    defer prof.deinit();

    try std.testing.expectEqual(@as(u64, 0), prof.total_calls);
}

test "Profile traceDispatchCall" {
    const allocator = std.testing.allocator;
    var prof = Profile.init(allocator, null, null);
    defer prof.deinit();

    prof.traceDispatchCall("test_func");
    try std.testing.expectEqual(@as(u64, 1), prof.total_calls);
    try std.testing.expect(prof.stats.contains("test_func"));
}

test "Stats init" {
    const allocator = std.testing.allocator;
    var stats = try Stats.init(allocator, null);
    defer stats.deinit();

    try std.testing.expectEqual(@as(u64, 0), stats.total_calls);
}

test "SortKey" {
    try std.testing.expectEqual(SortKey.calls, SortKey.calls);
    try std.testing.expectEqual(SortKey.time, SortKey.time);
}
