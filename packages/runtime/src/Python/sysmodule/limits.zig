/// limits - Recursion, Threading, and Conversion Limits
/// Functions to get/set system limits

const std = @import("std");
const config = @import("config.zig");

// ============================================================================
// Recursion Limits
// ============================================================================

/// Get the recursion limit
/// Mirrors: sys.getrecursionlimit()
pub fn getrecursionlimit() u32 {
    return config.recursion_limit;
}

/// Set the recursion limit
/// Mirrors: sys.setrecursionlimit()
pub fn setrecursionlimit(limit: u32) !void {
    if (limit < 1) {
        return error.ValueError;
    }
    config.recursion_limit = limit;
}

// ============================================================================
// Thread Switch Interval
// ============================================================================

/// Get the thread switch interval
/// Mirrors: sys.getswitchinterval()
pub fn getswitchinterval() f64 {
    return config.switch_interval;
}

/// Set the thread switch interval
/// Mirrors: sys.setswitchinterval()
pub fn setswitchinterval(interval: f64) !void {
    if (interval <= 0) {
        return error.ValueError;
    }
    config.switch_interval = interval;
}

// ============================================================================
// Int/String Conversion Limits
// ============================================================================

/// Get the maximum number of digits for int/str conversions
/// Mirrors: sys.get_int_max_str_digits()
pub fn get_int_max_str_digits(_: anytype) !i64 {
    return config.int_max_str_digits;
}

/// Set the maximum number of digits for int/str conversions
/// Mirrors: sys.set_int_max_str_digits()
pub fn set_int_max_str_digits(_: anytype, limit: i64) !void {
    if (limit != 0 and limit < 640) {
        return error.ValueError; // CPython minimum is 640
    }
    config.int_max_str_digits = limit;
}

// ============================================================================
// Tests
// ============================================================================

test "recursion limit" {
    try std.testing.expectEqual(@as(u32, 1000), getrecursionlimit());
    try setrecursionlimit(2000);
    try std.testing.expectEqual(@as(u32, 2000), getrecursionlimit());
    config.recursion_limit = 1000; // Reset
}

test "int max str digits" {
    try std.testing.expectEqual(@as(i64, 4300), try get_int_max_str_digits(.{}));
    try set_int_max_str_digits(.{}, 5000);
    try std.testing.expectEqual(@as(i64, 5000), try get_int_max_str_digits(.{}));

    // Test minimum limit
    const result = set_int_max_str_digits(.{}, 100);
    try std.testing.expectError(error.ValueError, result);

    config.int_max_str_digits = 4300; // Reset
}
