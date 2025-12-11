//! Profile statistics types
//!
//! Defines the core data structures for profiling statistics including
//! per-function stats and sort keys.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Profile Statistics Types
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

test "SortKey" {
    try std.testing.expectEqual(SortKey.calls, SortKey.calls);
    try std.testing.expectEqual(SortKey.time, SortKey.time);
}
