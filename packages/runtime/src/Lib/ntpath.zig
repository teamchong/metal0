//! Python 'ntpath' module - Windows pathname operations
//!
//! Provides path operations specific to Windows/NT systems.
//!
//! Mirrors: CPython Lib/ntpath.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

pub const sep: u8 = '\\';
pub const altsep: u8 = '/';
pub const extsep: u8 = '.';
pub const pathsep: u8 = ';';
pub const defpath: []const u8 = ".;C:\\bin";
pub const devnull: []const u8 = "nul";

// ============================================================================
// Path normalization
// ============================================================================

/// Normalize a pathname by replacing forward slashes with backslashes.
pub fn normpath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) {
        return try allocator.dupe(u8, ".");
    }

    var result = std.ArrayList(u8).init(allocator);

    // Replace forward slashes with backslashes
    var normalized = try allocator.alloc(u8, path.len);
    defer allocator.free(normalized);
    for (path, 0..) |c, i| {
        normalized[i] = if (c == '/') '\\' else c;
    }

    // Check for UNC path
    var prefix: []const u8 = "";
    var start: usize = 0;
    if (normalized.len >= 2 and normalized[0] == '\\' and normalized[1] == '\\') {
        // UNC path
        start = 2;
        // Find server\share
        var slashes: usize = 0;
        var i: usize = 2;
        while (i < normalized.len and slashes < 2) : (i += 1) {
            if (normalized[i] == '\\') {
                slashes += 1;
            }
        }
        prefix = normalized[0..i];
        start = i;
    } else if (normalized.len >= 2 and normalized[1] == ':') {
        // Drive letter
        prefix = normalized[0..2];
        start = 2;
        if (normalized.len > 2 and normalized[2] == '\\') {
            prefix = normalized[0..3];
            start = 3;
        }
    }

    try result.appendSlice(prefix);

    // Process path components
    var components = std.ArrayList([]const u8).init(allocator);
    defer components.deinit();

    var parts = std.mem.splitSequence(u8, normalized[start..], "\\");
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) {
            continue;
        }
        if (std.mem.eql(u8, part, "..")) {
            if (components.items.len > 0 and !std.mem.eql(u8, components.items[components.items.len - 1], "..")) {
                _ = components.pop();
            } else if (prefix.len == 0) {
                try components.append("..");
            }
        } else {
            try components.append(part);
        }
    }

    // Join components
    for (components.items, 0..) |comp, i| {
        if (i > 0 or (prefix.len > 0 and prefix[prefix.len - 1] != '\\')) {
            try result.append('\\');
        }
        try result.appendSlice(comp);
    }

    if (result.items.len == 0) {
        return try allocator.dupe(u8, ".");
    }

    return result.toOwnedSlice();
}

/// Test whether a path is absolute.
pub fn isabs(path: []const u8) bool {
    // Absolute if starts with drive letter + backslash or UNC path
    if (path.len >= 3 and path[1] == ':' and (path[2] == '\\' or path[2] == '/')) {
        return true;
    }
    if (path.len >= 2 and (path[0] == '\\' or path[0] == '/') and (path[1] == '\\' or path[1] == '/')) {
        return true;
    }
    return false;
}

/// Join path components.
pub fn join(allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var result_drive: []const u8 = "";
    var result_path = std.ArrayList(u8).init(allocator);
    defer result_path.deinit();

    for (paths) |p| {
        if (p.len == 0) continue;

        const p_drive = splitdrive(p).drive;
        const p_path = splitdrive(p).tail;

        if (isabs(p)) {
            result_drive = p_drive;
            result_path.clearRetainingCapacity();
            try result_path.appendSlice(p_path);
        } else if (p_drive.len > 0 and !std.mem.eql(u8, p_drive, result_drive)) {
            result_drive = p_drive;
            result_path.clearRetainingCapacity();
            try result_path.appendSlice(p_path);
        } else {
            if (result_path.items.len > 0) {
                const last = result_path.items[result_path.items.len - 1];
                if (last != '\\' and last != '/') {
                    try result_path.append('\\');
                }
            }
            try result_path.appendSlice(p_path);
        }
    }

    try result.appendSlice(result_drive);
    try result.appendSlice(result_path.items);
    return result.toOwnedSlice();
}

