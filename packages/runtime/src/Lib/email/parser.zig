//! Email parser classes and functions
//!
//! Provides parsing functionality for email messages.

const std = @import("std");
const Message = @import("message.zig").Message;

/// Parse email message from string
pub fn parseMessage(allocator: std.mem.Allocator, text: []const u8) !*Message {
    var msg = try allocator.create(Message);
    msg.* = Message.init(allocator);
    errdefer {
        msg.deinit();
        allocator.destroy(msg);
    }

    // Find header/body separator
    var header_end: usize = 0;
    if (std.mem.indexOf(u8, text, "\r\n\r\n")) |pos| {
        header_end = pos;
    } else if (std.mem.indexOf(u8, text, "\n\n")) |pos| {
        header_end = pos;
    } else {
        header_end = text.len;
    }

    // Parse headers
    const headers_text = text[0..header_end];
    var current_name: ?[]const u8 = null;
    var current_value: std.ArrayList(u8) = .{};
    defer current_value.deinit(allocator);

    var lines = std.mem.splitAny(u8, headers_text, "\r\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Continuation line (starts with whitespace)
        if (line[0] == ' ' or line[0] == '\t') {
            if (current_name != null) {
                try current_value.append(allocator, ' ');
                try current_value.appendSlice(allocator, std.mem.trim(u8, line, " \t"));
            }
            continue;
        }

        // Save previous header
        if (current_name) |name| {
            try msg.addHeader(name, current_value.items);
            current_value.clearRetainingCapacity();
        }

        // Parse new header
        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            current_name = line[0..colon_pos];
            const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
            try current_value.appendSlice(allocator, value);
        }
    }

    // Save last header
    if (current_name) |name| {
        try msg.addHeader(name, current_value.items);
    }

    // Parse body
    const body_start = if (header_end < text.len) blk: {
        var pos = header_end;
        while (pos < text.len and (text[pos] == '\r' or text[pos] == '\n')) {
            pos += 1;
        }
        break :blk pos;
    } else header_end;

    if (body_start < text.len) {
        const body = text[body_start..];

        // Check if multipart
        if (msg.getBoundary()) |boundary| {
            var parts: std.ArrayList(*Message) = .{};
            var search_boundary: std.ArrayList(u8) = .{};
            defer search_boundary.deinit(allocator);

            try search_boundary.appendSlice(allocator, "--");
            try search_boundary.appendSlice(allocator, boundary);

            var part_start: ?usize = null;
            var i: usize = 0;

            while (i < body.len) {
                if (std.mem.startsWith(u8, body[i..], search_boundary.items)) {
                    if (part_start) |start| {
                        // End of previous part
                        var end = i;
                        // Remove trailing CRLF
                        while (end > start and (body[end - 1] == '\r' or body[end - 1] == '\n')) {
                            end -= 1;
                        }
                        if (end > start) {
                            const part = try parseMessage(allocator, body[start..end]);
                            try parts.append(allocator, part);
                        }
                    }

                    // Skip boundary
                    i += search_boundary.items.len;

                    // Check for terminator
                    if (i + 2 <= body.len and std.mem.eql(u8, body[i .. i + 2], "--")) {
                        break;
                    }

                    // Skip CRLF after boundary
                    while (i < body.len and (body[i] == '\r' or body[i] == '\n')) {
                        i += 1;
                    }
                    part_start = i;
                } else {
                    i += 1;
                }
            }

            msg.payload = .{ .parts = parts };
        } else {
            try msg.setPayload(body);
        }
    }

    return msg;
}

/// Parser for parsing text messages
pub const Parser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Parser {
        return .{ .allocator = allocator };
    }

    pub fn parsestr(self: *Parser, text: []const u8) !*Message {
        return parseMessage(self.allocator, text);
    }
};

/// BytesParser for parsing bytes
pub const BytesParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BytesParser {
        return .{ .allocator = allocator };
    }

    pub fn parsebytes(self: *BytesParser, data: []const u8) !*Message {
        return parseMessage(self.allocator, data);
    }
};

/// HeaderParser for parsing just headers
pub const HeaderParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HeaderParser {
        return .{ .allocator = allocator };
    }

    pub fn parsestr(self: *HeaderParser, text: []const u8) !*Message {
        var msg = try self.allocator.create(Message);
        msg.* = Message.init(self.allocator);
        errdefer {
            msg.deinit();
            self.allocator.destroy(msg);
        }

        // Parse only headers (no body)
        var current_name: ?[]const u8 = null;
        var current_value: std.ArrayList(u8) = .{};
        defer current_value.deinit(self.allocator);

        var lines = std.mem.splitAny(u8, text, "\r\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Continuation line (starts with whitespace)
            if (line[0] == ' ' or line[0] == '\t') {
                if (current_name != null) {
                    try current_value.append(self.allocator, ' ');
                    try current_value.appendSlice(self.allocator, std.mem.trim(u8, line, " \t"));
                }
                continue;
            }

            // Save previous header
            if (current_name) |name| {
                try msg.addHeader(name, current_value.items);
                current_value.clearRetainingCapacity();
            }

            // Parse new header
            if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
                current_name = line[0..colon_pos];
                const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
                try current_value.appendSlice(self.allocator, value);
            }
        }

        // Save last header
        if (current_name) |name| {
            try msg.addHeader(name, current_value.items);
        }

        return msg;
    }
};

/// FeedParser for incremental parsing
pub const FeedParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) FeedParser {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *FeedParser) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn feed(self: *FeedParser, data: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, data);
    }

    pub fn close(self: *FeedParser) !*Message {
        return parseMessage(self.allocator, self.buffer.items);
    }
};
