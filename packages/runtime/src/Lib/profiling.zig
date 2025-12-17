//! Python profiling support module
//!
//! Provides profiling utilities and helpers.
//!
//! Internal module for profiling support.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const ProfilingError = error{
    NotRunning,
    AlreadyRunning,
    InvalidTimer,
    OutOfMemory,
};

// ============================================================================
// Timer
// ============================================================================

/// High-resolution timer for profiling
pub const Timer = struct {
    const Self = @This();

    start_time: i64 = 0,
    accumulated: i64 = 0,
    running: bool = false,

    pub fn init() Self {
        return Self{};
    }

    /// Start the timer
    pub fn start(self: *Self) void {
        if (!self.running) {
            self.start_time = std.time.nanoTimestamp();
            self.running = true;
        }
    }

    /// Stop the timer
    pub fn stop(self: *Self) void {
        if (self.running) {
            const now = std.time.nanoTimestamp();
            self.accumulated += now - self.start_time;
            self.running = false;
        }
    }

    /// Reset the timer
    pub fn reset(self: *Self) void {
        self.start_time = 0;
        self.accumulated = 0;
        self.running = false;
    }

    /// Get elapsed time in nanoseconds
    pub fn elapsed(self: *const Self) i64 {
        if (self.running) {
            const now = std.time.nanoTimestamp();
            return self.accumulated + (now - self.start_time);
        }
        return self.accumulated;
    }

    /// Get elapsed time in seconds
    pub fn elapsedSeconds(self: *const Self) f64 {
        return @as(f64, @floatFromInt(self.elapsed())) / @as(f64, std.time.ns_per_s);
    }
};

// ============================================================================
// FunctionStats
// ============================================================================

/// Statistics for a single function
pub const FunctionStats = struct {
    /// Number of calls
    ncalls: u64 = 0,
    /// Total time spent in function
    tottime: i64 = 0,
    /// Time per call
    percall: f64 = 0,
    /// Cumulative time (including subcalls)
    cumtime: i64 = 0,
    /// Cumulative time per call
    cumtime_percall: f64 = 0,
    /// Function name
    name: []const u8 = "",
    /// File name
    filename: []const u8 = "",
    /// Line number
    lineno: u32 = 0,

    /// Update averages
    pub fn updateAverages(self: *FunctionStats) void {
        if (self.ncalls > 0) {
            self.percall = @as(f64, @floatFromInt(self.tottime)) / @as(f64, @floatFromInt(self.ncalls));
            self.cumtime_percall = @as(f64, @floatFromInt(self.cumtime)) / @as(f64, @floatFromInt(self.ncalls));
        }
    }
};

// ============================================================================
// Profiler
// ============================================================================

/// Simple function profiler
pub const Profiler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stats: hashmap_helper.StringHashMap(FunctionStats),
    running: bool = false,
    timer: Timer = Timer.init(),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .stats = hashmap_helper.StringHashMap(FunctionStats).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stats.deinit();
    }

    /// Start profiling
    pub fn enable(self: *Self) !void {
        if (self.running) return error.AlreadyRunning;
        self.running = true;
        self.timer.start();
    }

    /// Stop profiling
    pub fn disable(self: *Self) void {
        if (!self.running) return;
        self.timer.stop();
        self.running = false;
    }

    /// Clear all statistics
    pub fn clear(self: *Self) void {
        self.stats.clearAndFree();
        self.timer.reset();
    }

    /// Record a function call
    pub fn recordCall(self: *Self, name: []const u8, time: i64) !void {
        const result = try self.stats.getOrPut(name);
        if (!result.found_existing) {
            result.value_ptr.* = FunctionStats{ .name = name };
        }
        result.value_ptr.ncalls += 1;
        result.value_ptr.tottime += time;
        result.value_ptr.cumtime += time;
        result.value_ptr.updateAverages();
    }

    /// Get statistics
    pub fn getStats(self: *const Self) []const FunctionStats {
        var result: std.ArrayList(FunctionStats) = .{};
        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            result.append(self.allocator, entry.value_ptr.*) catch unreachable;
        }
        return result.items;
    }

    /// Print statistics
    pub fn printStats(self: *const Self) void {
        const stdout = std.io.getStdOut().writer();

        stdout.print("\n{s:>10} {s:>10} {s:>10} {s:>10} {s}\n", .{
            "ncalls", "tottime", "percall", "cumtime", "function",
        }) catch {};
        stdout.print("{s:->10} {s:->10} {s:->10} {s:->10} {s:-<20}\n", .{
            "", "", "", "", "",
        }) catch {};

        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            const s = entry.value_ptr;
            stdout.print("{d:>10} {d:>10.6} {d:>10.6} {d:>10.6} {s}\n", .{
                s.ncalls,
                @as(f64, @floatFromInt(s.tottime)) / std.time.ns_per_s,
                s.percall / std.time.ns_per_s,
                @as(f64, @floatFromInt(s.cumtime)) / std.time.ns_per_s,
                s.name,
            }) catch {};
        }
    }
};

// ============================================================================
// Context Manager
// ============================================================================

/// Profile context for timing a code block
pub const ProfileContext = struct {
    name: []const u8,
    timer: Timer,

    pub fn init(name: []const u8) ProfileContext {
        var ctx = ProfileContext{
            .name = name,
            .timer = Timer.init(),
        };
        ctx.timer.start();
        return ctx;
    }

    pub fn finish(self: *ProfileContext) i64 {
        self.timer.stop();
        return self.timer.elapsed();
    }
};

// ============================================================================
// Module State
// ============================================================================

var global_profiler: ?*Profiler = null;
var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    if (global_profiler) |p| {
        p.disable();
        p.deinit();
    }
    global_profiler = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Timer basic" {
    var timer = Timer.init();
    try std.testing.expect(!timer.running);

    timer.start();
    try std.testing.expect(timer.running);

    std.Thread.sleep(1_000_000); // 1ms

    timer.stop();
    try std.testing.expect(!timer.running);
    try std.testing.expect(timer.elapsed() > 0);
}

test "Timer reset" {
    var timer = Timer.init();
    timer.start();
    std.Thread.sleep(1_000_000);
    timer.stop();

    try std.testing.expect(timer.elapsed() > 0);

    timer.reset();
    try std.testing.expectEqual(@as(i64, 0), timer.elapsed());
}

test "FunctionStats updateAverages" {
    var stats = FunctionStats{
        .ncalls = 10,
        .tottime = 1000,
        .cumtime = 2000,
    };
    stats.updateAverages();

    try std.testing.expectEqual(@as(f64, 100.0), stats.percall);
    try std.testing.expectEqual(@as(f64, 200.0), stats.cumtime_percall);
}

test "Profiler init" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try std.testing.expect(!profiler.running);
}

test "Profiler enable disable" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.enable();
    try std.testing.expect(profiler.running);

    profiler.disable();
    try std.testing.expect(!profiler.running);
}

test "Profiler recordCall" {
    const allocator = std.testing.allocator;
    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    try profiler.recordCall("test_func", 1000);
    try profiler.recordCall("test_func", 2000);

    const stats = profiler.stats.get("test_func");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 2), stats.?.ncalls);
    try std.testing.expectEqual(@as(i64, 3000), stats.?.tottime);
}

test "ProfileContext" {
    var ctx = ProfileContext.init("test");
    std.Thread.sleep(1_000_000);
    const elapsed = ctx.finish();

    try std.testing.expect(elapsed > 0);
}
