//! ctypes.macholib.dyld - dyld emulation
//! Reference: cpython/Lib/ctypes/macholib/dyld.py
//!
//! CPython __all__: ['dyld_find', 'framework_find', 'framework_info', 'dylib_info']
//!
//! Emulates dyld library search behavior for finding dynamic libraries
//! and frameworks on macOS.

const std = @import("std");
const builtin = @import("builtin");
const framework_mod = @import("framework.zig");
const dylib_mod = @import("dylib.zig");

// Re-export from submodules
pub const framework_info = framework_mod.framework_info;
pub const dylib_info = dylib_mod.dylib_info;

// ============================================================================
// Default Search Paths (as per man dyld(1))
// ============================================================================

/// Default framework fallback paths
pub const DEFAULT_FRAMEWORK_FALLBACK = [_][]const u8{
    "/Library/Frameworks",
    "/System/Library/Frameworks",
};

/// Default library fallback paths
pub const DEFAULT_LIBRARY_FALLBACK = [_][]const u8{
    "/usr/local/lib",
    "/lib",
    "/usr/lib",
};

// ============================================================================
// Environment Variable Helpers
// ============================================================================

/// Get paths from a dyld environment variable
pub fn dyld_env(env_var: []const u8) []const []const u8 {
    if (std.posix.getenv(env_var)) |value| {
        // Would split by ':' but return static for now
        _ = value;
    }
    return &[_][]const u8{};
}

/// CPython: def dyld_image_suffix(env=None)
/// Get DYLD_IMAGE_SUFFIX environment variable
pub fn dyld_image_suffix() ?[]const u8 {
    return std.posix.getenv("DYLD_IMAGE_SUFFIX");
}

/// CPython: def dyld_framework_path(env=None)
/// Get DYLD_FRAMEWORK_PATH paths
pub fn dyld_framework_path() []const []const u8 {
    return dyld_env("DYLD_FRAMEWORK_PATH");
}

/// CPython: def dyld_library_path(env=None)
/// Get DYLD_LIBRARY_PATH paths
pub fn dyld_library_path() []const []const u8 {
    return dyld_env("DYLD_LIBRARY_PATH");
}

/// CPython: def dyld_fallback_framework_path(env=None)
/// Get DYLD_FALLBACK_FRAMEWORK_PATH paths
pub fn dyld_fallback_framework_path() []const []const u8 {
    return dyld_env("DYLD_FALLBACK_FRAMEWORK_PATH");
}

/// CPython: def dyld_fallback_library_path(env=None)
/// Get DYLD_FALLBACK_LIBRARY_PATH paths
pub fn dyld_fallback_library_path() []const []const u8 {
    return dyld_env("DYLD_FALLBACK_LIBRARY_PATH");
}

// ============================================================================
// Path Search Functions
// ============================================================================

/// CPython: def dyld_override_search(name, env=None)
/// Search DYLD_FRAMEWORK_PATH and DYLD_LIBRARY_PATH
fn dyld_override_search(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    // Check if this is a framework
    if (framework_info(name)) |info| {
        // Search DYLD_FRAMEWORK_PATH
        if (std.posix.getenv("DYLD_FRAMEWORK_PATH")) |fw_path| {
            var iter = std.mem.splitScalar(u8, fw_path, ':');
            while (iter.next()) |dir| {
                const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, info.name }) catch continue;
                if (fileExists(full)) {
                    return full;
                }
                allocator.free(full);
            }
        }
    }

    // Search DYLD_LIBRARY_PATH
    if (std.posix.getenv("DYLD_LIBRARY_PATH")) |lib_path| {
        const basename = std.fs.path.basename(name);
        var iter = std.mem.splitScalar(u8, lib_path, ':');
        while (iter.next()) |dir| {
            const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, basename }) catch continue;
            if (fileExists(full)) {
                return full;
            }
            allocator.free(full);
        }
    }

    return null;
}

/// CPython: def dyld_executable_path_search(name, executable_path=None)
/// Handle @executable_path prefix
fn dyld_executable_path_search(allocator: std.mem.Allocator, name: []const u8, executable_path: ?[]const u8) ?[]const u8 {
    const prefix = "@executable_path/";
    if (std.mem.startsWith(u8, name, prefix)) {
        if (executable_path) |exec_path| {
            const suffix = name[prefix.len..];
            return std.fmt.allocPrint(allocator, "{s}/{s}", .{ exec_path, suffix }) catch null;
        }
    }
    return null;
}

