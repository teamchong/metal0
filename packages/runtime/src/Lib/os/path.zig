/// os.path module - Path manipulations
/// CPython Reference: https://docs.python.org/3.12/library/os.path.html
const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.zig");
const file_ops = @import("file_ops.zig");
const process = @import("process.zig");

/// Join path components
pub fn join(allocator: std.mem.Allocator, paths: []const []const u8) ![]const u8 {
    if (paths.len == 0) return try allocator.dupe(u8, "");

    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    for (paths, 0..) |p, i| {
        if (p.len == 0) continue;

        // If path is absolute, start fresh
        if (isabs(p)) {
            result.clearRetainingCapacity();
            try result.appendSlice(allocator, p);
        } else {
            // Add separator if needed
            if (result.items.len > 0 and result.items[result.items.len - 1] != constants.sep[0]) {
                try result.appendSlice(allocator, constants.sep);
            }
            try result.appendSlice(allocator, p);
        }
        _ = i;
    }

    return result.toOwnedSlice(allocator);
}

/// Check if path is absolute
pub fn isabs(p: []const u8) bool {
    if (p.len == 0) return false;
    if (builtin.os.tag == .windows) {
        // Check for drive letter or UNC path
        if (p.len >= 2 and p[1] == ':') return true;
        if (p.len >= 2 and p[0] == '\\' and p[1] == '\\') return true;
    }
    return p[0] == '/';
}

/// Get the base name of a path
pub fn basename(p: []const u8) []const u8 {
    if (p.len == 0) return "";

    // Find last separator
    var i = p.len;
    while (i > 0) {
        i -= 1;
        if (p[i] == '/' or (builtin.os.tag == .windows and p[i] == '\\')) {
            return p[i + 1 ..];
        }
    }
    return p;
}

/// Get the directory name of a path
pub fn dirname(p: []const u8) []const u8 {
    if (p.len == 0) return "";

    // Find last separator
    var i = p.len;
    while (i > 0) {
        i -= 1;
        if (p[i] == '/' or (builtin.os.tag == .windows and p[i] == '\\')) {
            if (i == 0) return "/";
            return p[0..i];
        }
    }
    return "";
}

/// Split path into (head, tail) where tail is the last component
pub fn split(p: []const u8) struct { head: []const u8, tail: []const u8 } {
    return .{
        .head = dirname(p),
        .tail = basename(p),
    };
}

/// Split path into (root, ext) where ext is the file extension
pub fn splitext(p: []const u8) struct { root: []const u8, ext: []const u8 } {
    const base = basename(p);
    if (base.len == 0) return .{ .root = p, .ext = "" };

    // Find last dot (but not leading dot)
    var i = base.len;
    while (i > 1) {
        i -= 1;
        if (base[i] == '.') {
            const dir = dirname(p);
            if (dir.len == 0) {
                return .{ .root = base[0..i], .ext = base[i..] };
            } else {
                // Need to reconstruct full path
                return .{ .root = p[0 .. p.len - (base.len - i)], .ext = base[i..] };
            }
        }
    }
    return .{ .root = p, .ext = "" };
}

/// Check if path exists
pub fn pathExists(p: []const u8) bool {
    return file_ops.exists(p);
}

/// Check if path is a file
pub fn isFile(p: []const u8) bool {
    return file_ops.isfile(p);
}

/// Check if path is a directory
pub fn isDir(p: []const u8) bool {
    return file_ops.isdir(p);
}

/// Get absolute path
pub fn abspath(allocator: std.mem.Allocator, p: []const u8) ![]const u8 {
    if (isabs(p)) {
        return try allocator.dupe(u8, p);
    }

    const cwd = try process.getcwd(allocator);
    defer allocator.free(cwd);

    const paths = [_][]const u8{ cwd, p };
    return try join(allocator, &paths);
}

