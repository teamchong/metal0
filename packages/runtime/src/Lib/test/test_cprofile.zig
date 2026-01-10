//! test.test_cprofile - cProfile tests
//! CPython Reference: https://docs.python.org/3.12/library/profile.html
//!
//! This module provides tests for the cProfile profiler functionality,
//! which is used to measure execution time and call statistics of Python code.

const std = @import("std");

// ============================================================================
// Profile Statistics Types
// ============================================================================

/// Represents statistics for a single function call
pub const FunctionStats = struct {
    /// Number of calls to this function
    call_count: u64 = 0,
    /// Number of recursive calls
    recursive_calls: u64 = 0,
    /// Total time spent in this function (excluding subcalls)
    total_time_ns: u64 = 0,
    /// Cumulative time (including subcalls)
    cumulative_time_ns: u64 = 0,
    /// Function name
    name: []const u8,
    /// File name where function is defined
    filename: []const u8 = "",
    /// Line number of function definition
    lineno: u32 = 0,

    /// Calculate average time per call
    pub fn avgTimePerCall(self: *const FunctionStats) f64 {
        if (self.call_count == 0) return 0;
        return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.call_count));
    }

    /// Calculate average cumulative time per call
    pub fn avgCumulativeTimePerCall(self: *const FunctionStats) f64 {
        if (self.call_count == 0) return 0;
        return @as(f64, @floatFromInt(self.cumulative_time_ns)) / @as(f64, @floatFromInt(self.call_count));
    }
};

/// Call graph edge representing caller->callee relationship
pub const CallEdge = struct {
    /// Caller function key
    caller_key: []const u8,
    /// Callee function key
    callee_key: []const u8,
    /// Number of calls from caller to callee
    call_count: u64 = 0,
    /// Total time spent in callee when called from this caller
    total_time_ns: u64 = 0,
};

/// Profiler sort key options (matches CPython's pstats.SortKey)
pub const SortKey = enum {
    /// Sort by call count
    calls,
    /// Sort by cumulative time
    cumulative,
    /// Sort by filename
    filename,
    /// Sort by line number
    line,
    /// Sort by function name
    name,
    /// Sort by number of calls (same as calls)
    ncalls,
    /// Sort by primitive call count
    pcalls,
    /// Sort by standard name
    stdname,
    /// Sort by total time
    time,
    /// Sort by total time (same as time)
    tottime,
};

// ============================================================================
// Profile Event Types
// ============================================================================

/// Types of profiler events
pub const ProfileEvent = enum {
    /// Function call event
    call,
    /// Function return event
    @"return",
    /// C function call
    c_call,
    /// C function return
    c_return,
    /// C function exception
    c_exception,
};

/// A single profile event
pub const ProfileEventRecord = struct {
    /// Event type
    event: ProfileEvent,
    /// Timestamp (nanoseconds since profiler start)
    timestamp_ns: u64,
    /// Function name
    function: []const u8,
    /// Filename
    filename: []const u8 = "",
    /// Line number
    lineno: u32 = 0,
    /// Argument info (for call events)
    arg_info: ?[]const u8 = null,
};

// ============================================================================
// Profile Data Structure
// ============================================================================

