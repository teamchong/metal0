/// pkgutil/resolver.zig - Module name resolution functionality
/// Handles relative and absolute module name resolution

const std = @import("std");

/// Resolve a relative module name to absolute
pub fn resolve_name(allocator: std.mem.Allocator, name: []const u8, package: ?[]const u8) ![]const u8 {
    if (name.len == 0 or name[0] != '.') {
        // Already absolute
        return try allocator.dupe(u8, name);
    }

    const pkg = package orelse return error.ImportError;

    // Count leading dots
    var dots: usize = 0;
    while (dots < name.len and name[dots] == '.') {
        dots += 1;
    }

    // Find package base (remove 'dots-1' components from end)
    var pkg_parts = std.ArrayList([]const u8).init(allocator);
    defer pkg_parts.deinit();

    var parts_iter = std.mem.splitScalar(u8, pkg, '.');
    while (parts_iter.next()) |part| {
        try pkg_parts.append(part);
    }

    if (dots > pkg_parts.items.len) {
        return error.ImportError;
    }

    // Build result
    var result = std.ArrayList(u8).init(allocator);
    for (pkg_parts.items[0 .. pkg_parts.items.len - (dots - 1)]) |part| {
        if (result.items.len > 0) {
            try result.append('.');
        }
        try result.appendSlice(part);
    }

    if (dots < name.len) {
        if (result.items.len > 0) {
            try result.append('.');
        }
        try result.appendSlice(name[dots..]);
    }

    return result.toOwnedSlice();
}

test "resolve_name absolute" {
    const allocator = std.testing.allocator;
    const result = try resolve_name(allocator, "os.path", null);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("os.path", result);
}

test "resolve_name relative single dot" {
    const allocator = std.testing.allocator;
    const result = try resolve_name(allocator, ".submodule", "package");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("package.submodule", result);
}

test "resolve_name relative double dot" {
    const allocator = std.testing.allocator;
    const result = try resolve_name(allocator, "..sibling", "package.subpackage");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("package.sibling", result);
}

test "resolve_name no package error" {
    const allocator = std.testing.allocator;
    const result = resolve_name(allocator, ".relative", null);
    try std.testing.expectError(error.ImportError, result);
}
