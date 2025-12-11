/// dir_ops - Directory Operations
/// Mirrors cpython/Python/fileutils.c directory operations
///
/// This module provides directory manipulation operations.

const std = @import("std");
const errors = @import("errors.zig");
const FileError = errors.FileError;

// ============================================================================
// Directory Operations
// ============================================================================

/// Read directory contents
pub fn listdir(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
        return FileError.IOError;
    };
    defer dir.close();

    var names = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit();
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const name = try allocator.dupe(u8, entry.name);
        try names.append(name);
    }

    return names.toOwnedSlice();
}

/// Create directory
pub fn mkdir(path: []const u8) FileError!void {
    std.fs.cwd().makeDir(path) catch |err| {
        return switch (err) {
            error.PathAlreadyExists => FileError.Exists,
            error.AccessDenied => FileError.AccessDenied,
            else => FileError.IOError,
        };
    };
}

/// Create directory recursively
pub fn makedirs(path: []const u8) FileError!void {
    std.fs.cwd().makePath(path) catch |err| {
        return switch (err) {
            error.AccessDenied => FileError.AccessDenied,
            else => FileError.IOError,
        };
    };
}

/// Remove directory
pub fn rmdir(path: []const u8) FileError!void {
    std.fs.cwd().deleteDir(path) catch |err| {
        return switch (err) {
            error.DirNotEmpty => FileError.IOError,
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            else => FileError.IOError,
        };
    };
}
