//! importlib.simple - Simple resource container
//! Reference: cpython/Lib/importlib/simple.py
//!
//! Provides a simple in-memory resource container for testing and embedding.

const std = @import("std");
const resources = @import("resources.zig");

// Re-export from resources module (DRY)
pub const ResourceReader = resources.ResourceReader;
pub const Traversable = resources.Traversable;

/// Simple in-memory resource container
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

    pub fn contents(self: *const SimpleReader, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8){};
        var iter = self.data.keyIterator();
        while (iter.next()) |key| {
            try result.append(allocator, key.*);
        }
        return result;
    }
};

/// Simple traversable backed by in-memory data
pub const SimpleTraversable = struct {
    name: []const u8,
    data: ?[]const u8 = null,
    children: std.StringHashMap(*SimpleTraversable),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) SimpleTraversable {
        return .{
            .name = name,
            .children = std.StringHashMap(*SimpleTraversable).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SimpleTraversable) void {
        self.children.deinit();
    }

    pub fn isFile(self: *const SimpleTraversable) bool {
        return self.data != null;
    }

    pub fn isDir(self: *const SimpleTraversable) bool {
        return self.data == null and self.children.count() > 0;
    }

    pub fn addChild(self: *SimpleTraversable, child: *SimpleTraversable) !void {
        try self.children.put(child.name, child);
    }

    pub fn getChild(self: *const SimpleTraversable, name: []const u8) ?*SimpleTraversable {
        return self.children.get(name);
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

test "SimpleTraversable" {
    const allocator = std.testing.allocator;
    var root = SimpleTraversable.init(allocator, "root");
    defer root.deinit();

    try std.testing.expect(!root.isFile());
}