/// Main profile data structure
pub const ProfileData = struct {
    /// Function statistics indexed by key (filename:lineno:name)
    stats: std.StringHashMap(FunctionStats),
    /// Call graph edges
    call_graph: std.ArrayList(CallEdge),
    /// Total profiling time
    total_time_ns: u64 = 0,
    /// Number of function calls
    total_calls: u64 = 0,
    /// Number of primitive calls (non-recursive)
    primitive_calls: u64 = 0,
    /// Allocator
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .stats = std.StringHashMap(FunctionStats).init(allocator),
            .call_graph = std.ArrayList(CallEdge).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stats.deinit();
        self.call_graph.deinit();
    }

    /// Record a function call
    pub fn recordCall(self: *Self, func_key: []const u8, time_ns: u64, is_recursive: bool) !void {
        const result = try self.stats.getOrPut(func_key);
        if (!result.found_existing) {
            result.value_ptr.* = FunctionStats{ .name = func_key };
        }

        result.value_ptr.call_count += 1;
        result.value_ptr.total_time_ns += time_ns;
        result.value_ptr.cumulative_time_ns += time_ns;

        if (is_recursive) {
            result.value_ptr.recursive_calls += 1;
        }

        self.total_calls += 1;
        if (!is_recursive) {
            self.primitive_calls += 1;
        }
    }

    /// Get sorted statistics
    pub fn getSortedStats(self: *Self, allocator: std.mem.Allocator, sort_key: SortKey) ![]FunctionStats {
        var list = std.ArrayList(FunctionStats).init(allocator);

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            try list.append(entry.value_ptr.*);
        }

        const items = list.items;
        switch (sort_key) {
            .calls, .ncalls => {
                std.mem.sort(FunctionStats, items, {}, struct {
                    fn lessThan(_: void, a: FunctionStats, b: FunctionStats) bool {
                        return a.call_count > b.call_count;
                    }
                }.lessThan);
            },
            .cumulative => {
                std.mem.sort(FunctionStats, items, {}, struct {
                    fn lessThan(_: void, a: FunctionStats, b: FunctionStats) bool {
                        return a.cumulative_time_ns > b.cumulative_time_ns;
                    }
                }.lessThan);
            },
            .time, .tottime => {
                std.mem.sort(FunctionStats, items, {}, struct {
                    fn lessThan(_: void, a: FunctionStats, b: FunctionStats) bool {
                        return a.total_time_ns > b.total_time_ns;
                    }
                }.lessThan);
            },
            .name, .stdname => {
                std.mem.sort(FunctionStats, items, {}, struct {
                    fn lessThan(_: void, a: FunctionStats, b: FunctionStats) bool {
                        return std.mem.lessThan(u8, a.name, b.name);
                    }
                }.lessThan);
            },
            .line => {
                std.mem.sort(FunctionStats, items, {}, struct {
                    fn lessThan(_: void, a: FunctionStats, b: FunctionStats) bool {
                        return a.lineno < b.lineno;
                    }
                }.lessThan);
            },
            .filename => {
                std.mem.sort(FunctionStats, items, {}, struct {
                    fn lessThan(_: void, a: FunctionStats, b: FunctionStats) bool {
                        return std.mem.lessThan(u8, a.filename, b.filename);
                    }
                }.lessThan);
            },
            .pcalls => {
                std.mem.sort(FunctionStats, items, {}, struct {
                    fn lessThan(_: void, a: FunctionStats, b: FunctionStats) bool {
                        return (a.call_count - a.recursive_calls) > (b.call_count - b.recursive_calls);
                    }
                }.lessThan);
            },
        }

        return list.toOwnedSlice();
    }
};

// ============================================================================
// Profiler Context
// ============================================================================

