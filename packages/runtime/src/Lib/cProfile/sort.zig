//! Sort key definitions
//!
//! Defines how profile statistics can be sorted.

const std = @import("std");

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
// Tests
// ============================================================================

test "SortKey enum" {
    try std.testing.expect(@intFromEnum(SortKey.calls) == 0);
    try std.testing.expect(@intFromEnum(SortKey.cumulative) == 1);
    try std.testing.expect(@intFromEnum(SortKey.time) == 8);
}
