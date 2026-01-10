//! importlib.resources.readers - Reader implementations
//! Reference: cpython/Lib/importlib/resources/readers.py

const std = @import("std");
const resources = @import("../resources.zig");

// Re-export from parent module (DRY)
pub const ResourceReader = resources.ResourceReader;
pub const Traversable = resources.Traversable;

/// Reader for filesystem resources
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
};

/// Reader for zip file resources
pub const ZipReader = struct {
    archive_path: []const u8,
    prefix: []const u8,

    pub fn init(archive_path: []const u8, prefix: []const u8) ZipReader {
        return .{ .archive_path = archive_path, .prefix = prefix };
    }

    pub fn isResource(self: *const ZipReader, name: []const u8) bool {
        _ = self;
        _ = name;
        // Would check zip archive
        return false;
    }
};

test "FileReader" {
    const reader = FileReader.init(".");
    try std.testing.expect(!reader.isResource("nonexistent_file.txt"));
}
