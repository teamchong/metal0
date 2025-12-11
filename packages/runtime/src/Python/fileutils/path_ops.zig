/// path_ops - Path Operations
/// Mirrors cpython/Python/fileutils.c path operations
///
/// This module provides path manipulation and validation utilities.

const std = @import("std");
const builtin = @import("builtin");
const errors = @import("errors.zig");
const FileError = errors.FileError;

// ============================================================================
// Path Operations
// ============================================================================

/// Path separator for current platform
pub const SEP: u8 = if (builtin.os.tag == .windows) '\\' else '/';

/// Alternative separator (Windows has both)
pub const ALTSEP: ?u8 = if (builtin.os.tag == .windows) '/' else null;

/// Extension separator
pub const EXTSEP: u8 = '.';

/// Path list separator (e.g., in PATH environment variable)
pub const PATHSEP: u8 = if (builtin.os.tag == .windows) ';' else ':';

/// Join path components
pub fn joinPath(allocator: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    if (parts.len == 0) return "";

    var size: usize = 0;
    for (parts) |part| {
        if (part.len > 0) {
            size += part.len + 1; // +1 for separator
        }
    }

    var result = try allocator.alloc(u8, size);
    var pos: usize = 0;

    for (parts) |part| {
        if (part.len == 0) continue;

        // Skip leading separator if not first
        var start: usize = 0;
        if (pos > 0 and part[0] == SEP) {
            start = 1;
        }

        // Add separator if needed
        if (pos > 0 and result[pos - 1] != SEP) {
            result[pos] = SEP;
            pos += 1;
        }

        // Copy part
        @memcpy(result[pos .. pos + part.len - start], part[start..]);
        pos += part.len - start;
    }

    return result[0..pos];
}

/// Get directory name from path
pub fn dirname(path: []const u8) []const u8 {
    if (path.len == 0) return ".";

    // Find last separator
    var i = path.len;
    while (i > 0) : (i -= 1) {
        if (path[i - 1] == SEP) {
            if (i == 1) return "/";
            return path[0 .. i - 1];
        }
    }
    return ".";
}

/// Get base name from path
pub fn basename(path: []const u8) []const u8 {
    if (path.len == 0) return "";

    // Find last separator
    var i = path.len;
    while (i > 0) : (i -= 1) {
        if (path[i - 1] == SEP) {
            return path[i..];
        }
    }
    return path;
}

/// Get file extension
pub fn extension(path: []const u8) []const u8 {
    const base = basename(path);
    if (base.len == 0) return "";

    // Find last dot (not at start)
    var i = base.len;
    while (i > 0) : (i -= 1) {
        if (base[i - 1] == EXTSEP) {
            if (i == 1) return ""; // Hidden file, not extension
            return base[i - 1 ..];
        }
    }
    return "";
}

/// Split path into directory and basename
pub fn splitPath(path: []const u8) struct { []const u8, []const u8 } {
    return .{ dirname(path), basename(path) };
}

/// Split extension from path
pub fn splitExt(path: []const u8) struct { []const u8, []const u8 } {
    const ext = extension(path);
    if (ext.len == 0) return .{ path, "" };
    return .{ path[0 .. path.len - ext.len], ext };
}

/// Normalize path (remove redundant separators and ..)
pub fn normpath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (path.len == 0) return ".";

    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    const is_absolute = path[0] == SEP;

    // Split by separator
    var iter = std.mem.splitSequence(u8, path, &[_]u8{SEP});
    while (iter.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) {
            continue;
        }
        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len > 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) {
                _ = parts.pop();
            } else if (!is_absolute) {
                try parts.append("..");
            }
        } else {
            try parts.append(part);
        }
    }

    // Rebuild path
    if (parts.items.len == 0) {
        return if (is_absolute) "/" else ".";
    }

    return joinPath(allocator, parts.items);
}

/// Check if path is absolute
pub fn isabs(path: []const u8) bool {
    if (path.len == 0) return false;
    if (builtin.os.tag == .windows) {
        // Windows: C:\ or \\server or /
        if (path.len >= 3 and path[1] == ':' and (path[2] == '\\' or path[2] == '/')) {
            return true;
        }
        if (path.len >= 2 and path[0] == '\\' and path[1] == '\\') {
            return true;
        }
    }
    return path[0] == SEP;
}

/// Get absolute path
pub fn abspath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (isabs(path)) {
        return normpath(allocator, path);
    }

    var cwd_buf: [4096]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch return FileError.IOError;

    const parts = [_][]const u8{ cwd, path };
    const joined = try joinPath(allocator, &parts);
    defer allocator.free(joined);

    return normpath(allocator, joined);
}

/// Check if path exists
pub fn exists(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    _ = stat;
    return true;
}

/// Check if path is a file
pub fn isfile(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

/// Check if path is a directory
pub fn isdir(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

/// Check if path is a symbolic link
pub fn islink(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .sym_link;
}

// ============================================================================
// Tests
// ============================================================================

test "path operations" {
    try std.testing.expectEqualStrings(".", dirname("foo"));
    try std.testing.expectEqualStrings("/usr", dirname("/usr/bin"));
    try std.testing.expectEqualStrings("foo", basename("foo"));
    try std.testing.expectEqualStrings("bar", basename("/foo/bar"));
    try std.testing.expectEqualStrings(".txt", extension("file.txt"));
    try std.testing.expectEqualStrings("", extension("file"));
}

test "isabs" {
    try std.testing.expect(isabs("/foo/bar"));
    try std.testing.expect(!isabs("foo/bar"));
    try std.testing.expect(!isabs(""));
}

test "split operations" {
    const split1 = splitPath("/foo/bar");
    try std.testing.expectEqualStrings("/foo", split1[0]);
    try std.testing.expectEqualStrings("bar", split1[1]);

    const split2 = splitExt("file.txt");
    try std.testing.expectEqualStrings("file", split2[0]);
    try std.testing.expectEqualStrings(".txt", split2[1]);
}

test "join path" {
    const allocator = std.testing.allocator;
    const parts = [_][]const u8{ "foo", "bar", "baz" };
    const joined = try joinPath(allocator, &parts);
    defer allocator.free(joined);
    try std.testing.expectEqualStrings("foo/bar/baz", joined);
}
