//! pathlib._os - OS-specific path operations
//! Reference: cpython/Lib/pathlib/_os.py
//!
//! Internal OS-level operations for pathlib.

const std = @import("std");
const builtin = @import("builtin");

/// Copy file with optional metadata preservation
pub fn copyFile(
    allocator: std.mem.Allocator,
    src: []const u8,
    dst: []const u8,
    follow_symlinks: bool,
) !void {
    _ = follow_symlinks;

    // Read source
    const content = try std.fs.cwd().readFileAlloc(allocator, src, std.math.maxInt(usize));
    defer allocator.free(content);

    // Write destination
    const file = try std.fs.cwd().createFile(dst, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Get file owner UID (Unix only)
pub fn getOwner(path: []const u8) !u32 {
    if (comptime builtin.os.tag == .windows) {
        return error.UnsupportedOperation;
    }

    const stat = try std.fs.cwd().statFile(path);
    return stat.uid;
}

/// Get file group GID (Unix only)
pub fn getGroup(path: []const u8) !u32 {
    if (comptime builtin.os.tag == .windows) {
        return error.UnsupportedOperation;
    }

    const stat = try std.fs.cwd().statFile(path);
    return stat.gid;
}

/// Change file owner (Unix only)
pub fn chown(path: []const u8, uid: ?u32, gid: ?u32) !void {
    if (comptime builtin.os.tag == .windows) {
        return error.UnsupportedOperation;
    }

    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    defer file.close();

    // Use fchown
    const real_uid: u32 = uid orelse @as(u32, @bitCast(@as(i32, -1)));
    const real_gid: u32 = gid orelse @as(u32, @bitCast(@as(i32, -1)));

    try std.posix.fchown(file.handle, real_uid, real_gid);
}

/// Change file permissions
pub fn chmod(path: []const u8, mode: u32) !void {
    if (comptime builtin.os.tag == .windows) {
        // Windows doesn't have Unix-style permissions
        return;
    }

    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    defer file.close();

    try std.posix.fchmod(file.handle, @intCast(mode));
}

/// Create a symbolic link
pub fn symlink(target: []const u8, link_path: []const u8) !void {
    try std.fs.cwd().symLink(target, link_path, .{});
}

/// Read a symbolic link
pub fn readlink(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return try std.fs.cwd().readLink(path, allocator);
}

/// Create a hard link
pub fn link(src: []const u8, dst: []const u8) !void {
    if (comptime builtin.os.tag == .windows) {
        // Windows hard link support
        return error.UnsupportedOperation;
    }

    try std.posix.link(src, dst);
}

/// Get file access and modification times
pub fn getTimes(path: []const u8) !struct { atime: i64, mtime: i64 } {
    const stat = try std.fs.cwd().statFile(path);
    return .{
        .atime = @intCast(@divFloor(stat.atime, std.time.ns_per_s)),
        .mtime = @intCast(@divFloor(stat.mtime, std.time.ns_per_s)),
    };
}

/// Set file access and modification times
pub fn setTimes(path: []const u8, atime: ?i64, mtime: ?i64) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    defer file.close();

    const stat = try file.stat();

    const real_atime: i128 = if (atime) |a| @as(i128, a) * std.time.ns_per_s else stat.atime;
    const real_mtime: i128 = if (mtime) |m| @as(i128, m) * std.time.ns_per_s else stat.mtime;

    try file.updateTimes(real_atime, real_mtime);
}

/// File type enumeration
pub const FileType = enum {
    file,
    directory,
    symlink,
    block_device,
    character_device,
    fifo,
    socket,
    unknown,
};

/// Get file type
pub fn getFileType(path: []const u8) !FileType {
    const stat = try std.fs.cwd().statFile(path);

    return switch (stat.kind) {
        .file => .file,
        .directory => .directory,
        .sym_link => .symlink,
        .block_device => .block_device,
        .character_device => .character_device,
        .named_pipe => .fifo,
        .unix_domain_socket => .socket,
        else => .unknown,
    };
}

/// Check if path is a mount point
pub fn isMountPoint(path: []const u8) !bool {
    if (comptime builtin.os.tag == .windows) {
        // Windows mount point detection
        return false;
    }

    // Unix: Check if . and .. have different devices
    const stat1 = try std.fs.cwd().statFile(path);

    const parent = std.fs.path.dirname(path) orelse return true;
    const stat2 = std.fs.cwd().statFile(parent) catch return true;

    return stat1.dev != stat2.dev;
}

/// Glob pattern matching (simple implementation)
pub fn matchPattern(name: []const u8, pattern: []const u8) bool {
    var ni: usize = 0;
    var pi: usize = 0;

    while (pi < pattern.len) {
        const pc = pattern[pi];

        switch (pc) {
            '*' => {
                // Wildcard: match zero or more characters
                pi += 1;
                if (pi >= pattern.len) return true;

                while (ni < name.len) {
                    if (matchPattern(name[ni..], pattern[pi..])) return true;
                    ni += 1;
                }
                return false;
            },
            '?' => {
                // Single character wildcard
                if (ni >= name.len) return false;
                ni += 1;
                pi += 1;
            },
            '[' => {
                // Character class
                if (ni >= name.len) return false;
                pi += 1;

                var matched = false;
                var negated = false;

                if (pi < pattern.len and pattern[pi] == '!') {
                    negated = true;
                    pi += 1;
                }

                while (pi < pattern.len and pattern[pi] != ']') {
                    if (pattern[pi] == name[ni]) matched = true;
                    pi += 1;
                }

                if (pi < pattern.len) pi += 1; // Skip ']'

                if (negated) matched = !matched;
                if (!matched) return false;
                ni += 1;
            },
            else => {
                if (ni >= name.len or name[ni] != pc) return false;
                ni += 1;
                pi += 1;
            },
        }
    }

    return ni >= name.len;
}

// ============================================================================
// Tests
// ============================================================================

test "matchPattern basic" {
    try std.testing.expect(matchPattern("test.txt", "test.txt"));
    try std.testing.expect(matchPattern("test.txt", "*.txt"));
    try std.testing.expect(matchPattern("test.txt", "test.*"));
    try std.testing.expect(matchPattern("test.txt", "t?st.txt"));
    try std.testing.expect(!matchPattern("test.txt", "*.py"));
}

test "matchPattern character class" {
    try std.testing.expect(matchPattern("test.txt", "[t]est.txt"));
    try std.testing.expect(matchPattern("test.txt", "[!a]est.txt"));
    try std.testing.expect(!matchPattern("test.txt", "[a]est.txt"));
}

test "FileType enum" {
    _ = FileType.file;
    _ = FileType.directory;
    _ = FileType.symlink;
}
