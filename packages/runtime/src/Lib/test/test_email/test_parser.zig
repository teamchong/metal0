//! test.test_email.test_parser - Email parser tests
const std = @import("std");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    policy: Policy = .{},
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }
    
    pub fn parsestr(self: @This(), text: []const u8) !Message {
        var msg = Message.init(self.allocator);
        var lines = std.mem.splitScalar(u8, text, '\n');
        var in_headers = true;
        var body = std.ArrayList(u8).init(self.allocator);
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, "\r");
            if (in_headers) {
                if (trimmed.len == 0) {
                    in_headers = false;
                    continue;
                }
                if (std.mem.indexOf(u8, trimmed, ":")) |idx| {
                    const name = trimmed[0..idx];
                    const value = std.mem.trim(u8, trimmed[idx+1..], " ");
                    try msg.headers.put(name, value);
                }
            } else {
                try body.appendSlice(trimmed);
                try body.append('\n');
            }
        }
        msg.body = body.items;
        return msg;
    }
    
    pub fn parsebytes(self: @This(), data: []const u8) !Message {
        return self.parsestr(data);
    }
};

pub const BytesParser = Parser;
pub const HeaderParser = Parser;
pub const BytesHeaderParser = Parser;

pub const FeedParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.buffer.deinit();
    }
    
    pub fn feed(self: *@This(), data: []const u8) !void {
        try self.buffer.appendSlice(data);
    }
    
    pub fn close(self: *@This()) !Message {
        const parser = Parser.init(self.allocator);
        return parser.parsestr(self.buffer.items);
    }
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

pub const Policy = struct {
    max_line_length: usize = 998,
    utf8: bool = false,
    raise_on_defect: bool = false,
};

test "parser_simple" {
    const parser = Parser.init(std.testing.allocator);
    var msg = try parser.parsestr("Subject: Test\r\n\r\nBody");
    defer msg.deinit();
    try std.testing.expectEqualStrings("Test", msg.headers.get("Subject").?);
}

test "feed_parser" {
    var fp = FeedParser.init(std.testing.allocator);
    defer fp.deinit();
    try fp.feed("From: a@b.com\r\n");
    try fp.feed("\r\n");
    try fp.feed("Hello");
    var msg = try fp.close();
    defer msg.deinit();
    try std.testing.expectEqualStrings("a@b.com", msg.headers.get("From").?);
}
