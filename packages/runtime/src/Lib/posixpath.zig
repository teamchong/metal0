//! Python 'posixpath' module - Posix pathname operations
//!
//! Provides path operations specific to POSIX systems.
//!
//! Mirrors: CPython Lib/posixpath.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

pub const sep: u8 = '/';
pub const altsep: ?u8 = null;
pub const extsep: u8 = '.';
pub const pathsep: u8 = ':';
pub const defpath: []const u8 = "/bin:/usr/bin";
pub const devnull: []const u8 = "/dev/null";

// ============================================================================
// Path normalization
// ============================================================================

/// Normalize a pathname by removing redundant separators and up-level references.
pub fn normpath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) {
        return try allocator.dupe(u8, ".");
    }

    const initial_slash = path[0] == '/';
    // POSIX allows one or three slashes at start, not two
    var initial_slashes: usize = 0;
    if (initial_slash) {
        initial_slashes = 1;
        if (path.len > 1 and path[1] == '/') {
            if (path.len > 2 and path[2] != '/') {
                initial_slashes = 2;
            }
        }
    }

    var components = std.ArrayList([]const u8).init(allocator);
    defer components.deinit();

    // Split path by /
    var parts = std.mem.splitSequence(u8, path, "/");
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) {
            continue;
        }
        if (std.mem.eql(u8, part, "..")) {
            if (components.items.len > 0 and !std.mem.eql(u8, components.items[components.items.len - 1], "..")) {
                _ = components.pop();
            } else if (!initial_slash) {
                try components.append("..");
            }
        } else {
            try components.append(part);
        }
    }

    // Reconstruct path
    var result = std.ArrayList(u8).init(allocator);

    // Add initial slashes
    for (0..initial_slashes) |_| {
        try result.append('/');
    }

    // Join components
    for (components.items, 0..) |comp, i| {
        if (i > 0) try result.append('/');
        try result.appendSlice(comp);
    }

    if (result.items.len == 0) {
        return try allocator.dupe(u8, ".");
    }

    return result.toOwnedSlice();
}

/// Return an absolute path.
pub fn abspath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (isabs(path)) {
        return normpath(allocator, path);
    }

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    return join(allocator, &[_][]const u8{ cwd, path });
}

/// Return a normalized absolutized version of the pathname path.
pub fn realpath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.fs.cwd().realpathAlloc(allocator, path);
}

/// Test whether a path is absolute.
pub fn isabs(path: []const u8) bool {
    return path.len > 0 and path[0] == '/';
}

/// Join path components.
pub fn join(allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    for (paths) |p| {
        if (p.len == 0) continue;

        if (p[0] == '/') {
            // Absolute path resets
            result.clearRetainingCapacity();
            try result.appendSlice(p);
        } else {
            if (result.items.len > 0 and result.items[result.items.len - 1] != '/') {
                try result.append('/');
            }
            try result.appendSlice(p);
        }
    }

    return result.toOwnedSlice();
}

/// Split a pathname into (head, tail).
pub fn split(path: []const u8) struct { head: []const u8, tail: []const u8 } {
    // Find last /
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') {
            var head = path[0 .. i + 1];
            const tail = path[i + 1 ..];

            // Strip trailing slashes from head (unless it's all slashes)
            if (head.len > 0) {
                var j = head.len;
                while (j > 0 and head[j - 1] == '/') {
                    j -= 1;
                }
                if (j > 0) head = head[0..j];
            }

            return .{ .head = head, .tail = tail };
        }
    }

    return .{ .head = "", .tail = path };
}

/// Split the extension from a pathname.
pub fn splitext(path: []const u8) struct { root: []const u8, ext: []const u8 } {
    const split_result = split(path);
    const base = split_result.tail;

    // Find last dot in base that's not at start
    var i = base.len;
    while (i > 0) {
        i -= 1;
        if (base[i] == '.') {
            if (i > 0) {
                const ext_start = path.len - base.len + i;
                return .{ .root = path[0..ext_start], .ext = path[ext_start..] };
            }
            break;
        }
    }

    return .{ .root = path, .ext = "" };
}

/// Split a pathname into drive and path (drive is always empty on Posix).
pub fn splitdrive(path: []const u8) struct { drive: []const u8, tail: []const u8 } {
    return .{ .drive = "", .tail = path };
}

/// Return the directory component of a pathname.
pub fn dirname(path: []const u8) []const u8 {
    return split(path).head;
}

/// Return the final component of a pathname.
pub fn basename(path: []const u8) []const u8 {
    return split(path).tail;
}

// ============================================================================
// Path expansion
// ============================================================================

/// Expand ~ and ~user constructs.
pub fn expanduser(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0 or path[0] != '~') {
        return try allocator.dupe(u8, path);
    }

    // Find end of ~user
    var i: usize = 1;
    while (i < path.len and path[i] != '/') {
        i += 1;
    }

    var home: ?[]const u8 = null;

    if (i == 1) {
        // Just ~
        home = std.posix.getenv("HOME");
    }
    // ~user expansion would require passwd lookup

    if (home) |h| {
        var result = std.ArrayList(u8).init(allocator);
        try result.appendSlice(h);
        if (i < path.len) {
            try result.appendSlice(path[i..]);
        }
        return result.toOwnedSlice();
    }

    return try allocator.dupe(u8, path);
}

