//! importlib.metadata._meta - Meta type definitions
//! Reference: cpython/Lib/importlib/metadata/_meta.py
//!
//! CPython exports: PackageMetadata, SimplePath

const std = @import("std");
const metadata = @import("../metadata.zig");

// Re-export from parent module (DRY)
pub const PackageMetadata = metadata.PackageMetadata;

/// SimplePath - Protocol for path-like objects
/// CPython: class SimplePath(Protocol)
pub const SimplePath = struct {
    path: []const u8,

    pub fn init(path: []const u8) SimplePath {
        return .{ .path = path };
    }

    pub fn joinpath(self: *const SimplePath, allocator: std.mem.Allocator, child: []const u8) !SimplePath {
        const new_path = try std.fs.path.join(allocator, &.{ self.path, child });
        return SimplePath.init(new_path);
    }

    pub fn readText(self: *const SimplePath, allocator: std.mem.Allocator) ![]u8 {
        const file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, std.math.maxInt(usize));
    }

    pub fn exists(self: *const SimplePath) bool {
        std.fs.cwd().access(self.path, .{}) catch return false;
        return true;
    }

    pub fn parent(self: *const SimplePath) SimplePath {
        const dir = std.fs.path.dirname(self.path) orelse ".";
        return SimplePath.init(dir);
    }
};

test "SimplePath" {
    const sp = SimplePath.init("test.txt");
    try std.testing.expectEqualStrings("test.txt", sp.path);
}
