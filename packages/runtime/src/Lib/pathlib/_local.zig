//! pathlib._local - Local path implementation details
//! Reference: cpython/Lib/pathlib/_local.py
//!
//! Internal implementation for local filesystem paths.
//! Re-exports from parent pathlib module.

const std = @import("std");
const pathlib = @import("../pathlib.zig");

// Re-export main Path class
pub const Path = pathlib.Path;
pub const LazyFile = pathlib.LazyFile;

/// Platform-specific path separator
pub const sep = std.fs.path.sep;

/// Alternative separator (Windows only)
pub const altsep: ?u8 = if (std.fs.path.sep == '\\') '/' else null;

/// Path extension separator
pub const extsep = '.';

/// Current directory marker
pub const curdir = ".";

/// Parent directory marker
pub const pardir = "..";

/// Check if a path is reserved (Windows-specific)
pub fn isReserved(path: []const u8) bool {
    // On Unix, no paths are reserved
    if (comptime std.Target.current.os.tag != .windows) {
        return false;
    }

    // Windows reserved names: CON, PRN, AUX, NUL, COM1-COM9, LPT1-LPT9
    const reserved_names = [_][]const u8{
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    };

    const basename = std.fs.path.basename(path);
    const name_without_ext = if (std.mem.indexOf(u8, basename, ".")) |dot|
        basename[0..dot]
    else
        basename;

    for (reserved_names) |reserved| {
        if (std.ascii.eqlIgnoreCase(name_without_ext, reserved)) {
            return true;
        }
    }
    return false;
}

/// Normalize path separators
pub fn normalizeSeparators(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (comptime std.fs.path.sep == '/') {
        // Unix: no transformation needed
        return try allocator.dupe(u8, path);
    }

    // Windows: convert forward slashes to backslashes
    var result = try allocator.alloc(u8, path.len);
    for (path, 0..) |c, i| {
        result[i] = if (c == '/') '\\' else c;
    }
    return result;
}

/// Join path parts
pub fn joinParts(allocator: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    return std.fs.path.join(allocator, parts);
}

/// Split path into drive and rest (Windows UNC support)
pub fn splitDrive(path: []const u8) struct { drive: []const u8, rest: []const u8 } {
    if (comptime std.fs.path.sep == '/') {
        // Unix: no drive
        return .{ .drive = "", .rest = path };
    }

    // Windows drive detection
    if (path.len >= 2) {
        if (path[1] == ':') {
            // Standard drive letter
            return .{ .drive = path[0..2], .rest = path[2..] };
        }
        if (path.len >= 4 and path[0] == '\\' and path[1] == '\\') {
            // UNC path
            if (std.mem.indexOf(u8, path[2..], "\\")) |third_slash| {
                const server_end = third_slash + 2;
                if (std.mem.indexOf(u8, path[server_end + 1 ..], "\\")) |fourth_slash| {
                    const share_end = fourth_slash + server_end + 1;
                    return .{ .drive = path[0..share_end], .rest = path[share_end..] };
                }
            }
        }
    }

    return .{ .drive = "", .rest = path };
}

// ============================================================================
// Tests
// ============================================================================

test "isReserved" {
    try std.testing.expect(!isReserved("normal.txt"));
    // Platform-specific reserved path tests would go here
}

test "normalizeSeparators" {
    const allocator = std.testing.allocator;
    const result = try normalizeSeparators(allocator, "a/b/c");
    defer allocator.free(result);
    // On Unix, should be unchanged
    if (comptime std.fs.path.sep == '/') {
        try std.testing.expectEqualStrings("a/b/c", result);
    }
}

test "splitDrive" {
    const result = splitDrive("/home/user/file.txt");
    try std.testing.expectEqualStrings("", result.drive);
    try std.testing.expectEqualStrings("/home/user/file.txt", result.rest);
}
