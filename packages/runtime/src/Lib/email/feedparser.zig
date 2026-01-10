//! email.feedparser - Feed-style parser for email messages
//! Reference: cpython/Lib/email/feedparser.py
//!
//! CPython __all__: ['FeedParser', 'BytesFeedParser']

const std = @import("std");
const Message = @import("message.zig").Message;
const parser = @import("parser.zig");

// Re-export FeedParser from parser module (DRY)
pub const FeedParser = parser.FeedParser;

/// BytesFeedParser - Feed parser for bytes input
/// CPython: class BytesFeedParser(FeedParser)
pub const BytesFeedParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) BytesFeedParser {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *BytesFeedParser) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn feed(self: *BytesFeedParser, data: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, data);
    }

    pub fn close(self: *BytesFeedParser) !*Message {
        return parser.parseMessage(self.allocator, self.buffer.items);
    }
};

test "FeedParser basic" {
    const allocator = std.testing.allocator;
    var fp = FeedParser.init(allocator);
    defer fp.deinit();

    try fp.feed("Subject: Test\r\n");
    try fp.feed("From: test@example.com\r\n");
    try fp.feed("\r\n");
    try fp.feed("Body text");

    const msg = try fp.close();
    defer {
        msg.deinit();
        allocator.destroy(msg);
    }

    try std.testing.expectEqualStrings("Test", msg.get("Subject").?);
}

test "BytesFeedParser basic" {
    const allocator = std.testing.allocator;
    var fp = BytesFeedParser.init(allocator);
    defer fp.deinit();

    try fp.feed("Subject: Test\r\n\r\nBody");

    const msg = try fp.close();
    defer {
        msg.deinit();
        allocator.destroy(msg);
    }

    try std.testing.expectEqualStrings("Test", msg.get("Subject").?);
}