/// Split a pathname into drive and path.
pub fn splitdrive(path: []const u8) struct { drive: []const u8, tail: []const u8 } {
    if (path.len >= 2) {
        // Check for UNC path \\server\share
        if ((path[0] == '\\' or path[0] == '/') and (path[1] == '\\' or path[1] == '/')) {
            // Find \\server\share boundary
            var i: usize = 2;
            var slashes: usize = 0;
            while (i < path.len and slashes < 2) : (i += 1) {
                if (path[i] == '\\' or path[i] == '/') {
                    slashes += 1;
                }
            }
            if (slashes >= 2) {
                return .{ .drive = path[0 .. i - 1], .tail = path[i - 1 ..] };
            }
            return .{ .drive = path, .tail = "" };
        }
        // Check for drive letter C:
        if (path[1] == ':') {
            return .{ .drive = path[0..2], .tail = path[2..] };
        }
    }
    return .{ .drive = "", .tail = path };
}

/// Split a pathname into (head, tail).
pub fn split(path: []const u8) struct { head: []const u8, tail: []const u8 } {
    const drive_split = splitdrive(path);
    const d = drive_split.drive;
    var p = drive_split.tail;

    // Find last separator
    var i = p.len;
    while (i > 0) {
        i -= 1;
        if (p[i] == '\\' or p[i] == '/') {
            var head = p[0 .. i + 1];
            const tail = p[i + 1 ..];

            // Strip trailing separators
            while (head.len > 0 and (head[head.len - 1] == '\\' or head[head.len - 1] == '/')) {
                head = head[0 .. head.len - 1];
            }

            // Combine drive and head
            if (d.len > 0) {
                var combined = std.ArrayList(u8).init(std.heap.page_allocator);
                combined.appendSlice(d) catch {};
                combined.appendSlice(head) catch {};
                return .{ .head = combined.items, .tail = tail };
            }

            return .{ .head = head, .tail = tail };
        }
    }

    return .{ .head = d, .tail = p };
}

