//! Python 'genericpath' module - Common operations on Posix and Windows pathnames
//!
//! Provides path operations that work on both Posix and Windows.
//!
//! Mirrors: CPython Lib/genericpath.py

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Path operations
// ============================================================================

/// Return True if path refers to an existing path.
pub fn exists(path: []const u8) bool {
    _ = std.fs.cwd().statFile(path) catch return false;
    return true;
}

/// Test whether a path is absolute.
pub fn isabs(path: []const u8) bool {
    if (builtin.os.tag == .windows) {
        // Windows: starts with drive letter or UNC path
        if (path.len >= 2 and path[1] == ':') return true;
        if (path.len >= 2 and path[0] == '\\' and path[1] == '\\') return true;
        return false;
    } else {
        // Posix: starts with /
        return path.len > 0 and path[0] == '/';
    }
}

/// Return True if path is an existing regular file.
pub fn isfile(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

/// Return True if path is an existing directory.
pub fn isdir(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

/// Return the size, in bytes, of path.
pub fn getsize(path: []const u8) !u64 {
    const stat = try std.fs.cwd().statFile(path);
    return stat.size;
}

/// Return the last modification time of path.
pub fn getmtime(path: []const u8) !i128 {
    const stat = try std.fs.cwd().statFile(path);
    return stat.mtime;
}

/// Return the last access time of path.
pub fn getatime(path: []const u8) !i128 {
    const stat = try std.fs.cwd().statFile(path);
    return stat.atime;
}

/// Return the creation time of path.
pub fn getctime(path: []const u8) !i128 {
    const stat = try std.fs.cwd().statFile(path);
    // ctime not always available, use mtime as fallback
    return stat.ctime;
}

/// Test whether two pathnames reference the same file or directory.
pub fn samefile(path1: []const u8, path2: []const u8) !bool {
    const stat1 = try std.fs.cwd().statFile(path1);
    const stat2 = try std.fs.cwd().statFile(path2);
    return stat1.inode == stat2.inode and stat1.dev == stat2.dev;
}

/// Test whether two file descriptors reference the same file.
pub fn sameopenfile(fd1: std.fs.File.Handle, fd2: std.fs.File.Handle) !bool {
    const file1 = std.fs.File{ .handle = fd1 };
    const file2 = std.fs.File{ .handle = fd2 };
    const stat1 = try file1.stat();
    const stat2 = try file2.stat();
    return stat1.inode == stat2.inode and stat1.dev == stat2.dev;
}

/// Test whether two stat structures reference the same file.
pub fn samestat(s1: std.fs.File.Stat, s2: std.fs.File.Stat) bool {
    return s1.inode == s2.inode and s1.dev == s2.dev;
}

// ============================================================================
// Path splitting
// ============================================================================

/// Split a pathname. Return tuple (head, tail).
pub fn split(path: []const u8) struct { head: []const u8, tail: []const u8 } {
    const sep = if (builtin.os.tag == .windows) '\\' else '/';

    // Find last separator
    var last_sep: ?usize = null;
    for (path, 0..) |c, i| {
        if (c == sep or (builtin.os.tag == .windows and c == '/')) {
            last_sep = i;
        }
    }

    if (last_sep) |idx| {
        var head = path[0 .. idx + 1];
        const tail = path[idx + 1 ..];

        // Strip trailing separators from head (except for root)
        while (head.len > 1 and (head[head.len - 1] == sep or
            (builtin.os.tag == .windows and head[head.len - 1] == '/')))
        {
            head = head[0 .. head.len - 1];
        }

        return .{ .head = head, .tail = tail };
    }

    return .{ .head = "", .tail = path };
}

/// Split the extension from a pathname.
pub fn splitext(path: []const u8) struct { root: []const u8, ext: []const u8 } {
    const sep = if (builtin.os.tag == .windows) '\\' else '/';

    // Find the base name (after last separator)
    var base_start: usize = 0;
    for (path, 0..) |c, i| {
        if (c == sep or (builtin.os.tag == .windows and c == '/')) {
            base_start = i + 1;
        }
    }

    // Find the extension (last dot not at start of basename)
    var ext_start: ?usize = null;
    var i = path.len;
    while (i > base_start) {
        i -= 1;
        if (path[i] == '.') {
            // Don't consider leading dots as extensions
            if (i == base_start) break;
            // Check if there's only dots
            var all_dots = true;
            for (path[base_start..i]) |c| {
                if (c != '.') {
                    all_dots = false;
                    break;
                }
            }
            if (!all_dots) {
                ext_start = i;
            }
            break;
        }
    }

    if (ext_start) |idx| {
        return .{ .root = path[0..idx], .ext = path[idx..] };
    }

    return .{ .root = path, .ext = "" };
}

/// Return the longest common sub-path of each pathname in the sequence.
pub fn commonprefix(allocator: std.mem.Allocator, paths: []const []const u8) ![]const u8 {
    if (paths.len == 0) return "";

    var min_path = paths[0];
    for (paths) |p| {
        if (p.len < min_path.len) {
            min_path = p;
        }
    }

    var prefix_len: usize = 0;
    outer: for (min_path, 0..) |c, i| {
        for (paths) |p| {
            if (p[i] != c) {
                break :outer;
            }
        }
        prefix_len = i + 1;
    }

    return try allocator.dupe(u8, paths[0][0..prefix_len]);
}

// ============================================================================
// Tests
// ============================================================================

test "exists with nonexistent file" {
    try std.testing.expect(!exists("/nonexistent/path/to/file"));
}

test "isabs posix style" {
    if (builtin.os.tag != .windows) {
        try std.testing.expect(isabs("/home/user"));
        try std.testing.expect(!isabs("relative/path"));
        try std.testing.expect(!isabs(""));
    }
}

test "isabs windows style" {
    if (builtin.os.tag == .windows) {
        try std.testing.expect(isabs("C:\\Users"));
        try std.testing.expect(isabs("\\\\server\\share"));
        try std.testing.expect(!isabs("relative\\path"));
    }
}

test "split path" {
    const result = split("/home/user/file.txt");
    try std.testing.expectEqualStrings("/home/user", result.head);
    try std.testing.expectEqualStrings("file.txt", result.tail);
}

test "split path no separator" {
    const result = split("file.txt");
    try std.testing.expectEqualStrings("", result.head);
    try std.testing.expectEqualStrings("file.txt", result.tail);
}

test "split path root" {
    const result = split("/file.txt");
    try std.testing.expectEqualStrings("/", result.head);
    try std.testing.expectEqualStrings("file.txt", result.tail);
}

test "splitext normal" {
    const result = splitext("/home/user/file.txt");
    try std.testing.expectEqualStrings("/home/user/file", result.root);
    try std.testing.expectEqualStrings(".txt", result.ext);
}

test "splitext no extension" {
    const result = splitext("/home/user/file");
    try std.testing.expectEqualStrings("/home/user/file", result.root);
    try std.testing.expectEqualStrings("", result.ext);
}

test "splitext dotfile" {
    const result = splitext("/home/user/.bashrc");
    try std.testing.expectEqualStrings("/home/user/.bashrc", result.root);
    try std.testing.expectEqualStrings("", result.ext);
}

test "splitext multiple dots" {
    const result = splitext("/home/user/file.tar.gz");
    try std.testing.expectEqualStrings("/home/user/file.tar", result.root);
    try std.testing.expectEqualStrings(".gz", result.ext);
}

test "commonprefix" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{ "/home/user/a", "/home/user/b", "/home/user/c" };
    const result = try commonprefix(allocator, &paths);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/home/user/", result);
}

test "commonprefix empty" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{};
    const result = try commonprefix(allocator, &paths);
    try std.testing.expectEqualStrings("", result);
}

test "commonprefix no common" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{ "/abc", "/xyz" };
    const result = try commonprefix(allocator, &paths);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/", result);
}

test "samestat" {
    const s1 = std.fs.File.Stat{ .inode = 123, .dev = 456, .size = 0, .mode = 0, .mtime = 0, .ctime = 0, .atime = 0, .kind = .file };
    const s2 = std.fs.File.Stat{ .inode = 123, .dev = 456, .size = 100, .mode = 0, .mtime = 0, .ctime = 0, .atime = 0, .kind = .file };
    const s3 = std.fs.File.Stat{ .inode = 789, .dev = 456, .size = 0, .mode = 0, .mtime = 0, .ctime = 0, .atime = 0, .kind = .file };

    try std.testing.expect(samestat(s1, s2));
    try std.testing.expect(!samestat(s1, s3));
}
