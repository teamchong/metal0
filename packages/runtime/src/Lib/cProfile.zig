//! CPython source: Lib/cProfile.py
//!
//! Provides a deterministic profiler for Python programs.
//!
//! Mirrors: CPython Lib/cProfile.py

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Profile Entry
// ============================================================================

/// Statistics for a single function
pub const ProfileEntry = struct {
    /// Number of calls
    ncalls: u64 = 0,
    /// Number of recursive calls
    nrcalls: u64 = 0,
    /// Total time in this function
    tottime: f64 = 0.0,
    /// Cumulative time (including subcalls)
    cumtime: f64 = 0.0,
    /// Function name
    name: []const u8,
    /// File name
    filename: []const u8,
    /// Line number
    lineno: usize,
    /// Callers: maps caller name -> call count
    callers: hashmap_helper.StringHashMap(u64) = undefined,
    /// Callees: maps callee name -> call count
    callees: hashmap_helper.StringHashMap(u64) = undefined,
    allocator: ?std.mem.Allocator = null,

    pub fn init(name: []const u8, filename: []const u8, lineno: usize) ProfileEntry {
        return .{
            .name = name,
            .filename = filename,
            .lineno = lineno,
            .callers = undefined,
            .callees = undefined,
            .allocator = null,
        };
    }

    pub fn initWithAllocator(allocator: std.mem.Allocator, name: []const u8, filename: []const u8, lineno: usize) ProfileEntry {
        return .{
            .name = name,
            .filename = filename,
            .lineno = lineno,
            .callers = hashmap_helper.StringHashMap(u64).init(allocator),
            .callees = hashmap_helper.StringHashMap(u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProfileEntry) void {
        if (self.allocator != null) {
            self.callers.deinit();
            self.callees.deinit();
        }
    }

    /// Record a call from caller
    pub fn recordCaller(self: *ProfileEntry, caller_name: []const u8) void {
        if (self.allocator == null) return;
        const entry = self.callers.getOrPut(caller_name) catch return;
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    /// Record a call to callee
    pub fn recordCallee(self: *ProfileEntry, callee_name: []const u8) void {
        if (self.allocator == null) return;
        const entry = self.callees.getOrPut(callee_name) catch return;
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    /// Get per-call time
    pub fn percallTot(self: *const ProfileEntry) f64 {
        if (self.ncalls == 0) return 0.0;
        return self.tottime / @as(f64, @floatFromInt(self.ncalls));
    }

    /// Get per-call cumulative time
    pub fn percallCum(self: *const ProfileEntry) f64 {
        if (self.ncalls == 0) return 0.0;
        return self.cumtime / @as(f64, @floatFromInt(self.ncalls));
    }
};

// ============================================================================
// Call Stack Entry
// ============================================================================

/// Entry in the call stack for tracking nested calls
const CallStackEntry = struct {
    name: []const u8,
    start_time: i128,
    subcall_time: f64,
};

// ============================================================================
// Profile
// ============================================================================

/// Deterministic profiler
pub const Profile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Profile statistics by function key
    stats: hashmap_helper.StringHashMap(ProfileEntry),
    /// Call stack for tracking nested calls
    call_stack: std.ArrayList(CallStackEntry),
    /// Whether profiler is enabled
    enabled: bool = false,
    /// Total time spent profiling
    total_time: f64 = 0.0,
    /// Timer function
    timer: *const fn () i128,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .stats = hashmap_helper.StringHashMap(ProfileEntry).init(allocator),
            .call_stack = std.ArrayList(CallStackEntry).init(allocator),
            .timer = defaultTimer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stats.deinit();
        self.call_stack.deinit();
    }

    fn defaultTimer() i128 {
        return std.time.nanoTimestamp();
    }

    /// Enable the profiler
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// Disable the profiler
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }

    /// Clear all statistics
    pub fn clear(self: *Self) void {
        self.stats.clearRetainingCapacity();
        self.call_stack.clearRetainingCapacity();
        self.total_time = 0.0;
    }

    /// Record function entry
    pub fn callEnter(self: *Self, name: []const u8) void {
        if (!self.enabled) return;

        const now = self.timer();
        self.call_stack.append(.{
            .name = name,
            .start_time = now,
            .subcall_time = 0.0,
        }) catch return;
    }

    /// Record function exit
    pub fn callExit(self: *Self, name: []const u8, filename: []const u8, lineno: usize) void {
        if (!self.enabled) return;

        const now = self.timer();

        // Pop from call stack
        if (self.call_stack.items.len == 0) return;
        const entry = self.call_stack.pop();

        const elapsed_ns = now - entry.start_time;
        const elapsed = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const own_time = elapsed - entry.subcall_time;

        // Update stats
        const key = name;
        if (self.stats.getPtr(key)) |stat| {
            stat.ncalls += 1;
            stat.tottime += own_time;
            stat.cumtime += elapsed;
        } else {
            var new_entry = ProfileEntry.init(name, filename, lineno);
            new_entry.ncalls = 1;
            new_entry.tottime = own_time;
            new_entry.cumtime = elapsed;
            self.stats.put(key, new_entry) catch return;
        }

        // Update parent's subcall time
        if (self.call_stack.items.len > 0) {
            self.call_stack.items[self.call_stack.items.len - 1].subcall_time += elapsed;
        }

        self.total_time += own_time;
    }

    /// High-level method to record a function call
    /// Combines callEnter with caller/callee tracking
    pub fn recordCall(self: *Self, name: []const u8, filename: []const u8, lineno: usize) !void {
        if (!self.enabled) return;

        // Track caller->callee relationship
        if (self.call_stack.items.len > 0) {
            const caller_name = self.call_stack.items[self.call_stack.items.len - 1].name;
            // Get or create callee entry to record caller
            const callee_result = try self.stats.getOrPut(name);
            if (!callee_result.found_existing) {
                callee_result.value_ptr.* = ProfileEntry.initWithAllocator(self.allocator, name, filename, lineno);
            }
            callee_result.value_ptr.recordCaller(caller_name);

            // Get or create caller entry to record callee
            if (self.stats.getPtr(caller_name)) |caller_entry| {
                caller_entry.recordCallee(name);
            }
        }

        self.callEnter(name);
    }

    /// High-level method to record a function return
    /// Combines callExit with any additional tracking
    pub fn recordReturn(self: *Self, name: []const u8) !void {
        if (!self.enabled) return;

        // Find the filename/lineno from the call stack or stats
        var filename: []const u8 = "<unknown>";
        var lineno: usize = 0;
        if (self.stats.get(name)) |entry| {
            filename = entry.filename;
            lineno = entry.lineno;
        }

        self.callExit(name, filename, lineno);
    }

    /// Create stats summary
    pub fn createStats(self: *Self) Stats {
        return Stats.init(self.allocator, &self.stats);
    }

    /// Print statistics
    pub fn printStats(self: *Self, sort: SortKey) !void {
        var stats = self.createStats();
        try stats.sortStats(sort);
        try stats.printStats();
    }

    /// Dump stats to file
    pub fn dumpStats(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var writer = file.writer();
        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            try writer.print("{s},{d},{d:.6},{d:.6}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.ncalls,
                entry.value_ptr.tottime,
                entry.value_ptr.cumtime,
            });
        }
    }

    /// Run a callable under the profiler
    pub fn runcall(self: *Self, comptime func: anytype, args: anytype) @TypeOf(@call(.auto, func, args)) {
        self.enable();
        defer self.disable();
        return @call(.auto, func, args);
    }
};

