//! importlib.metadata._adapters - Adapter utilities
//! Reference: cpython/Lib/importlib/metadata/_adapters.py

const std = @import("std");
const metadata = @import("../metadata.zig");

// Re-export from parent module (DRY)
pub const PackageMetadata = metadata.PackageMetadata;

/// Message - Wrapper for email message-like metadata
/// CPython: class Message
pub const Message = struct {
    data: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Message {
        return .{
            .data = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Message) void {
        self.data.deinit();
    }

    pub fn get(self: *const Message, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn getAll(self: *const Message, key: []const u8) ?[]const u8 {
        return self.get(key);
    }

    pub fn put(self: *Message, key: []const u8, value: []const u8) !void {
        try self.data.put(key, value);
    }
};

/// Parse metadata from text
pub fn parseMetadata(allocator: std.mem.Allocator, text: []const u8) !Message {
    var msg = Message.init(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
        const key = std.mem.trim(u8, line[0..colon_pos], " \t");
        const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
        try msg.put(key, value);
    }
    return msg;
}

test "Message" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.put("Name", "testpkg");
    try std.testing.expectEqualStrings("testpkg", msg.get("Name").?);
}

test "parseMetadata" {
    const allocator = std.testing.allocator;
    const text = "Name: testpkg\nVersion: 1.0.0";
    var msg = try parseMetadata(allocator, text);
    defer msg.deinit();

    try std.testing.expectEqualStrings("testpkg", msg.get("Name").?);
    try std.testing.expectEqualStrings("1.0.0", msg.get("Version").?);
}
