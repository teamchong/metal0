//! Helper functions for debugger operations.
//!
//! Provides utility functions:
//! - shouldTrace: Check if code should be traced (not in skip set)
//! - canonic: Get canonical filename (absolute path)
//! - effectiveSkip: Expand module patterns into skip set

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if code should be traced (not in skip set)
pub fn shouldTrace(skip: ?hashmap_helper.StringHashMap(void), name: []const u8) bool {
    if (skip) |s| {
        if (s.contains(name)) return false;
    }
    return true;
}

/// Get canonical filename
pub fn canonic(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    // Normalize the path
    if (std.fs.path.isAbsolute(filename)) {
        return allocator.dupe(u8, filename);
    }

    // Make it absolute
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &buf) catch return allocator.dupe(u8, filename);
    return std.fs.path.join(allocator, &.{ cwd, filename });
}

/// Effective skip set - expands module patterns
pub fn effectiveSkip(allocator: std.mem.Allocator, skip: []const []const u8) !hashmap_helper.StringHashMap(void) {
    var result = hashmap_helper.StringHashMap(void).init(allocator);
    for (skip) |name| {
        try result.put(name, {});
    }
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "shouldTrace" {
    const allocator = std.testing.allocator;

    // No skip set
    try std.testing.expect(shouldTrace(null, "anything"));

    // With skip set
    var skip = hashmap_helper.StringHashMap(void).init(allocator);
    defer skip.deinit();
    try skip.put("skip_me", {});

    try std.testing.expect(!shouldTrace(skip, "skip_me"));
    try std.testing.expect(shouldTrace(skip, "trace_me"));
}
