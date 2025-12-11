//! Utility functions for profile statistics
//!
//! Provides helper functions for formatting and manipulating profiling data.

const std = @import("std");

// ============================================================================
// Key Generation
// ============================================================================

/// Create a function key from components
pub fn funcKey(allocator: std.mem.Allocator, filename: []const u8, lineno: usize, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{d}({s})", .{ filename, lineno, name });
}

// ============================================================================
// Path Utilities
// ============================================================================

/// Strip common prefix from filenames
pub fn stripPath(filename: []const u8) []const u8 {
    return std.fs.path.basename(filename);
}

// ============================================================================
// Formatting Functions
// ============================================================================

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