/// Expand shell variables of the form $var and ${var}.
pub fn expandvars(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;

    while (i < path.len) {
        if (path[i] == '$') {
            if (i + 1 < path.len) {
                if (path[i + 1] == '$') {
                    // Escaped $
                    try result.append('$');
                    i += 2;
                    continue;
                } else if (path[i + 1] == '{') {
                    // ${var}
                    if (std.mem.indexOfScalar(u8, path[i + 2 ..], '}')) |end| {
                        const var_name = path[i + 2 .. i + 2 + end];
                        if (std.posix.getenv(var_name)) |val| {
                            try result.appendSlice(val);
                        }
                        i = i + 3 + end;
                        continue;
                    }
                } else {
                    // $var
                    var j = i + 1;
                    while (j < path.len and (std.ascii.isAlphanumeric(path[j]) or path[j] == '_')) {
                        j += 1;
                    }
                    if (j > i + 1) {
                        const var_name = path[i + 1 .. j];
                        if (std.posix.getenv(var_name)) |val| {
                            try result.appendSlice(val);
                        }
                        i = j;
                        continue;
                    }
                }
            }
        }
        try result.append(path[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Path queries
// ============================================================================

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

/// Return True if path is a symbolic link.
pub fn islink(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .sym_link;
}

/// Return True if path is a mount point.
pub fn ismount(path: []const u8) bool {
    const stat1 = std.fs.cwd().statFile(path) catch return false;
    const parent = dirname(path);
    const parent_path = if (parent.len == 0) "." else parent;
    const stat2 = std.fs.cwd().statFile(parent_path) catch return false;
    return stat1.dev != stat2.dev;
}

/// Return True if path refers to an existing path.
pub fn exists(path: []const u8) bool {
    _ = std.fs.cwd().statFile(path) catch return false;
    return true;
}

/// Return True if path refers to an existing path (follows symlinks).
pub fn lexists(path: []const u8) bool {
    // Would use lstat, for now same as exists
    return exists(path);
}

// ============================================================================
// Tests
// ============================================================================

test "normpath simple" {
    const allocator = std.testing.allocator;
    const result = try normpath(allocator, "/home/user/../other");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/home/other", result);
}

test "normpath dots" {
    const allocator = std.testing.allocator;
    const result = try normpath(allocator, "/home/./user/./file");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/home/user/file", result);
}

test "normpath double slash" {
    const allocator = std.testing.allocator;
    const result = try normpath(allocator, "//home//user");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("//home/user", result);
}

test "normpath empty" {
    const allocator = std.testing.allocator;
    const result = try normpath(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqualStrings(".", result);
}

test "isabs" {
    try std.testing.expect(isabs("/home/user"));
    try std.testing.expect(!isabs("relative/path"));
    try std.testing.expect(!isabs(""));
}

test "join paths" {
    const allocator = std.testing.allocator;
    const result = try join(allocator, &[_][]const u8{ "/home", "user", "file.txt" });
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/home/user/file.txt", result);
}

test "join with absolute" {
    const allocator = std.testing.allocator;
    const result = try join(allocator, &[_][]const u8{ "/home", "/etc", "passwd" });
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/etc/passwd", result);
}

test "split path" {
    const result = split("/home/user/file.txt");
    try std.testing.expectEqualStrings("/home/user", result.head);
    try std.testing.expectEqualStrings("file.txt", result.tail);
}

test "split root" {
    const result = split("/file.txt");
    try std.testing.expectEqualStrings("/", result.head);
    try std.testing.expectEqualStrings("file.txt", result.tail);
}

test "splitext" {
    const result = splitext("/home/user/file.txt");
    try std.testing.expectEqualStrings("/home/user/file", result.root);
    try std.testing.expectEqualStrings(".txt", result.ext);
}

test "splitdrive" {
    const result = splitdrive("/home/user");
    try std.testing.expectEqualStrings("", result.drive);
    try std.testing.expectEqualStrings("/home/user", result.tail);
}

test "dirname" {
    try std.testing.expectEqualStrings("/home/user", dirname("/home/user/file.txt"));
    try std.testing.expectEqualStrings("", dirname("file.txt"));
}

test "basename" {
    try std.testing.expectEqualStrings("file.txt", basename("/home/user/file.txt"));
    try std.testing.expectEqualStrings("file.txt", basename("file.txt"));
}

test "expanduser home" {
    const allocator = std.testing.allocator;
    if (std.posix.getenv("HOME")) |home| {
        const result = try expanduser(allocator, "~/file.txt");
        defer allocator.free(result);
        try std.testing.expect(std.mem.startsWith(u8, result, home));
    }
}

test "expanduser no tilde" {
    const allocator = std.testing.allocator;
    const result = try expanduser(allocator, "/home/user");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/home/user", result);
}

test "expandvars" {
    const allocator = std.testing.allocator;
    if (std.posix.getenv("HOME")) |_| {
        const result = try expandvars(allocator, "$HOME/file");
        defer allocator.free(result);
        try std.testing.expect(result.len > 6); // More than "/file"
    }
}

test "expandvars escaped" {
    const allocator = std.testing.allocator;
    const result = try expandvars(allocator, "$$HOME");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("$HOME", result);
}

test "exists nonexistent" {
    try std.testing.expect(!exists("/nonexistent/path/to/file"));
}

test "constants" {
    try std.testing.expectEqual(@as(u8, '/'), sep);
    try std.testing.expectEqual(@as(u8, '.'), extsep);
    try std.testing.expectEqual(@as(u8, ':'), pathsep);
}