/// Profiler context for tracking function calls
pub const ProfilerContext = struct {
    /// Profile data
    data: ProfileData,
    /// Call stack for tracking current execution
    call_stack: std.ArrayList(CallFrame),
    /// Start time of profiling
    start_time_ns: i128 = 0,
    /// Whether profiler is currently active
    is_active: bool = false,
    /// Event log (optional)
    event_log: ?std.ArrayList(ProfileEventRecord) = null,
    /// Maximum call stack depth observed
    max_depth: u32 = 0,

    const Self = @This();

    /// Call frame on the stack
    pub const CallFrame = struct {
        func_key: []const u8,
        start_time_ns: i128,
        child_time_ns: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .data = ProfileData.init(allocator),
            .call_stack = std.ArrayList(CallFrame).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
        self.call_stack.deinit();
        if (self.event_log) |*log| {
            log.deinit();
        }
    }

    /// Start profiling
    pub fn start(self: *Self) void {
        self.start_time_ns = std.time.nanoTimestamp();
        self.is_active = true;
    }

    /// Stop profiling
    pub fn stop(self: *Self) void {
        if (self.is_active) {
            const end_time = std.time.nanoTimestamp();
            self.data.total_time_ns = @intCast(end_time - self.start_time_ns);
            self.is_active = false;
        }
    }

    /// Record function entry
    pub fn enterFunction(self: *Self, func_key: []const u8) !void {
        if (!self.is_active) return;

        const now = std.time.nanoTimestamp();
        try self.call_stack.append(.{
            .func_key = func_key,
            .start_time_ns = now,
        });

        if (self.call_stack.items.len > self.max_depth) {
            self.max_depth = @intCast(self.call_stack.items.len);
        }
    }

    /// Record function exit
    pub fn exitFunction(self: *Self) !void {
        if (!self.is_active or self.call_stack.items.len == 0) return;

        const now = std.time.nanoTimestamp();
        const frame = self.call_stack.pop();

        const total_time: u64 = @intCast(now - frame.start_time_ns);
        const own_time = total_time - frame.child_time_ns;

        // Check if recursive
        var is_recursive = false;
        for (self.call_stack.items) |f| {
            if (std.mem.eql(u8, f.func_key, frame.func_key)) {
                is_recursive = true;
                break;
            }
        }

        // Update parent's child time
        if (self.call_stack.items.len > 0) {
            self.call_stack.items[self.call_stack.items.len - 1].child_time_ns += total_time;
        }

        try self.data.recordCall(frame.func_key, own_time, is_recursive);
    }

    /// Get current call depth
    pub fn getDepth(self: *const Self) u32 {
        return @intCast(self.call_stack.items.len);
    }
};

// ============================================================================
// Output Formatting
// ============================================================================