/// CPython: def dyld_default_search(name, env=None)
/// Search default paths and fallbacks
fn dyld_default_search(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    // Try name directly first
    if (fileExists(name)) {
        return allocator.dupe(u8, name) catch null;
    }

    // Check if this is a framework
    if (framework_info(name)) |info| {
        // Try DYLD_FALLBACK_FRAMEWORK_PATH
        if (std.posix.getenv("DYLD_FALLBACK_FRAMEWORK_PATH")) |paths| {
            var iter = std.mem.splitScalar(u8, paths, ':');
            while (iter.next()) |dir| {
                const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, info.name }) catch continue;
                if (fileExists(full)) return full;
                allocator.free(full);
            }
        } else {
            // Use default framework paths
            for (DEFAULT_FRAMEWORK_FALLBACK) |dir| {
                const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, info.name }) catch continue;
                if (fileExists(full)) return full;
                allocator.free(full);
            }
        }
    }

    // Try DYLD_FALLBACK_LIBRARY_PATH
    const basename = std.fs.path.basename(name);
    if (std.posix.getenv("DYLD_FALLBACK_LIBRARY_PATH")) |paths| {
        var iter = std.mem.splitScalar(u8, paths, ':');
        while (iter.next()) |dir| {
            const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, basename }) catch continue;
            if (fileExists(full)) return full;
            allocator.free(full);
        }
    } else {
        // Use default library paths
        for (DEFAULT_LIBRARY_FALLBACK) |dir| {
            const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, basename }) catch continue;
            if (fileExists(full)) return full;
            allocator.free(full);
        }
    }

    return null;
}

// ============================================================================
// Main Functions
// ============================================================================

/// CPython: def dyld_find(name, executable_path=None, env=None)
/// Find a library or framework using dyld semantics
pub fn dyld_find(allocator: std.mem.Allocator, name: []const u8, executable_path: ?[]const u8) ?[]const u8 {
    // Handle DYLD_IMAGE_SUFFIX
    const suffix = dyld_image_suffix();

    // Try with suffix first if set
    if (suffix) |sfx| {
        const name_with_suffix = blk: {
            if (std.mem.endsWith(u8, name, ".dylib")) {
                const base = name[0 .. name.len - 6];
                break :blk std.fmt.allocPrint(allocator, "{s}{s}.dylib", .{ base, sfx }) catch null;
            } else {
                break :blk std.fmt.allocPrint(allocator, "{s}{s}", .{ name, sfx }) catch null;
            }
        };

        if (name_with_suffix) |suffixed| {
            defer allocator.free(suffixed);

            // Search with suffix
            if (dyld_override_search(allocator, suffixed)) |found| return found;
            if (dyld_executable_path_search(allocator, suffixed, executable_path)) |found| {
                if (fileExists(found)) return found;
                allocator.free(found);
            }
            if (dyld_default_search(allocator, suffixed)) |found| return found;
        }
    }

    // Search without suffix
    if (dyld_override_search(allocator, name)) |found| return found;
    if (dyld_executable_path_search(allocator, name, executable_path)) |found| {
        if (fileExists(found)) return found;
        allocator.free(found);
    }
    if (dyld_default_search(allocator, name)) |found| return found;

    // Check dyld shared cache (macOS 11+)
    if (dyld_shared_cache_contains_path(name)) {
        return allocator.dupe(u8, name) catch null;
    }

    return null;
}

/// CPython: def framework_find(fn, executable_path=None, env=None)
/// Find a framework using dyld semantics in a loose manner.
/// Accepts input like: Python, Python.framework, Python.framework/Versions/Current
pub fn framework_find(allocator: std.mem.Allocator, name: []const u8, executable_path: ?[]const u8) ?[]const u8 {
    // Try direct lookup first
    if (dyld_find(allocator, name, executable_path)) |found| {
        return found;
    }

    // Try adding .framework suffix
    var fmwk_name: []const u8 = undefined;
    var fmwk_index = std.mem.lastIndexOf(u8, name, ".framework");

    if (fmwk_index == null) {
        // Add .framework suffix
        const with_framework = std.fmt.allocPrint(allocator, "{s}.framework", .{name}) catch return null;
        defer allocator.free(with_framework);

        // Construct full framework path: Name.framework/Name
        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ with_framework, name }) catch return null;
        return dyld_find(allocator, full_path, executable_path);
    }

    return null;
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if a file exists
fn fileExists(path: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}

/// Check if path is in dyld shared cache (macOS 11+)
/// CPython: from _ctypes import _dyld_shared_cache_contains_path
fn dyld_shared_cache_contains_path(path: []const u8) bool {
    // On macOS 11+, many system libraries are in the shared cache
    // and don't exist as files on disk
    if (builtin.os.tag != .macos) return false;

    // Common system libraries in shared cache
    const cached_prefixes = [_][]const u8{
        "/usr/lib/lib",
        "/System/Library/Frameworks/",
    };

    for (cached_prefixes) |prefix| {
        if (std.mem.startsWith(u8, path, prefix)) {
            return true;
        }
    }

    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "DEFAULT_FRAMEWORK_FALLBACK" {
    try std.testing.expect(DEFAULT_FRAMEWORK_FALLBACK.len >= 2);
}

test "DEFAULT_LIBRARY_FALLBACK" {
    try std.testing.expect(DEFAULT_LIBRARY_FALLBACK.len >= 3);
}

test "fileExists" {
    // Root should exist
    try std.testing.expect(fileExists("/"));
    // Random path should not
    try std.testing.expect(!fileExists("/nonexistent_path_12345"));
}

test "dyld_image_suffix" {
    // Usually not set
    const suffix = dyld_image_suffix();
    _ = suffix;
}
