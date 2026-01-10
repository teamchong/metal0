//! importlib._bootstrap_external - External import machinery (frozen module)
//! Reference: cpython/Lib/importlib/_bootstrap_external.py
//!
//! This module handles file-based imports and is normally frozen.
//! In AOT compilation, file imports are resolved at compile time.

const std = @import("std");
const builtin = @import("builtin");
const importlib = @import("../importlib.zig");

// Re-export from parent module (DRY)
pub const ModuleSpec = importlib.ModuleSpec;
pub const SourceFileLoader = importlib.SourceFileLoader;
pub const SourcelessFileLoader = importlib.SourcelessFileLoader;
pub const ExtensionFileLoader = importlib.ExtensionFileLoader;
pub const PathFinder = importlib.PathFinder;

// File suffixes
pub const SOURCE_SUFFIXES: []const []const u8 = &.{".py"};
pub const BYTECODE_SUFFIXES: []const []const u8 = &.{".pyc"};
pub const EXTENSION_SUFFIXES: []const []const u8 = if (builtin.os.tag == .windows)
    &.{".pyd", ".dll"}
else if (builtin.os.tag == .macos)
    &.{".so", ".dylib"}
else
    &.{".so"};

/// Magic number for bytecode files (Python 3.12+)
pub const MAGIC_NUMBER: [4]u8 = .{ 0xa7, 0x0d, 0x0d, 0x0a };

/// Cache tag for bytecode files
pub const CACHE_TAG: []const u8 = "cpython-312";

/// Check if a path is a package (has __init__.py)
pub fn isPackage(path: []const u8) bool {
    var buf: [512]u8 = undefined;
    const init_path = std.fmt.bufPrint(&buf, "{s}/__init__.py", .{path}) catch return false;
    std.fs.cwd().access(init_path, .{}) catch return false;
    return true;
}

/// Get the path to the cache directory
pub fn cachePath(source_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // Simple: replace .py with .pyc
    if (std.mem.endsWith(u8, source_path, ".py")) {
        var result = try allocator.alloc(u8, source_path.len + 1);
        @memcpy(result[0..source_path.len], source_path);
        result[source_path.len] = 'c';
        return result;
    }
    return allocator.dupe(u8, source_path);
}

test "isPackage" {
    try std.testing.expect(!isPackage("/nonexistent/path"));
}

test "MAGIC_NUMBER" {
    try std.testing.expectEqual(@as(u8, 0xa7), MAGIC_NUMBER[0]);
}