/// Format profile statistics as a string
pub fn formatStats(allocator: std.mem.Allocator, data: *ProfileData, sort_key: SortKey, limit: ?u32) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    // Header
    try writer.print("         {d} function calls", .{data.total_calls});
    if (data.primitive_calls != data.total_calls) {
        try writer.print(" ({d} primitive calls)", .{data.primitive_calls});
    }
    try writer.print(" in {d:.6} seconds\n\n", .{@as(f64, @floatFromInt(data.total_time_ns)) / 1_000_000_000.0});

    // Column headers
    try writer.writeAll("   ncalls  tottime  percall  cumtime  percall filename:lineno(function)\n");

    // Get sorted stats
    const sorted = try data.getSortedStats(allocator, sort_key);
    defer allocator.free(sorted);

    const count = if (limit) |l| @min(l, @as(u32, @intCast(sorted.len))) else @as(u32, @intCast(sorted.len));

    for (sorted[0..count]) |stat| {
        // Format call count
        if (stat.recursive_calls > 0) {
            try writer.print("{d}/{d}", .{ stat.call_count, stat.call_count - stat.recursive_calls });
        } else {
            try writer.print("{d:8}", .{stat.call_count});
        }

        // Format times
        const tottime = @as(f64, @floatFromInt(stat.total_time_ns)) / 1_000_000_000.0;
        const cumtime = @as(f64, @floatFromInt(stat.cumulative_time_ns)) / 1_000_000_000.0;
        const percall_tot = stat.avgTimePerCall() / 1_000_000_000.0;
        const percall_cum = stat.avgCumulativeTimePerCall() / 1_000_000_000.0;

        try writer.print("  {d:7.3}  {d:7.3}  {d:7.3}  {d:7.3}  ", .{
            tottime,
            percall_tot,
            cumtime,
            percall_cum,
        });

        // Format location
        if (stat.filename.len > 0) {
            try writer.print("{s}:{d}({s})\n", .{ stat.filename, stat.lineno, stat.name });
        } else {
            try writer.print("{s}\n", .{stat.name});
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Test Helpers
// ============================================================================

/// Simulate a profiled function call
pub fn simulateCall(ctx: *ProfilerContext, func_name: []const u8, duration_ns: u64) !void {
    try ctx.enterFunction(func_name);

    // Simulate work
    std.time.sleep(duration_ns);

    try ctx.exitFunction();
}

/// Create a test profile with sample data
pub fn createTestProfile(allocator: std.mem.Allocator) !*ProfilerContext {
    const ctx = try allocator.create(ProfilerContext);
    ctx.* = ProfilerContext.init(allocator);

    // Add some sample function stats
    try ctx.data.recordCall("main", 1000000, false);
    try ctx.data.recordCall("process", 500000, false);
    try ctx.data.recordCall("process", 600000, false);
    try ctx.data.recordCall("helper", 100000, false);
    try ctx.data.recordCall("recursive", 200000, false);
    try ctx.data.recordCall("recursive", 150000, true);
    try ctx.data.recordCall("recursive", 100000, true);

    return ctx;
}

// ============================================================================
// Test Cases
// ============================================================================

/// Test case structure
pub const ProfileTestCase = struct {
    name: []const u8,
    functions: []const FunctionCall,
    expected_total_calls: u64,
    expected_primitive_calls: u64,

    pub const FunctionCall = struct {
        name: []const u8,
        duration_ns: u64,
        is_recursive: bool = false,
    };
};

/// Standard test cases
pub const standard_test_cases = [_]ProfileTestCase{
    .{
        .name = "single_function",
        .functions = &[_]ProfileTestCase.FunctionCall{
            .{ .name = "main", .duration_ns = 1000000 },
        },
        .expected_total_calls = 1,
        .expected_primitive_calls = 1,
    },
    .{
        .name = "multiple_functions",
        .functions = &[_]ProfileTestCase.FunctionCall{
            .{ .name = "main", .duration_ns = 1000000 },
            .{ .name = "foo", .duration_ns = 500000 },
            .{ .name = "bar", .duration_ns = 300000 },
        },
        .expected_total_calls = 3,
        .expected_primitive_calls = 3,
    },
    .{
        .name = "recursive_calls",
        .functions = &[_]ProfileTestCase.FunctionCall{
            .{ .name = "recurse", .duration_ns = 100000 },
            .{ .name = "recurse", .duration_ns = 80000, .is_recursive = true },
            .{ .name = "recurse", .duration_ns = 60000, .is_recursive = true },
        },
        .expected_total_calls = 3,
        .expected_primitive_calls = 1,
    },
};

// ============================================================================
// Unit Tests
// ============================================================================

test "FunctionStats avgTimePerCall" {
    const stats = FunctionStats{
        .name = "test",
        .call_count = 10,
        .total_time_ns = 1000,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 100.0), stats.avgTimePerCall(), 0.001);
}

test "FunctionStats avgCumulativeTimePerCall" {
    const stats = FunctionStats{
        .name = "test",
        .call_count = 5,
        .cumulative_time_ns = 500,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 100.0), stats.avgCumulativeTimePerCall(), 0.001);
}

test "ProfileData init and deinit" {
    const allocator = std.testing.allocator;
    var data = ProfileData.init(allocator);
    defer data.deinit();

    try std.testing.expectEqual(@as(u64, 0), data.total_calls);
    try std.testing.expectEqual(@as(u64, 0), data.primitive_calls);
}

test "ProfileData recordCall" {
    const allocator = std.testing.allocator;
    var data = ProfileData.init(allocator);
    defer data.deinit();

    try data.recordCall("func1", 1000, false);
    try data.recordCall("func1", 2000, false);
    try data.recordCall("func2", 500, false);

    try std.testing.expectEqual(@as(u64, 3), data.total_calls);
    try std.testing.expectEqual(@as(u64, 3), data.primitive_calls);

    const func1_stats = data.stats.get("func1").?;
    try std.testing.expectEqual(@as(u64, 2), func1_stats.call_count);
    try std.testing.expectEqual(@as(u64, 3000), func1_stats.total_time_ns);
}

test "ProfileData recordCall recursive" {
    const allocator = std.testing.allocator;
    var data = ProfileData.init(allocator);
    defer data.deinit();

    try data.recordCall("recurse", 1000, false);
    try data.recordCall("recurse", 800, true);
    try data.recordCall("recurse", 600, true);

    try std.testing.expectEqual(@as(u64, 3), data.total_calls);
    try std.testing.expectEqual(@as(u64, 1), data.primitive_calls);

    const stats = data.stats.get("recurse").?;
    try std.testing.expectEqual(@as(u64, 3), stats.call_count);
    try std.testing.expectEqual(@as(u64, 2), stats.recursive_calls);
}

