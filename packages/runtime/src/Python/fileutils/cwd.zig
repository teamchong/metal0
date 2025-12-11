/// cwd - Current Working Directory
/// Mirrors cpython/Python/fileutils.c cwd operations
///
/// This module provides current working directory operations.

const std = @import("std");
const errors = @import("errors.zig");
const FileError = errors.FileError;

// ============================================================================
// Current Working Directory
// ============================================================================

/// Get current working directory
pub fn getcwd(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [4096]u8 = undefined;
    const path = std.fs.cwd().realpath(".", &buf) catch return FileError.IOError;
    return allocator.dupe(u8, path);
}

/// Change current working directory
pub fn chdir(path: []const u8) FileError!void {
    std.posix.chdir(path) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            error.NotDir => FileError.NotDirectory,
            else => FileError.IOError,
        };
    };
}
