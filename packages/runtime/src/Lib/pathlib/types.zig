//! pathlib.types - Type definitions for pathlib
//! Reference: cpython/Lib/pathlib/types.py
//!
//! CPython __all__: PathLike (from os module)
//!
//! Type definitions and protocols for path operations.

const std = @import("std");
const pathlib = @import("../pathlib.zig");

/// PathLike protocol - objects that can be used as filesystem paths
/// In CPython, this is os.PathLike which defines __fspath__
pub fn PathLike(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();

        /// Get the filesystem path representation
        /// Equivalent to Python's __fspath__
        pub fn fspath(self: Self) []const u8 {
            if (comptime @hasDecl(T, "toString")) {
                return self.value.toString();
            } else if (comptime @hasDecl(T, "path")) {
                return self.value.path;
            } else if (comptime @TypeOf(T) == []const u8) {
                return self.value;
            } else {
                @compileError("Type does not implement PathLike protocol");
            }
        }
    };
}

/// Convert any path-like object to a string
pub fn fspath(path: anytype) []const u8 {
    const T = @TypeOf(path);

    if (T == []const u8) {
        return path;
    } else if (T == *pathlib.Path) {
        return path.toString();
    } else if (T == *const pathlib.Path) {
        return path.toString();
    } else if (@hasDecl(T, "toString")) {
        return path.toString();
    } else if (@hasField(T, "path")) {
        return path.path;
    } else {
        @compileError("Cannot convert type to path");
    }
}

/// PurePath flavour types (for cross-platform path handling)
pub const Flavour = enum {
    posix,
    windows,
};

/// Get the current platform's flavour
pub fn currentFlavour() Flavour {
    return if (std.fs.path.sep == '/') .posix else .windows;
}

/// Path parts structure
pub const PathParts = struct {
    drive: []const u8,
    root: []const u8,
    parts: []const []const u8,
};

/// Parse a path into its components
pub fn parsePath(allocator: std.mem.Allocator, path: []const u8) !PathParts {
    var parts_list: std.ArrayList([]const u8) = .{};
    errdefer {
        for (parts_list.items) |p| allocator.free(p);
        parts_list.deinit(allocator);
    }

    // Determine drive and root
    var drive: []const u8 = "";
    var root: []const u8 = "";
    var rest = path;

    // Handle Windows drive letters and UNC paths
    if (currentFlavour() == .windows and path.len >= 2) {
        if (path[1] == ':') {
            drive = path[0..2];
            rest = path[2..];
        } else if (path.len >= 4 and path[0] == '\\' and path[1] == '\\') {
            // UNC path handling would go here
        }
    }

    // Handle root
    if (rest.len > 0 and (rest[0] == '/' or rest[0] == '\\')) {
        root = rest[0..1];
        rest = rest[1..];
    }

    // Split remaining path into parts
    var iter = std.mem.splitAny(u8, rest, "/\\");
    while (iter.next()) |part| {
        if (part.len > 0) {
            try parts_list.append(allocator, try allocator.dupe(u8, part));
        }
    }

    return .{
        .drive = drive,
        .root = root,
        .parts = try parts_list.toOwnedSlice(allocator),
    };
}

/// Free PathParts resources
pub fn freePathParts(allocator: std.mem.Allocator, parts: *PathParts) void {
    for (parts.parts) |p| {
        allocator.free(p);
    }
    allocator.free(parts.parts);
}

/// Stat result structure (subset of os.stat_result)
pub const StatResult = struct {
    mode: u32,
    ino: u64,
    dev: u64,
    nlink: u64,
    uid: u32,
    gid: u32,
    size: u64,
    atime: i64,
    mtime: i64,
    ctime: i64,
};

/// Get stat result for a path
pub fn stat(path: []const u8) !StatResult {
    const s = try std.fs.cwd().statFile(path);

    return .{
        .mode = @intCast(s.mode),
        .ino = s.inode,
        .dev = s.dev,
        .nlink = @intCast(s.nlink),
        .uid = s.uid,
        .gid = s.gid,
        .size = s.size,
        .atime = @intCast(@divFloor(s.atime, std.time.ns_per_s)),
        .mtime = @intCast(@divFloor(s.mtime, std.time.ns_per_s)),
        .ctime = @intCast(@divFloor(s.ctime, std.time.ns_per_s)),
    };
}

/// Directory entry (from iterating a directory)
pub const DirEntry = struct {
    name: []const u8,
    path: []const u8,
    kind: std.fs.Dir.Entry.Kind,

    pub fn isFile(self: DirEntry) bool {
        return self.kind == .file;
    }

    pub fn isDir(self: DirEntry) bool {
        return self.kind == .directory;
    }

    pub fn isSymlink(self: DirEntry) bool {
        return self.kind == .sym_link;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "fspath string" {
    const path = "/tmp/test.txt";
    try std.testing.expectEqualStrings("/tmp/test.txt", fspath(path));
}

test "currentFlavour" {
    const flavour = currentFlavour();
    if (comptime std.fs.path.sep == '/') {
        try std.testing.expectEqual(Flavour.posix, flavour);
    } else {
        try std.testing.expectEqual(Flavour.windows, flavour);
    }
}

test "parsePath" {
    const allocator = std.testing.allocator;
    var parts = try parsePath(allocator, "/home/user/file.txt");
    defer freePathParts(allocator, &parts);

    try std.testing.expectEqualStrings("", parts.drive);
    try std.testing.expectEqualStrings("/", parts.root);
    try std.testing.expectEqual(@as(usize, 3), parts.parts.len);
    try std.testing.expectEqualStrings("home", parts.parts[0]);
    try std.testing.expectEqualStrings("user", parts.parts[1]);
    try std.testing.expectEqualStrings("file.txt", parts.parts[2]);
}

test "DirEntry" {
    const entry = DirEntry{
        .name = "test.txt",
        .path = "/tmp/test.txt",
        .kind = .file,
    };
    try std.testing.expect(entry.isFile());
    try std.testing.expect(!entry.isDir());
}
