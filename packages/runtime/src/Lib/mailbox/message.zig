//! CPython source: Lib/mailbox.py
//!
//! Message and MaildirMessage classes for mailbox operations.
//!
//! Mirrors: CPython Lib/mailbox.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Message
// ============================================================================

/// A message in a mailbox
pub const Message = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    headers: hashmap_helper.StringHashMap([]const u8),
    body: []const u8,
    flags: Flags,

    /// Message flags
    pub const Flags = struct {
        read: bool = false,
        replied: bool = false,
        flagged: bool = false,
        deleted: bool = false,
        draft: bool = false,
        recent: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .headers = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .body = "",
            .flags = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.headers.deinit();
    }

    /// Set a header
    pub fn setHeader(self: *Self, name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }

    /// Get a header
    pub fn getHeader(self: *Self, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// Get all headers
    pub fn getHeaders(self: *Self) hashmap_helper.StringHashMap([]const u8) {
        return self.headers;
    }

    /// Set body
    pub fn setBody(self: *Self, body: []const u8) void {
        self.body = body;
    }

    /// Get body
    pub fn getBody(self: *Self) []const u8 {
        return self.body;
    }

    /// Set flags
    pub fn setFlags(self: *Self, flags: Flags) void {
        self.flags = flags;
    }

    /// Get flags
    pub fn getFlags(self: *Self) Flags {
        return self.flags;
    }

    /// Convert to string representation
    pub fn asString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var it = self.headers.iterator();
        while (it.next()) |entry| {
            try result.appendSlice(entry.key_ptr.*);
            try result.appendSlice(": ");
            try result.appendSlice(entry.value_ptr.*);
            try result.append('\n');
        }
        try result.append('\n');
        try result.appendSlice(self.body);

        return result.toOwnedSlice();
    }

    /// Parse from string
    pub fn fromString(allocator: std.mem.Allocator, data: []const u8) !Self {
        var self = Self.init(allocator);

        // Find header/body separator
        const sep_idx = std.mem.indexOf(u8, data, "\n\n") orelse data.len;

        // Parse headers
        const header_part = data[0..sep_idx];
        var lines = std.mem.splitScalar(u8, header_part, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, ": ")) |colon_idx| {
                const name = line[0..colon_idx];
                const value = line[colon_idx + 2 ..];
                try self.setHeader(name, value);
            }
        }

        // Set body
        if (sep_idx + 2 < data.len) {
            self.body = data[sep_idx + 2 ..];
        }

        return self;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Message init and headers" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.setHeader("From", "test@example.com");
    try msg.setHeader("Subject", "Test");

    try std.testing.expectEqualStrings("test@example.com", msg.getHeader("From").?);
    try std.testing.expectEqualStrings("Test", msg.getHeader("Subject").?);
}

test "Message body" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    msg.setBody("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", msg.getBody());
}

test "Message flags" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    msg.setFlags(.{ .read = true, .flagged = true });
    const flags = msg.getFlags();
    try std.testing.expect(flags.read);
    try std.testing.expect(flags.flagged);
    try std.testing.expect(!flags.deleted);
}
