/// paths - Module Search Path Management
/// Handles sys.path and installation prefixes

const std = @import("std");

// ============================================================================
// Path Storage
// ============================================================================

/// Module search path (initialized at runtime)
threadlocal var path_storage: [256][]const u8 = undefined;
threadlocal var path_len: usize = 0;

// ============================================================================
// Installation Prefixes
// ============================================================================

/// Prefix for installed files
pub const prefix: []const u8 = "/usr/local";

/// Exec prefix for platform-specific files
pub const exec_prefix: []const u8 = "/usr/local";

/// Base prefix (same as prefix unless in venv)
pub const base_prefix: []const u8 = "/usr/local";

/// Base exec prefix
pub const base_exec_prefix: []const u8 = "/usr/local";

// ============================================================================
// Path Operations
// ============================================================================

/// Get the module search path
pub fn getPath() []const []const u8 {
    return path_storage[0..path_len];
}

/// Set the module search path
pub fn setPath(paths: []const []const u8) void {
    const copy_len = @min(paths.len, path_storage.len);
    for (paths[0..copy_len], 0..) |p, i| {
        path_storage[i] = p;
    }
    path_len = copy_len;
}

/// Add a path to sys.path
pub fn addPath(new_path: []const u8) !void {
    if (path_len >= path_storage.len) {
        return error.PathStorageFull;
    }
    path_storage[path_len] = new_path;
    path_len += 1;
}

/// Initialize default paths
pub fn initPaths() void {
    path_storage[0] = "";
    path_storage[1] = ".";
    path_len = 2;
}

// ============================================================================
// Tests
// ============================================================================

test "path operations" {
    initPaths();
    try std.testing.expect(path_len >= 2);

    try addPath("/custom/path");
    const paths = getPath();
    try std.testing.expectEqualStrings("/custom/path", paths[paths.len - 1]);
}
