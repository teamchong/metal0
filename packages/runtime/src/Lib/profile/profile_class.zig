//! Deterministic profiler implementation
//!
//! Provides the main Profile class for deterministic profiling of Python programs.
//! Tracks function calls, timing, and generates statistics.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

const FuncStats = types.FuncStats;
const SortKey = types.SortKey;

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

        // Sort based on sort key
        const SortContext = struct {
            key: SortKey,
        };
        const ctx = SortContext{ .key = sort };

        std.mem.sort(@TypeOf(entries.items[0]), entries.items, ctx, struct {
            fn lessThan(c: SortContext, a: @TypeOf(entries.items[0]), b: @TypeOf(entries.items[0])) bool {
                return switch (c.key) {
                    .calls => a.stat.ncalls < b.stat.ncalls,
                    .cumulative => a.stat.cumtime < b.stat.cumtime,
                    .time => a.stat.tottime < b.stat.tottime,
                    .name => std.mem.lessThan(u8, a.key, b.key),
                    else => a.stat.cumtime < b.stat.cumtime,
                };
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

// ============================================================================
// Tests
// ============================================================================

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
