//! test.test_email.test_message - Email message tests
const std = @import("std");

pub const EmailMessage = struct {
    headers: std.StringHashMap([]const u8),
    payload: Payload,
    allocator: std.mem.Allocator,
    
    pub const Payload = union(enum) {
        text: []const u8,
        parts: std.ArrayList(*EmailMessage),
    };
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .payload = .{ .text = "" },
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.headers.deinit();
        if (self.payload == .parts) self.payload.parts.deinit();
    }
    
    pub fn setHeader(self: *@This(), name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }
    
    pub fn getHeader(self: @This(), name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }
    
    pub fn delHeader(self: *@This(), name: []const u8) bool {
        return self.headers.remove(name);
    }
    
    pub fn setPayload(self: *@This(), text: []const u8) void {
        self.payload = .{ .text = text };
    }
    
    pub fn getPayload(self: @This()) []const u8 {
        return switch (self.payload) {
            .text => |t| t,
            .parts => "",
        };
    }
    
    pub fn isMultipart(self: @This()) bool {
        return self.payload == .parts;
    }
    
    pub fn addPart(self: *@This(), part: *EmailMessage) !void {
        if (self.payload != .parts) {
            self.payload = .{ .parts = std.ArrayList(*EmailMessage).init(self.allocator) };
        }
        try self.payload.parts.append(part);
    }
    
    pub fn getParts(self: @This()) []const *EmailMessage {
        return switch (self.payload) {
            .parts => |p| p.items,
            .text => &.{},
        };
    }
    
    pub fn walk(self: *@This()) MessageIterator {
        return MessageIterator.init(self);
    }
};

pub const MessageIterator = struct {
    stack: std.ArrayList(*EmailMessage),
    
    pub fn init(root: *EmailMessage) @This() {
        var stack = std.ArrayList(*EmailMessage).init(root.allocator);
        stack.append(root) catch {};
        return .{ .stack = stack };
    }
    
    pub fn next(self: *@This()) ?*EmailMessage {
        if (self.stack.items.len == 0) return null;
        const msg = self.stack.pop();
        for (msg.getParts()) |part| {
            self.stack.append(part) catch {};
        }
        return msg;
    }
};

test "message_init" {
    var msg = EmailMessage.init(std.testing.allocator);
    defer msg.deinit();
    try std.testing.expect(!msg.isMultipart());
}

test "message_headers" {
    var msg = EmailMessage.init(std.testing.allocator);
    defer msg.deinit();
    try msg.setHeader("Subject", "Test");
    try msg.setHeader("From", "a@b.com");
    try std.testing.expectEqualStrings("Test", msg.getHeader("Subject").?);
    try std.testing.expect(msg.delHeader("From"));
    try std.testing.expect(msg.getHeader("From") == null);
}

test "message_payload" {
    var msg = EmailMessage.init(std.testing.allocator);
    defer msg.deinit();
    msg.setPayload("Hello World");
    try std.testing.expectEqualStrings("Hello World", msg.getPayload());
}
