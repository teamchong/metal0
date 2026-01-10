//! importlib.readers - Reader implementations for package resources
//! Reference: cpython/Lib/importlib/readers.py
//!
//! This module provides reader implementations for different package formats.

const std = @import("std");
const resources = @import("resources.zig");

// Re-export from resources module (DRY)
pub const ResourceReader = resources.ResourceReader;
pub const Traversable = resources.Traversable;

/// Reader for filesystem-based packages
pub const FileReader = struct {
    base_path: []const u8,

    pub fn init(base_path: []const u8) FileReader {
        return .{ .base_path = base_path };
    }

    pub fn openResource(self: *const FileReader, resource: []const u8) !std.fs.File {
        var path_buf: [512]u8 = undefined;
        const full_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ self.base_path, resource });
        return std.fs.cwd().openFile(full_path, .{});
    }

    pub fn isResource(self: *const FileReader, name: []const u8) bool {
        var path_buf: [512]u8 = undefined;
        const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ self.base_path, name }) catch return false;
        std.fs.cwd().access(full_path, .{}) catch return false;
        return true;
    }

    pub fn contents(self: *const FileReader, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8){};
        const dir = std.fs.cwd().openDir(self.base_path, .{ .iterate = true }) catch return result;
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            try result.append(allocator, try allocator.dupe(u8, entry.name));
        }
        return result;
    }
};

/// Reader for zip-based packages (wheel, egg)
pub const ZipReader = struct {
    archive_path: []const u8,
    prefix: []const u8,

    pub fn init(archive_path: []const u8, prefix: []const u8) ZipReader {
        return .{ .archive_path = archive_path, .prefix = prefix };
    }

    pub fn isResource(self: *const ZipReader, name: []const u8) bool {
        _ = self;
        _ = name;
        // Would check zip archive entries
        return false;
    }

    pub fn openResource(self: *const ZipReader, resource: []const u8) !std.fs.File {
        _ = self;
        _ = resource;
        return error.NotImplemented;
    }
};

/// Namespace reader for namespace packages
pub const NamespaceReader = struct {
    paths: []const []const u8,

    pub fn init(paths: []const []const u8) NamespaceReader {
        return .{ .paths = paths };
    }

    pub fn isResource(self: *const NamespaceReader, name: []const u8) bool {
        for (self.paths) |path| {
            var buf: [512]u8 = undefined;
            const full_path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ path, name }) catch continue;
            std.fs.cwd().access(full_path, .{}) catch continue;
            return true;
        }
        return false;
    }
};

test "FileReader" {
    const reader = FileReader.init(".");
    try std.testing.expect(!reader.isResource("nonexistent_file_12345.txt"));
}

test "ZipReader" {
    const reader = ZipReader.init("test.zip", "");
    try std.testing.expect(!reader.isResource("test.txt"));
}