test "ProfilerContext init and deinit" {
    const allocator = std.testing.allocator;
    var ctx = ProfilerContext.init(allocator);
    defer ctx.deinit();

    try std.testing.expect(!ctx.is_active);
    try std.testing.expectEqual(@as(u32, 0), ctx.getDepth());
}

test "ProfilerContext start and stop" {
    const allocator = std.testing.allocator;
    var ctx = ProfilerContext.init(allocator);
    defer ctx.deinit();

    ctx.start();
    try std.testing.expect(ctx.is_active);

    ctx.stop();
    try std.testing.expect(!ctx.is_active);
    try std.testing.expect(ctx.data.total_time_ns > 0);
}

test "ProfilerContext enterFunction and exitFunction" {
    const allocator = std.testing.allocator;
    var ctx = ProfilerContext.init(allocator);
    defer ctx.deinit();

    ctx.start();

    try ctx.enterFunction("main");
    try std.testing.expectEqual(@as(u32, 1), ctx.getDepth());

    try ctx.enterFunction("helper");
    try std.testing.expectEqual(@as(u32, 2), ctx.getDepth());

    try ctx.exitFunction();
    try std.testing.expectEqual(@as(u32, 1), ctx.getDepth());

    try ctx.exitFunction();
    try std.testing.expectEqual(@as(u32, 0), ctx.getDepth());

    ctx.stop();

    try std.testing.expectEqual(@as(u64, 2), ctx.data.total_calls);
}

test "ProfilerContext max_depth tracking" {
    const allocator = std.testing.allocator;
    var ctx = ProfilerContext.init(allocator);
    defer ctx.deinit();

    ctx.start();

    try ctx.enterFunction("a");
    try ctx.enterFunction("b");
    try ctx.enterFunction("c");
    try std.testing.expectEqual(@as(u32, 3), ctx.max_depth);

    try ctx.exitFunction();
    try ctx.exitFunction();
    try ctx.exitFunction();

    try std.testing.expectEqual(@as(u32, 3), ctx.max_depth);

    ctx.stop();
}

test "getSortedStats by calls" {
    const allocator = std.testing.allocator;
    var data = ProfileData.init(allocator);
    defer data.deinit();

    try data.recordCall("few_calls", 1000, false);
    try data.recordCall("many_calls", 500, false);
    try data.recordCall("many_calls", 500, false);
    try data.recordCall("many_calls", 500, false);
    try data.recordCall("medium_calls", 700, false);
    try data.recordCall("medium_calls", 700, false);

    const sorted = try data.getSortedStats(allocator, .calls);
    defer allocator.free(sorted);

    try std.testing.expectEqual(@as(usize, 3), sorted.len);
    try std.testing.expectEqualStrings("many_calls", sorted[0].name);
    try std.testing.expectEqualStrings("medium_calls", sorted[1].name);
    try std.testing.expectEqualStrings("few_calls", sorted[2].name);
}

test "getSortedStats by time" {
    const allocator = std.testing.allocator;
    var data = ProfileData.init(allocator);
    defer data.deinit();

    try data.recordCall("fast", 100, false);
    try data.recordCall("slow", 1000, false);
    try data.recordCall("medium", 500, false);

    const sorted = try data.getSortedStats(allocator, .time);
    defer allocator.free(sorted);

    try std.testing.expectEqual(@as(usize, 3), sorted.len);
    try std.testing.expectEqualStrings("slow", sorted[0].name);
    try std.testing.expectEqualStrings("medium", sorted[1].name);
    try std.testing.expectEqualStrings("fast", sorted[2].name);
}

test "createTestProfile" {
    const allocator = std.testing.allocator;
    const ctx = try createTestProfile(allocator);
    defer {
        ctx.deinit();
        allocator.destroy(ctx);
    }

    try std.testing.expect(ctx.data.total_calls > 0);
    try std.testing.expect(ctx.data.stats.count() > 0);
}