/// Normalize a path (remove redundant separators, resolve . and ..)
pub fn normpath(allocator: std.mem.Allocator, p: []const u8) ![]const u8 {
    if (p.len == 0) return try allocator.dupe(u8, ".");

    var components: std.ArrayList([]const u8) = .{};
    defer components.deinit(allocator);

    const is_absolute = isabs(p);
    var iter = std.mem.splitScalar(u8, p, '/');

    while (iter.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".")) {
            continue;
        }
        if (std.mem.eql(u8, component, "..")) {
            if (components.items.len > 0 and !std.mem.eql(u8, components.items[components.items.len - 1], "..")) {
                _ = components.pop();
            } else if (!is_absolute) {
                try components.append(allocator, "..");
            }
        } else {
            try components.append(allocator, component);
        }
    }

    if (components.items.len == 0) {
        return try allocator.dupe(u8, if (is_absolute) "/" else ".");
    }

    var result: std.ArrayList(u8) = .{};
    if (is_absolute) try result.append(allocator, '/');

    for (components.items, 0..) |comp, i| {
        if (i > 0) try result.append(allocator, '/');
        try result.appendSlice(allocator, comp);
    }

    return result.toOwnedSlice(allocator);
}

/// Normalize case of a path
/// On Unix/Mac, this returns the path unchanged (case-sensitive filesystem)
/// On Windows, this converts to lowercase and replaces forward slashes with backslashes
/// Note: Takes optional allocator for API consistency (not used on POSIX)
pub fn normcase(_: std.mem.Allocator, p: []const u8) ![]const u8 {
    // On POSIX systems (Unix, Mac, Linux), normcase is an identity function
    // The filesystem is case-sensitive, so we don't modify the path
    // This matches CPython's os.path.normcase behavior
    if (builtin.os.tag != .windows) {
        return p;
    }
    // On Windows, would need to lowercase and normalize slashes
    // For now, return as-is (most metal0 users are on Unix/Mac)
    return p;
}

/// Get the real path (resolve symlinks)
pub fn realpath(allocator: std.mem.Allocator, p: []const u8) ![]const u8 {
    // Use std.fs to resolve the real path
    const absolute = try abspath(allocator, p);
    defer allocator.free(absolute);

    // Try to resolve symlinks using std.fs
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (std.fs.cwd().realpathZ(absolute.ptr, &path_buf)) |resolved| {
        return try allocator.dupe(u8, resolved);
    } else |_| {
        // If realpath fails (e.g., path doesn't exist), return absolute path
        return try allocator.dupe(u8, absolute);
    }
}

/// Get common prefix of a list of paths
pub fn commonprefix(paths: []const []const u8) []const u8 {
    if (paths.len == 0) return "";
    if (paths.len == 1) return paths[0];

    // Find minimum length
    var min_len = paths[0].len;
    for (paths[1..]) |p| {
        if (p.len < min_len) min_len = p.len;
    }

    // Find common prefix
    var i: usize = 0;
    outer: while (i < min_len) : (i += 1) {
        const c = paths[0][i];
        for (paths[1..]) |p| {
            if (p[i] != c) break :outer;
        }
    }

    return paths[0][0..i];
}

// ============================================================================
// Tests
// ============================================================================

test "path.basename" {
    try std.testing.expectEqualStrings("file.txt", basename("/home/user/file.txt"));
    try std.testing.expectEqualStrings("file.txt", basename("file.txt"));
    try std.testing.expectEqualStrings("", basename("/home/user/"));
    try std.testing.expectEqualStrings("", basename(""));
}

test "path.dirname" {
    try std.testing.expectEqualStrings("/home/user", dirname("/home/user/file.txt"));
    try std.testing.expectEqualStrings("", dirname("file.txt"));
    try std.testing.expectEqualStrings("/home/user", dirname("/home/user/"));
}

test "path.splitext" {
    const r1 = splitext("/home/user/file.txt");
    try std.testing.expectEqualStrings("/home/user/file", r1.root);
    try std.testing.expectEqualStrings(".txt", r1.ext);

    const r2 = splitext("file");
    try std.testing.expectEqualStrings("file", r2.root);
    try std.testing.expectEqualStrings("", r2.ext);

    const r3 = splitext(".hidden");
    try std.testing.expectEqualStrings(".hidden", r3.root);
    try std.testing.expectEqualStrings("", r3.ext);
}

test "path.isabs" {
    try std.testing.expect(isabs("/home/user"));
    try std.testing.expect(!isabs("relative/path"));
    try std.testing.expect(!isabs(""));
}

test "path.join" {
    const allocator = std.testing.allocator;

    const p1 = try join(allocator, &.{ "/home", "user", "file.txt" });
    defer allocator.free(p1);
    try std.testing.expectEqualStrings("/home/user/file.txt", p1);

    const p2 = try join(allocator, &.{ "relative", "path" });
    defer allocator.free(p2);
    try std.testing.expectEqualStrings("relative/path", p2);
}
