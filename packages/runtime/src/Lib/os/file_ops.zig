/// File and directory operations
/// CPython Reference: https://docs.python.org/3.12/library/os.html#files-and-directories
const std = @import("std");

/// List directory contents
pub fn listdir(allocator: std.mem.Allocator, dir_path: []const u8) ![][]const u8 {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var entries: std.ArrayList([]const u8) = .{};
    errdefer {
        for (entries.items) |entry| allocator.free(entry);
        entries.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try entries.append(allocator, try allocator.dupe(u8, entry.name));
    }

    return entries.toOwnedSlice(allocator);
}

/// Create a directory
pub fn mkdir(dir_path: []const u8) !void {
    try std.fs.cwd().makeDir(dir_path);
}

/// Create a directory and all parent directories
pub fn makedirs(dir_path: []const u8) !void {
    std.fs.cwd().makePath(dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

/// Remove a file
pub fn remove(file_path: []const u8) !void {
    try std.fs.cwd().deleteFile(file_path);
}

/// Alias for remove
pub const unlink = remove;

/// Remove an empty directory
pub fn rmdir(dir_path: []const u8) !void {
    try std.fs.cwd().deleteDir(dir_path);
}

/// Remove a directory tree recursively
pub fn removedirs(dir_path: []const u8) !void {
    try std.fs.cwd().deleteTree(dir_path);
}

/// Rename a file or directory
pub fn rename(src: []const u8, dst: []const u8) !void {
    try std.fs.cwd().rename(src, dst);
}

/// Check if a path exists
pub fn exists(file_path: []const u8) bool {
    std.fs.cwd().access(file_path, .{}) catch return false;
    return true;
}

/// Check if path is a file
pub fn isfile(file_path: []const u8) bool {
    const file_stat = std.fs.cwd().statFile(file_path) catch return false;
    return file_stat.kind == .file;
}

/// Check if path is a directory
pub fn isdir(dir_path: []const u8) bool {
    var dir = std.fs.cwd().openDir(dir_path, .{}) catch return false;
    dir.close();
    return true;
}

/// Get file size
pub fn getsize(file_path: []const u8) !u64 {
    const file_stat = try std.fs.cwd().statFile(file_path);
    return file_stat.size;
}
