/// Utility functions for 're' module: escape, purge
const std = @import("std");
const runtime = @import("../../runtime.zig");

/// Python-compatible escape() function
/// Usage: escaped = re.escape("hello.world")
/// Escapes special regex characters
pub fn escape(allocator: std.mem.Allocator, pattern: []const u8) !*runtime.PyObject {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    const special = "\\^$.|?*+()[]{}";
    for (pattern) |c| {
        for (special) |s| {
            if (c == s) {
                try result.append(allocator, '\\');
                break;
            }
        }
        try result.append(allocator, c);
    }

    const owned = try result.toOwnedSlice(allocator);
    return try runtime.PyString.createOwned(allocator, owned);
}

/// Python-compatible purge() function
/// Usage: re.purge()
/// Clears the regex cache (no-op in our implementation)
pub fn purge() void {
    // No-op - we don't have a global cache
}
