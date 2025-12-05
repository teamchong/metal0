/// shutil - High-level file operations
/// Provides copy, move, rmtree, and other shell utilities
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Copy a file from src to dst
/// If dst is a directory, copy into it with same filename
pub fn copy(allocator: Allocator, src: []const u8, dst: []const u8) ![]const u8 {
    // Check if dst is a directory
    var is_dir = false;
    if (std.fs.cwd().openDir(dst, .{})) |dir| {
        var d = dir;
        d.close();
        is_dir = true;
    } else |_| {}

    const final_dst = if (is_dir) blk: {
        const basename = std.fs.path.basename(src);
        break :blk try std.fs.path.join(allocator, &.{ dst, basename });
    } else try allocator.dupe(u8, dst);

    try std.fs.cwd().copyFile(src, std.fs.cwd(), final_dst, .{});
    return final_dst;
}

/// Copy file preserving metadata (copy2 in Python)
pub fn copy2(allocator: Allocator, src: []const u8, dst: []const u8) ![]const u8 {
    // For now, same as copy - Zig's copyFile preserves what it can
    return copy(allocator, src, dst);
}

/// Copy file content only (no metadata)
pub fn copyfile(src: []const u8, dst: []const u8) !void {
    try std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{});
}

/// Copy entire directory tree
pub fn copytree(allocator: Allocator, src: []const u8, dst: []const u8) !void {
    // Create destination directory
    try std.fs.cwd().makePath(dst);

    // Open source directory
    var src_dir = try std.fs.cwd().openDir(src, .{ .iterate = true });
    defer src_dir.close();

    // Iterate and copy
    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        const src_path = try std.fs.path.join(allocator, &.{ src, entry.name });
        defer allocator.free(src_path);
        const dst_path = try std.fs.path.join(allocator, &.{ dst, entry.name });
        defer allocator.free(dst_path);

        switch (entry.kind) {
            .directory => {
                try copytree(allocator, src_path, dst_path);
            },
            .file => {
                try std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{});
            },
            .sym_link => {
                // Read and recreate symlink
                var link_buf: [std.fs.max_path_bytes]u8 = undefined;
                const link_target = try src_dir.readLink(entry.name, &link_buf);
                try std.fs.cwd().symLink(link_target, dst_path, .{});
            },
            else => {},
        }
    }
}

/// Move file or directory (rename with fallback to copy+delete)
pub fn move(allocator: Allocator, src: []const u8, dst: []const u8) ![]const u8 {
    // Check if dst is a directory
    var is_dir = false;
    if (std.fs.cwd().openDir(dst, .{})) |dir| {
        var d = dir;
        d.close();
        is_dir = true;
    } else |_| {}

    const final_dst = if (is_dir) blk: {
        const basename = std.fs.path.basename(src);
        break :blk try std.fs.path.join(allocator, &.{ dst, basename });
    } else try allocator.dupe(u8, dst);

    // Try rename first (fast, same filesystem)
    std.fs.cwd().rename(src, final_dst) catch |err| {
        if (err == error.RenameAcrossMountPoints) {
            // Different filesystem - copy then delete
            // Check if source is a directory
            if (std.fs.cwd().openDir(src, .{})) |*dir| {
                dir.close();
                try copytree(allocator, src, final_dst);
                try rmtree(src);
            } else |_| {
                try std.fs.cwd().copyFile(src, std.fs.cwd(), final_dst, .{});
                try std.fs.cwd().deleteFile(src);
            }
        } else {
            return err;
        }
    };

    return final_dst;
}

/// Remove directory tree recursively (rm -rf)
pub fn rmtree(path: []const u8) !void {
    // Try to delete as file first
    std.fs.cwd().deleteFile(path) catch |file_err| {
        if (file_err == error.IsDir) {
            // It's a directory - delete recursively
            try std.fs.cwd().deleteTree(path);
        } else if (file_err == error.FileNotFound) {
            // Already gone, that's fine
            return;
        } else {
            return file_err;
        }
    };
}

