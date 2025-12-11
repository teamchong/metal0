/// fd_ops - File Descriptor Operations
/// Mirrors cpython/Python/fileutils.c file descriptor operations
///
/// This module provides low-level file descriptor operations.

const std = @import("std");
const errors = @import("errors.zig");
const FileError = errors.FileError;

// ============================================================================
// File Descriptor Operations
// ============================================================================

/// Open flags matching CPython's os module
pub const OpenFlags = packed struct {
    read: bool = false,
    write: bool = false,
    append: bool = false,
    create: bool = false,
    exclusive: bool = false,
    truncate: bool = false,
    binary: bool = false,
    text: bool = true,
    cloexec: bool = true, // Close on exec by default
    nonblock: bool = false,
    directory: bool = false,
    sync: bool = false,
    _padding: u4 = 0,
};

/// Open a file with the given flags
pub fn open(path: []const u8, flags: OpenFlags) FileError!std.fs.File {
    var std_flags: std.fs.File.OpenFlags = .{};

    if (flags.read and flags.write) {
        std_flags.mode = .read_write;
    } else if (flags.write) {
        std_flags.mode = .write_only;
    } else {
        std_flags.mode = .read_only;
    }

    // Use cwd() for relative paths
    const file = std.fs.cwd().openFile(path, std_flags) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.FileNotFound,
            error.AccessDenied => FileError.AccessDenied,
            error.IsDir => FileError.IsDirectory,
            else => FileError.IOError,
        };
    };

    return file;
}

/// Create a file
pub fn create(path: []const u8, mode: u9) FileError!std.fs.File {
    _ = mode;
    return std.fs.cwd().createFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => FileError.InvalidPath,
            error.AccessDenied => FileError.AccessDenied,
            error.PathAlreadyExists => FileError.Exists,
            else => FileError.IOError,
        };
    };
}

/// Close a file descriptor
pub fn close(file: std.fs.File) void {
    file.close();
}

/// Read from file descriptor
pub fn read(file: std.fs.File, buffer: []u8) FileError!usize {
    return file.read(buffer) catch FileError.IOError;
}

/// Write to file descriptor
pub fn write(file: std.fs.File, data: []const u8) FileError!usize {
    return file.write(data) catch |err| {
        return switch (err) {
            error.BrokenPipe => FileError.BrokenPipe,
            else => FileError.IOError,
        };
    };
}

/// Seek in file
pub fn seek(file: std.fs.File, offset: i64, whence: std.fs.File.SeekableStream.SeekOrigin) FileError!u64 {
    _ = file.seekTo(@intCast(offset)) catch return FileError.IOError;
    return file.getPos() catch return FileError.IOError;
}

/// Get current position
pub fn tell(file: std.fs.File) FileError!u64 {
    return file.getPos() catch FileError.IOError;
}

/// Check if file descriptor is a TTY
pub fn isatty(file: std.fs.File) bool {
    return std.posix.isatty(file.handle);
}
