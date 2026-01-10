//! test.test_email - Email handling tests
const std = @import("std");

pub const Message = struct {
    headers: std.StringHashMap([]const u8),
    body: []const u8 = "",
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .headers = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.headers.deinit();
    }
    
    pub fn setHeader(self: *@This(), name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }
    
    pub fn getHeader(self: @This(), name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }
    
    pub fn setPayload(self: *@This(), payload: []const u8) void {
        self.body = payload;
    }
    
    pub fn getPayload(self: @This()) []const u8 {
        return self.body;
    }
    
    pub fn asString(self: @This(), writer: anytype) !void {
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{entry.key_ptr.*, entry.value_ptr.*});
        }
        try writer.writeAll("\r\n");
        try writer.writeAll(self.body);
    }
};

pub const Address = struct {
    name: ?[]const u8 = null,
    email: []const u8,
    
    pub fn parse(addr: []const u8) !@This() {
        if (std.mem.indexOf(u8, addr, "<")) |start| {
            if (std.mem.indexOf(u8, addr, ">")) |end| {
                return .{
                    .name = if (start > 0) std.mem.trim(u8, addr[0..start], " ") else null,
                    .email = addr[start+1..end],
                };
            }
        }
        return .{ .email = addr };
    }
    
    pub fn format(self: @This(), writer: anytype) !void {
        if (self.name) |n| {
            try writer.print("{s} <{s}>", .{n, self.email});
        } else {
            try writer.writeAll(self.email);
        }
    }
};

pub const MIMEText = struct {
    message: Message,
    subtype: []const u8 = "plain",
    charset: []const u8 = "utf-8",
    
    pub fn init(allocator: std.mem.Allocator, text: []const u8) !@This() {
        var msg = Message.init(allocator);
        try msg.setHeader("Content-Type", "text/plain; charset=utf-8");
        try msg.setHeader("MIME-Version", "1.0");
        msg.setPayload(text);
        return .{ .message = msg };
    }
    
    pub fn deinit(self: *@This()) void {
        self.message.deinit();
    }
};

pub const MIMEMultipart = struct {
    message: Message,
    parts: std.ArrayList(Message),
    boundary: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !@This() {
        var msg = Message.init(allocator);
        try msg.setHeader("MIME-Version", "1.0");
        return .{
            .allocator = allocator,
            .message = msg,
            .parts = std.ArrayList(Message).init(allocator),
            .boundary = "----=_Part_0_123456789",
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.message.deinit();
        self.parts.deinit();
    }
    
    pub fn attach(self: *@This(), part: Message) !void {
        try self.parts.append(part);
    }
};

test "message_headers" {
    var msg = Message.init(std.testing.allocator);
    defer msg.deinit();
    try msg.setHeader("Subject", "Test");
    try msg.setHeader("From", "test@example.com");
    try std.testing.expectEqualStrings("Test", msg.getHeader("Subject").?);
}

test "message_payload" {
    var msg = Message.init(std.testing.allocator);
    defer msg.deinit();
    msg.setPayload("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", msg.getPayload());
}

test "address_parse_simple" {
    const addr = try Address.parse("test@example.com");
    try std.testing.expectEqualStrings("test@example.com", addr.email);
    try std.testing.expect(addr.name == null);
}

test "address_parse_with_name" {
    const addr = try Address.parse("John Doe <john@example.com>");
    try std.testing.expectEqualStrings("john@example.com", addr.email);
    try std.testing.expectEqualStrings("John Doe", addr.name.?);
}

test "mime_text" {
    var mime = try MIMEText.init(std.testing.allocator, "Hello");
    defer mime.deinit();
    try std.testing.expectEqualStrings("Hello", mime.message.getPayload());
}
