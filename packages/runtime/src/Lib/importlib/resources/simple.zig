//! importlib.resources.simple - Simple resource implementations
//! Reference: cpython/Lib/importlib/resources/simple.py

const std = @import("std");
const resources = @import("../resources.zig");

// Re-export from parent module (DRY)
pub const ResourceReader = resources.ResourceReader;
pub const Traversable = resources.Traversable;

/// Simple container for resources
pub const SimpleReader = struct {
    data: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SimpleReader {
        return .{
            .data = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SimpleReader) void {
        self.data.deinit();
    }

    pub fn addResource(self: *SimpleReader, name: []const u8, content: []const u8) !void {
        try self.data.put(name, content);
    }

    pub fn isResource(self: *const SimpleReader, name: []const u8) bool {
        return self.data.contains(name);
    }

    pub fn getResource(self: *const SimpleReader, name: []const u8) ?[]const u8 {
        return self.data.get(name);
    }
};

test "SimpleReader" {
    const allocator = std.testing.allocator;
    var reader = SimpleReader.init(allocator);
    defer reader.deinit();

    try reader.addResource("test.txt", "hello world");
    try std.testing.expect(reader.isResource("test.txt"));
    try std.testing.expectEqualStrings("hello world", reader.getResource("test.txt").?);
}
