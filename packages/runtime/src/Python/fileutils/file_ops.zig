/// file_ops - File Operations
/// Mirrors cpython/Python/fileutils.c file operations
///
/// This module provides file manipulation operations.

const std = @import("std");
const errors = @import("errors.zig");
const FileError = errors.FileError;

// ============================================================================
// File Operations
// ============================================================================

/// Remove file
pub fn unlink(path: []const u8) FileError!void {
    std.fs.cwd().deleteFile(path) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            error.IsDir => FileError.IsDirectory,
            else => FileError.IOError,
        };
    };
}

/// Rename file or directory
pub fn rename(old_path: []const u8, new_path: []const u8) FileError!void {
    std.fs.cwd().rename(old_path, new_path) catch {
        return FileError.IOError;
    };
}

/// Copy file
pub fn copy(src: []const u8, dst: []const u8) FileError!void {
    std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{}) catch {
        return FileError.IOError;
    };
}