/// Split the extension from a pathname.
pub fn splitext(path: []const u8) struct { root: []const u8, ext: []const u8 } {
    const drive_split = splitdrive(path);
    const p = drive_split.tail;

    // Find last separator
    var base_start: usize = 0;
    for (p, 0..) |c, i| {
        if (c == '\\' or c == '/') {
            base_start = i + 1;
        }
    }

    // Find extension
    var i = p.len;
    while (i > base_start) {
        i -= 1;
        if (p[i] == '.') {
            if (i > base_start) {
                const ext_start = drive_split.drive.len + i;
                return .{ .root = path[0..ext_start], .ext = path[ext_start..] };
            }
            break;
        }
    }

    return .{ .root = path, .ext = "" };
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
    while (i < path.len and path[i] != '\\' and path[i] != '/') {
        i += 1;
    }

    var home: ?[]const u8 = null;

    if (i == 1) {
        // Just ~
        home = std.posix.getenv("USERPROFILE");
        if (home == null) {
            if (std.posix.getenv("HOMEPATH")) |homepath| {
                if (std.posix.getenv("HOMEDRIVE")) |homedrive| {
                    _ = homedrive;
                    _ = homepath;
                    // Would combine HOMEDRIVE + HOMEPATH
                }
            }
        }
    }

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

/// Expand shell variables of the form %var%.
pub fn expandvars(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;

    while (i < path.len) {
        if (path[i] == '%') {
            if (std.mem.indexOfScalar(u8, path[i + 1 ..], '%')) |end| {
                const var_name = path[i + 1 .. i + 1 + end];
                if (std.posix.getenv(var_name)) |val| {
                    try result.appendSlice(val);
                } else {
                    try result.appendSlice(path[i .. i + 2 + end]);
                }
                i = i + 2 + end;
                continue;
            }
        } else if (path[i] == '$') {
            // Also support $var and ${var}
            if (i + 1 < path.len) {
                if (path[i + 1] == '{') {
                    if (std.mem.indexOfScalar(u8, path[i + 2 ..], '}')) |end| {
                        const var_name = path[i + 2 .. i + 2 + end];
                        if (std.posix.getenv(var_name)) |val| {
                            try result.appendSlice(val);
                        }
                        i = i + 3 + end;
                        continue;
                    }
                } else {
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

/// Return True if path refers to an existing path.
pub fn exists(path: []const u8) bool {
    _ = std.fs.cwd().statFile(path) catch return false;
    return true;
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

/// Return True if path is a symbolic link.
pub fn islink(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .sym_link;
}

/// Return True if pathname path is a mount point.
pub fn ismount(path: []const u8) bool {
    // On Windows, mount point if drive root or UNC root
    const drive_split = splitdrive(path);
    if (drive_split.drive.len > 0) {
        const tail = drive_split.tail;
        if (tail.len == 0 or (tail.len == 1 and (tail[0] == '\\' or tail[0] == '/'))) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "normpath simple" {
    const allocator = std.testing.allocator;
    const result = try normpath(allocator, "C:\\Users\\..\\Other");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("C:\\Other", result);
}

test "normpath forward slashes" {
    const allocator = std.testing.allocator;
    const result = try normpath(allocator, "C:/Users/Name");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("C:\\Users\\Name", result);
}

test "normpath empty" {
    const allocator = std.testing.allocator;
    const result = try normpath(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqualStrings(".", result);
}

test "isabs drive letter" {
    try std.testing.expect(isabs("C:\\Users"));
    try std.testing.expect(isabs("D:/Users"));
    try std.testing.expect(!isabs("C:relative"));
    try std.testing.expect(!isabs("relative\\path"));
}

test "isabs UNC" {
    try std.testing.expect(isabs("\\\\server\\share"));
    try std.testing.expect(isabs("//server/share"));
}

test "splitdrive drive letter" {
    const result = splitdrive("C:\\Users\\Name");
    try std.testing.expectEqualStrings("C:", result.drive);
    try std.testing.expectEqualStrings("\\Users\\Name", result.tail);
}

test "splitdrive no drive" {
    const result = splitdrive("\\Users\\Name");
    try std.testing.expectEqualStrings("", result.drive);
    try std.testing.expectEqualStrings("\\Users\\Name", result.tail);
}

test "splitext" {
    const result = splitext("C:\\Users\\file.txt");
    try std.testing.expectEqualStrings("C:\\Users\\file", result.root);
    try std.testing.expectEqualStrings(".txt", result.ext);
}

test "splitext no ext" {
    const result = splitext("C:\\Users\\file");
    try std.testing.expectEqualStrings("C:\\Users\\file", result.root);
    try std.testing.expectEqualStrings("", result.ext);
}

test "basename" {
    try std.testing.expectEqualStrings("file.txt", basename("C:\\Users\\file.txt"));
}

test "join paths" {
    const allocator = std.testing.allocator;
    const result = try join(allocator, &[_][]const u8{ "C:\\Users", "Name", "file.txt" });
    defer allocator.free(result);
    try std.testing.expectEqualStrings("C:\\Users\\Name\\file.txt", result);
}

test "join with absolute" {
    const allocator = std.testing.allocator;
    const result = try join(allocator, &[_][]const u8{ "C:\\Users", "D:\\Other" });
    defer allocator.free(result);
    try std.testing.expectEqualStrings("D:\\Other", result);
}

test "exists nonexistent" {
    try std.testing.expect(!exists("C:\\NonExistent\\Path"));
}

test "ismount drive root" {
    try std.testing.expect(ismount("C:\\"));
    try std.testing.expect(ismount("D:/"));
    try std.testing.expect(!ismount("C:\\Users"));
}

test "constants" {
    try std.testing.expectEqual(@as(u8, '\\'), sep);
    try std.testing.expectEqual(@as(u8, '/'), altsep);
    try std.testing.expectEqual(@as(u8, '.'), extsep);
    try std.testing.expectEqual(@as(u8, ';'), pathsep);
}