// ============================================================================
// Sort Keys
// ============================================================================

/// How to sort profile statistics
pub const SortKey = enum {
    /// Sort by call count
    calls,
    /// Sort by cumulative time
    cumulative,
    /// Sort by file name
    filename,
    /// Sort by line number
    line,
    /// Sort by function name
    name,
    /// Sort by number of calls
    ncalls,
    /// Sort by per-call cumulative time
    pcalls,
    /// Sort by standard name
    stdname,
    /// Sort by total time
    time,
    /// Sort by total time
    tottime,
};

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
    pub fn printCallers(self: *Self, name: []const u8) !void {
        const stdout = std.io.getStdOut().writer();

        // Find the entry for this function
        const entry = self.stats.get(name) orelse {
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
    pub fn printCallees(self: *Self, name: []const u8) !void {
        const stdout = std.io.getStdOut().writer();

        // Find the entry for this function
        const entry = self.stats.get(name) orelse {
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
// Module Functions
// ============================================================================

/// Run a statement under the profiler
/// In AOT context, this records the statement as a profiled execution
pub fn run(statement: []const u8, filename: ?[]const u8, sort: ?SortKey) !void {
    const allocator = allocator_helper.fast_allocator;
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    profiler.enable();

    // Record the statement as a function call
    const fname = filename orelse "<string>";
    try profiler.recordCall(statement, fname, 1);

    // In AOT, actual execution happens in compiled code
    // This tracks it for profiling purposes

    try profiler.recordReturn(statement);

    profiler.disable();

    // Print stats with requested sort key
    try profiler.printStats(sort orelse .cumulative);
}

/// Run a main module under the profiler
pub fn runMain(allocator: std.mem.Allocator) !void {
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    profiler.enable();

    // In AOT context, the main module execution is compiled
    // This serves as the profiler entry point
    try profiler.recordCall("<module>", "__main__", 1);

    // Actual execution happens via compiled code
    // Generated code should call profiler.recordCall/recordReturn

    try profiler.recordReturn("<module>");

    profiler.disable();

    try profiler.printStats(.cumulative);
}

/// Create a label for a function
pub fn label(code: anytype) []const u8 {
    _ = code;
    return "<function>";
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the cProfile module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "ProfileEntry init" {
    const entry = ProfileEntry.init("test", "test.py", 10);
    try std.testing.expectEqualStrings("test", entry.name);
    try std.testing.expectEqualStrings("test.py", entry.filename);
    try std.testing.expectEqual(@as(usize, 10), entry.lineno);
    try std.testing.expectEqual(@as(u64, 0), entry.ncalls);
}

test "ProfileEntry percall" {
    var entry = ProfileEntry.init("test", "test.py", 10);
    entry.ncalls = 10;
    entry.tottime = 1.0;
    entry.cumtime = 2.0;

    try std.testing.expectApproxEqAbs(@as(f64, 0.1), entry.percallTot(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), entry.percallCum(), 0.001);
}

test "ProfileEntry percall zero calls" {
    const entry = ProfileEntry.init("test", "test.py", 10);
    try std.testing.expectEqual(@as(f64, 0.0), entry.percallTot());
    try std.testing.expectEqual(@as(f64, 0.0), entry.percallCum());
}

test "Profile init" {
    const allocator = std.testing.allocator;
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    try std.testing.expect(!profiler.enabled);
    try std.testing.expectEqual(@as(f64, 0.0), profiler.total_time);
}

test "Profile enable/disable" {
    const allocator = std.testing.allocator;
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    try std.testing.expect(!profiler.enabled);
    profiler.enable();
    try std.testing.expect(profiler.enabled);
    profiler.disable();
    try std.testing.expect(!profiler.enabled);
}

test "Profile clear" {
    const allocator = std.testing.allocator;
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    profiler.total_time = 1.0;
    profiler.clear();
    try std.testing.expectEqual(@as(f64, 0.0), profiler.total_time);
}

test "SortKey enum" {
    try std.testing.expect(@intFromEnum(SortKey.calls) == 0);
    try std.testing.expect(@intFromEnum(SortKey.cumulative) == 1);
    try std.testing.expect(@intFromEnum(SortKey.time) == 8);
}

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