/// Remove single file or empty directory
pub fn remove(path: []const u8) !void {
    std.fs.cwd().deleteFile(path) catch |err| {
        if (err == error.IsDir) {
            try std.fs.cwd().deleteDir(path);
        } else {
            return err;
        }
    };
}

/// Get disk usage statistics
pub const DiskUsage = struct {
    total: u64,
    used: u64,
    free: u64,
};

/// Get disk usage for a path (like df)
pub fn disk_usage(path: []const u8) !DiskUsage {
    _ = path;
    // This requires platform-specific syscalls
    // For now, return a stub
    return .{
        .total = 0,
        .used = 0,
        .free = 0,
    };
}

/// Check if a command exists in PATH
pub fn which(allocator: Allocator, cmd: []const u8) !?[]const u8 {
    const path_env = std.posix.getenv("PATH") orelse return null;

    var iter = std.mem.splitScalar(u8, path_env, ':');
    while (iter.next()) |dir| {
        const full_path = try std.fs.path.join(allocator, &.{ dir, cmd });
        defer allocator.free(full_path);

        // Check if file exists and is executable
        const stat = std.fs.cwd().statFile(full_path) catch continue;
        if (stat.kind == .file) {
            // Check executable bit
            if (stat.mode & 0o111 != 0) {
                return try allocator.dupe(u8, full_path);
            }
        }
    }

    return null;
}

/// Create archive (basic tar-like)
pub fn make_archive(
    allocator: Allocator,
    base_name: []const u8,
    format: []const u8,
    root_dir: []const u8,
) ![]const u8 {
    _ = allocator;
    _ = base_name;
    _ = format;
    _ = root_dir;
    // TODO: Implement archive creation
    return error.NotImplemented;
}

/// Get terminal size
pub const TerminalSize = struct {
    columns: u16,
    lines: u16,
};

pub fn get_terminal_size() TerminalSize {
    // Try to get from ioctl
    if (@import("builtin").os.tag != .windows) {
        var ws: std.posix.winsize = undefined;
        if (std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0) {
            return .{
                .columns = ws.col,
                .lines = ws.row,
            };
        }
    }
    // Default fallback
    return .{ .columns = 80, .lines = 24 };
}

// ============================================================================
// Tests
// ============================================================================

test "copy file" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a temp file
    const tmp_src = "/tmp/shutil_test_src.txt";
    const tmp_dst = "/tmp/shutil_test_dst.txt";

    {
        const file = try std.fs.cwd().createFile(tmp_src, .{});
        defer file.close();
        try file.writeAll("test content");
    }
    defer std.fs.cwd().deleteFile(tmp_src) catch {};
    defer std.fs.cwd().deleteFile(tmp_dst) catch {};

    const result = try copy(allocator, tmp_src, tmp_dst);
    defer allocator.free(result);

    try testing.expectEqualStrings(tmp_dst, result);

    // Verify content
    const content = try std.fs.cwd().readFileAlloc(allocator, tmp_dst, 1024);
    defer allocator.free(content);
    try testing.expectEqualStrings("test content", content);
}

test "rmtree" {
    // Create a directory tree
    const base = "/tmp/shutil_rmtree_test";
    try std.fs.cwd().makePath(base ++ "/subdir");

    {
        const file = try std.fs.cwd().createFile(base ++ "/file.txt", .{});
        file.close();
    }
    {
        const file = try std.fs.cwd().createFile(base ++ "/subdir/nested.txt", .{});
        file.close();
    }

    // Remove it
    try rmtree(base);

    // Verify it's gone
    const exists = std.fs.cwd().access(base, .{});
    try std.testing.expectError(error.FileNotFound, exists);
}

test "which" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // ls should exist on Unix
    if (@import("builtin").os.tag != .windows) {
        if (try which(allocator, "ls")) |path| {
            defer allocator.free(path);
            try testing.expect(std.mem.indexOf(u8, path, "ls") != null);
        }
    }

    // Nonexistent command
    const result = try which(allocator, "nonexistent_command_xyz");
    try testing.expect(result == null);
}
