/// stat - File Statistics
/// Mirrors cpython/Python/fileutils.c file statistics
///
/// This module provides file statistics operations.

const std = @import("std");
const errors = @import("errors.zig");
const FileError = errors.FileError;

// ============================================================================
// File Statistics
// ============================================================================

/// File stat result
pub const StatResult = struct {
    mode: u32,
    size: u64,
    atime: i128,
    mtime: i128,
    ctime: i128,
    is_dir: bool,
    is_file: bool,
    is_link: bool,
};

/// Get file statistics
pub fn stat(path: []const u8) FileError!StatResult {
    const s = std.fs.cwd().statFile(path) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            else => FileError.IOError,
        };
    };

    return StatResult{
        .mode = s.mode,
        .size = s.size,
        .atime = s.atime,
        .mtime = s.mtime,
        .ctime = s.ctime,
        .is_dir = s.kind == .directory,
        .is_file = s.kind == .file,
        .is_link = s.kind == .sym_link,
    };
}

/// Get file size
pub fn getsize(path: []const u8) FileError!u64 {
    const s = try stat(path);
    return s.size;
}

/// Get modification time
pub fn getmtime(path: []const u8) FileError!i128 {
    const s = try stat(path);
    return s.mtime;
}
