//! test.test_email.test_generator - Email generator tests
const std = @import("std");

pub const Generator = struct {
    policy: Policy = .{},
    
    pub fn flatten(self: @This(), msg: *Message, writer: anytype) !void {
        _ = self;
        var it = msg.headers.iterator();
        while (it.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{entry.key_ptr.*, entry.value_ptr.*});
        }
        try writer.writeAll("\r\n");
        try writer.writeAll(msg.body);
    }
};

pub const BytesGenerator = Generator;

pub const DecodedGenerator = struct {
    policy: Policy = .{},
    
    pub fn flatten(self: @This(), msg: *Message, writer: anytype) !void {
        _ = self;
        var it = msg.headers.iterator();
        while (it.next()) |entry| {
            try writer.print("{s}: {s}\n", .{entry.key_ptr.*, entry.value_ptr.*});
        }
        try writer.writeAll("\n");
        try writer.writeAll(msg.body);
    }
};

pub const Policy = struct {
    max_line_length: usize = 78,
    linesep: []const u8 = "\r\n",
    cte_type: []const u8 = "8bit",
    utf8: bool = false,
};

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
};

test "generator_flatten" {
    var msg = Message.init(std.testing.allocator);
    defer msg.deinit();
    try msg.headers.put("Subject", "Test");
    msg.body = "Hello";
    
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const gen = Generator{};
    try gen.flatten(&msg, stream.writer());
    
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Subject: Test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Hello") != null);
}
