//! Sorting functionality for profile statistics
//!
//! Provides sorting logic for organizing profiling data by various criteria.

const std = @import("std");
const types = @import("types.zig");

// ============================================================================
// Sort Context
// ============================================================================

/// Internal entry type for sorting
pub const Entry = struct {
    key: []const u8,
    value: types.FuncStat,
};

/// Sort context for comparing entries
pub const SortContext = struct {
    keys: []const types.SortKey,

    pub fn lessThan(ctx: @This(), a: Entry, b: Entry) bool {
        for (ctx.keys) |key| {
            const cmp = compareByKey(key, a.value, b.value);
            if (cmp != 0) return cmp < 0;
        }
        // Default: sort by name
        return std.mem.order(u8, a.key, b.key) == .lt;
    }

    fn compareByKey(key: types.SortKey, a: types.FuncStat, b: types.FuncStat) i32 {
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

// ============================================================================
// Sorting Functions
// ============================================================================

/// Sort function stats by cumulative time (for getTopFunctions)
pub fn sortByCumulativeTime(_: void, a: types.FuncStat, b: types.FuncStat) bool {
    return b.cumulative_time < a.cumulative_time;
}
