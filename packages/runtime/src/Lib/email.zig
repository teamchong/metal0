//! Python 'email' module - Email handling package
//!
//! Provides email message parsing, generation, and MIME handling.
//!
//! Mirrors: CPython Lib/email/

const std = @import("std");

// ============================================================================
// email.message - Message class
// ============================================================================

/// Email message class
pub const Message = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    headers: std.ArrayList(Header),
    payload: Payload,
    preamble: ?[]const u8,
    epilogue: ?[]const u8,
    defects: std.ArrayList([]const u8),
    policy: ?*const Policy,

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    pub const Payload = union(enum) {
        text: []const u8,
        parts: std.ArrayList(*Message),
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .headers = std.ArrayList(Header).init(allocator),
            .payload = .{ .text = "" },
            .preamble = null,
            .epilogue = null,
            .defects = std.ArrayList([]const u8).init(allocator),
            .policy = null,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.headers.items) |h| {
            self.allocator.free(h.name);
            self.allocator.free(h.value);
        }
        self.headers.deinit();

        switch (self.payload) {
            .parts => |parts| {
                for (parts.items) |part| {
                    part.deinit();
                    self.allocator.destroy(part);
                }
                parts.deinit();
            },
            .text => |t| {
                if (t.len > 0) self.allocator.free(t);
            },
        }

        if (self.preamble) |p| self.allocator.free(p);
        if (self.epilogue) |e| self.allocator.free(e);
        self.defects.deinit();
    }

    /// Get header value by name (first occurrence)
    pub fn get(self: *const Self, name: []const u8) ?[]const u8 {
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                return h.value;
            }
        }
        return null;
    }

    /// Get header value with default
    pub fn getWithDefault(self: *const Self, name: []const u8, default: []const u8) []const u8 {
        return self.get(name) orelse default;
    }

    /// Get all values for a header
    pub fn getAll(self: *Self, name: []const u8) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                try result.append(h.value);
            }
        }
        return result.toOwnedSlice();
    }

    /// Set a header (replaces existing)
    pub fn set(self: *Self, name: []const u8, value: []const u8) !void {
        // Remove existing headers with this name
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, name)) {
                const h = self.headers.orderedRemove(i);
                self.allocator.free(h.name);
                self.allocator.free(h.value);
            } else {
                i += 1;
            }
        }

        // Add new header
        try self.headers.append(.{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        });
    }

    /// Add a header (allows duplicates)
    pub fn addHeader(self: *Self, name: []const u8, value: []const u8) !void {
        try self.headers.append(.{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        });
    }

    /// Delete a header
    pub fn delete(self: *Self, name: []const u8) void {
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, name)) {
                const h = self.headers.orderedRemove(i);
                self.allocator.free(h.name);
                self.allocator.free(h.value);
            } else {
                i += 1;
            }
        }
    }

    /// Check if header exists
    pub fn contains(self: *const Self, name: []const u8) bool {
        return self.get(name) != null;
    }

    /// Get all header names
    pub fn keys(self: *Self) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();

        for (self.headers.items) |h| {
            const lower = try std.ascii.allocLowerString(self.allocator, h.name);
            defer self.allocator.free(lower);
            if (!seen.contains(lower)) {
                try seen.put(try self.allocator.dupe(u8, lower), {});
                try result.append(h.name);
            }
        }
        return result.toOwnedSlice();
    }

    /// Get all header values
    pub fn values(self: *Self) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        for (self.headers.items) |h| {
            try result.append(h.value);
        }
        return result.toOwnedSlice();
    }

    /// Get all header items
    pub fn items(self: *Self) ![]Header {
        return self.allocator.dupe(Header, self.headers.items);
    }

    /// Get payload as string
    pub fn getPayload(self: *const Self) ?[]const u8 {
        return switch (self.payload) {
            .text => |t| t,
            .parts => null,
        };
    }

    /// Set payload
    pub fn setPayload(self: *Self, payload: []const u8) !void {
        switch (self.payload) {
            .text => |t| {
                if (t.len > 0) self.allocator.free(t);
            },
            .parts => |parts| {
                for (parts.items) |part| {
                    part.deinit();
                    self.allocator.destroy(part);
                }
                parts.deinit();
            },
        }
        self.payload = .{ .text = try self.allocator.dupe(u8, payload) };
    }

    /// Check if multipart
    pub fn isMultipart(self: *const Self) bool {
        return switch (self.payload) {
            .parts => true,
            .text => false,
        };
    }

    /// Get content type
    pub fn getContentType(self: *const Self) []const u8 {
        if (self.get("Content-Type")) |ct| {
            // Parse just the type/subtype
            if (std.mem.indexOf(u8, ct, ";")) |semicolon| {
                return ct[0..semicolon];
            }
            return ct;
        }
        return "text/plain";
    }

    /// Get main content type
    pub fn getContentMainType(self: *const Self) []const u8 {
        const ct = self.getContentType();
        if (std.mem.indexOf(u8, ct, "/")) |slash| {
            return ct[0..slash];
        }
        return ct;
    }

    /// Get content subtype
    pub fn getContentSubtype(self: *const Self) []const u8 {
        const ct = self.getContentType();
        if (std.mem.indexOf(u8, ct, "/")) |slash| {
            return ct[slash + 1 ..];
        }
        return "plain";
    }

    /// Get charset
    pub fn getCharset(self: *const Self) ?[]const u8 {
        if (self.get("Content-Type")) |ct| {
            return parseParam(ct, "charset");
        }
        return null;
    }

    /// Get boundary
    pub fn getBoundary(self: *const Self) ?[]const u8 {
        if (self.get("Content-Type")) |ct| {
            return parseParam(ct, "boundary");
        }
        return null;
    }

    /// Get filename
    pub fn getFilename(self: *const Self) ?[]const u8 {
        if (self.get("Content-Disposition")) |cd| {
            return parseParam(cd, "filename");
        }
        return null;
    }

    /// Attach a part to multipart message
    pub fn attach(self: *Self, part: *Message) !void {
        switch (self.payload) {
            .parts => |*parts| {
                try parts.append(part);
            },
            .text => |t| {
                if (t.len > 0) self.allocator.free(t);
                var parts = std.ArrayList(*Message).init(self.allocator);
                try parts.append(part);
                self.payload = .{ .parts = parts };
            },
        }
    }

    /// Get parts of multipart message
    pub fn getParts(self: *const Self) ?[]*Message {
        return switch (self.payload) {
            .parts => |parts| parts.items,
            .text => null,
        };
    }

    /// Walk through all parts
    pub fn walk(self: *Self) MessageIterator {
        return MessageIterator.init(self);
    }

    /// Convert to string
    pub fn asString(self: *Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        // Write headers
        for (self.headers.items) |h| {
            try result.appendSlice(h.name);
            try result.appendSlice(": ");
            try result.appendSlice(h.value);
            try result.appendSlice("\r\n");
        }

        // Blank line before body
        try result.appendSlice("\r\n");

        // Write payload
        switch (self.payload) {
            .text => |t| {
                try result.appendSlice(t);
            },
            .parts => |parts| {
                const boundary = self.getBoundary() orelse "boundary";
                if (self.preamble) |p| {
                    try result.appendSlice(p);
                    try result.appendSlice("\r\n");
                }
                for (parts.items) |part| {
                    try result.appendSlice("--");
                    try result.appendSlice(boundary);
                    try result.appendSlice("\r\n");
                    const part_str = try part.asString();
                    defer self.allocator.free(part_str);
                    try result.appendSlice(part_str);
                    try result.appendSlice("\r\n");
                }
                try result.appendSlice("--");
                try result.appendSlice(boundary);
                try result.appendSlice("--\r\n");
                if (self.epilogue) |e| {
                    try result.appendSlice(e);
                }
            },
        }

        return result.toOwnedSlice();
    }
};

/// Message iterator for walk()
pub const MessageIterator = struct {
    stack: std.ArrayList(*Message),
    allocator: std.mem.Allocator,

    pub fn init(root: *Message) MessageIterator {
        var stack = std.ArrayList(*Message).init(root.allocator);
        stack.append(root) catch {};
        return .{
            .stack = stack,
            .allocator = root.allocator,
        };
    }

    pub fn deinit(self: *MessageIterator) void {
        self.stack.deinit();
    }

    pub fn next(self: *MessageIterator) ?*Message {
        if (self.stack.items.len == 0) return null;

        const msg = self.stack.pop();

        // Add children to stack in reverse order
        if (msg.getParts()) |parts| {
            var i = parts.len;
            while (i > 0) {
                i -= 1;
                self.stack.append(parts[i]) catch {};
            }
        }

        return msg;
    }
};

/// Parse parameter from header value
fn parseParam(header: []const u8, param_name: []const u8) ?[]const u8 {
    var parts = std.mem.splitScalar(u8, header, ';');
    _ = parts.next(); // Skip main value

    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const name = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            if (std.ascii.eqlIgnoreCase(name, param_name)) {
                var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");
                // Remove quotes
                if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                    value = value[1 .. value.len - 1];
                }
                return value;
            }
        }
    }
    return null;
}

// ============================================================================
// email.mime - MIME message classes
// ============================================================================

pub const mime = struct {
    /// MIME text message
    pub const MIMEText = struct {
        message: Message,

        pub fn init(allocator: std.mem.Allocator, text: []const u8, subtype: []const u8, charset: []const u8) !MIMEText {
            var msg = Message.init(allocator);

            // Build Content-Type header
            var ct_buf: [256]u8 = undefined;
            const ct = try std.fmt.bufPrint(&ct_buf, "text/{s}; charset=\"{s}\"", .{ subtype, charset });
            try msg.set("Content-Type", ct);
            try msg.set("MIME-Version", "1.0");
            try msg.setPayload(text);

            return .{ .message = msg };
        }

        pub fn deinit(self: *MIMEText) void {
            self.message.deinit();
        }
    };

    /// MIME multipart message
    pub const MIMEMultipart = struct {
        message: Message,

        pub fn init(allocator: std.mem.Allocator, subtype: []const u8, boundary: ?[]const u8) !MIMEMultipart {
            var msg = Message.init(allocator);

            // Generate boundary if not provided
            const actual_boundary = boundary orelse "===============boundary===============";

            var ct_buf: [256]u8 = undefined;
            const ct = try std.fmt.bufPrint(&ct_buf, "multipart/{s}; boundary=\"{s}\"", .{ subtype, actual_boundary });
            try msg.set("Content-Type", ct);
            try msg.set("MIME-Version", "1.0");

            // Initialize as multipart
            msg.payload = .{ .parts = std.ArrayList(*Message).init(allocator) };

            return .{ .message = msg };
        }

        pub fn deinit(self: *MIMEMultipart) void {
            self.message.deinit();
        }

        pub fn attach(self: *MIMEMultipart, part: *Message) !void {
            try self.message.attach(part);
        }
    };

    /// MIME base message
    pub const MIMEBase = struct {
        message: Message,

        pub fn init(allocator: std.mem.Allocator, maintype: []const u8, subtype: []const u8) !MIMEBase {
            var msg = Message.init(allocator);

            var ct_buf: [256]u8 = undefined;
            const ct = try std.fmt.bufPrint(&ct_buf, "{s}/{s}", .{ maintype, subtype });
            try msg.set("Content-Type", ct);
            try msg.set("MIME-Version", "1.0");

            return .{ .message = msg };
        }

        pub fn deinit(self: *MIMEBase) void {
            self.message.deinit();
        }
    };

    /// MIME application message
    pub const MIMEApplication = struct {
        message: Message,

        pub fn init(allocator: std.mem.Allocator, data: []const u8, subtype: []const u8) !MIMEApplication {
            var msg = Message.init(allocator);

            var ct_buf: [256]u8 = undefined;
            const ct = try std.fmt.bufPrint(&ct_buf, "application/{s}", .{subtype});
            try msg.set("Content-Type", ct);
            try msg.set("MIME-Version", "1.0");
            try msg.set("Content-Transfer-Encoding", "base64");
            try msg.setPayload(data);

            return .{ .message = msg };
        }

        pub fn deinit(self: *MIMEApplication) void {
            self.message.deinit();
        }
    };

    /// MIME image message
    pub const MIMEImage = struct {
        message: Message,

        pub fn init(allocator: std.mem.Allocator, data: []const u8, subtype: []const u8) !MIMEImage {
            var msg = Message.init(allocator);

            var ct_buf: [256]u8 = undefined;
            const ct = try std.fmt.bufPrint(&ct_buf, "image/{s}", .{subtype});
            try msg.set("Content-Type", ct);
            try msg.set("MIME-Version", "1.0");
            try msg.set("Content-Transfer-Encoding", "base64");
            try msg.setPayload(data);

            return .{ .message = msg };
        }

        pub fn deinit(self: *MIMEImage) void {
            self.message.deinit();
        }
    };

    /// MIME audio message
    pub const MIMEAudio = struct {
        message: Message,

        pub fn init(allocator: std.mem.Allocator, data: []const u8, subtype: []const u8) !MIMEAudio {
            var msg = Message.init(allocator);

            var ct_buf: [256]u8 = undefined;
            const ct = try std.fmt.bufPrint(&ct_buf, "audio/{s}", .{subtype});
            try msg.set("Content-Type", ct);
            try msg.set("MIME-Version", "1.0");
            try msg.set("Content-Transfer-Encoding", "base64");
            try msg.setPayload(data);

            return .{ .message = msg };
        }

        pub fn deinit(self: *MIMEAudio) void {
            self.message.deinit();
        }
    };
};

// ============================================================================
// email.parser - Email parser
// ============================================================================

pub const parser = struct {
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
        var current_value = std.ArrayList(u8).init(allocator);
        defer current_value.deinit();

        var lines = std.mem.splitAny(u8, headers_text, "\r\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Continuation line (starts with whitespace)
            if (line[0] == ' ' or line[0] == '\t') {
                if (current_name != null) {
                    try current_value.append(' ');
                    try current_value.appendSlice(std.mem.trim(u8, line, " \t"));
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
                try current_value.appendSlice(value);
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
                var parts = std.ArrayList(*Message).init(allocator);
                var search_boundary = std.ArrayList(u8).init(allocator);
                defer search_boundary.deinit();

                try search_boundary.appendSlice("--");
                try search_boundary.appendSlice(boundary);

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
                                try parts.append(part);
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

    /// FeedParser for incremental parsing
    pub const FeedParser = struct {
        allocator: std.mem.Allocator,
        buffer: std.ArrayList(u8),

        pub fn init(allocator: std.mem.Allocator) FeedParser {
            return .{
                .allocator = allocator,
                .buffer = std.ArrayList(u8).init(allocator),
            };
        }

        pub fn deinit(self: *FeedParser) void {
            self.buffer.deinit();
        }

        pub fn feed(self: *FeedParser, data: []const u8) !void {
            try self.buffer.appendSlice(data);
        }

        pub fn close(self: *FeedParser) !*Message {
            return parseMessage(self.allocator, self.buffer.items);
        }
    };
};

// ============================================================================
// email.header - Header encoding/decoding
// ============================================================================

pub const header = struct {
    /// Decode a header value
    pub fn decodeHeader(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
        // Simple implementation - just looks for =?charset?encoding?text?= patterns
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var i: usize = 0;
        while (i < value.len) {
            if (i + 2 < value.len and std.mem.startsWith(u8, value[i..], "=?")) {
                // Find closing ?=
                if (std.mem.indexOf(u8, value[i + 2 ..], "?=")) |end| {
                    const encoded = value[i + 2 .. i + 2 + end];

                    // Parse charset?encoding?text
                    var parts = std.mem.splitScalar(u8, encoded, '?');
                    _ = parts.next(); // charset
                    const encoding = parts.next();
                    const text = parts.next();

                    if (encoding != null and text != null) {
                        if (encoding.?[0] == 'B' or encoding.?[0] == 'b') {
                            // Base64 decode
                            const decoded = std.base64.standard.Decoder.calcSizeForSlice(text.?) catch {
                                try result.appendSlice(value[i .. i + 2 + end + 2]);
                                i = i + 2 + end + 2;
                                continue;
                            };
                            var buf = try allocator.alloc(u8, decoded);
                            defer allocator.free(buf);
                            std.base64.standard.Decoder.decode(buf, text.?) catch {
                                try result.appendSlice(value[i .. i + 2 + end + 2]);
                                i = i + 2 + end + 2;
                                continue;
                            };
                            try result.appendSlice(buf);
                        } else if (encoding.?[0] == 'Q' or encoding.?[0] == 'q') {
                            // Quoted-printable decode
                            for (text.?) |c| {
                                if (c == '_') {
                                    try result.append(' ');
                                } else if (c == '=') {
                                    // Would decode hex
                                    try result.append(c);
                                } else {
                                    try result.append(c);
                                }
                            }
                        } else {
                            try result.appendSlice(text.?);
                        }
                    }

                    i = i + 2 + end + 2;
                    continue;
                }
            }

            try result.append(value[i]);
            i += 1;
        }

        return result.toOwnedSlice();
    }

    /// Make a header with the given charset
    pub fn makeHeader(allocator: std.mem.Allocator, decoded_value: []const u8, charset: []const u8) ![]u8 {
        // Check if encoding is needed
        var needs_encoding = false;
        for (decoded_value) |c| {
            if (c > 127) {
                needs_encoding = true;
                break;
            }
        }

        if (!needs_encoding) {
            return allocator.dupe(u8, decoded_value);
        }

        // Encode using base64
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.appendSlice("=?");
        try result.appendSlice(charset);
        try result.appendSlice("?B?");

        const encoded_len = std.base64.standard.Encoder.calcSize(decoded_value.len);
        var encoded = try allocator.alloc(u8, encoded_len);
        defer allocator.free(encoded);
        _ = std.base64.standard.Encoder.encode(encoded, decoded_value);
        try result.appendSlice(encoded);

        try result.appendSlice("?=");

        return result.toOwnedSlice();
    }

    /// Header class for complex headers
    pub const Header = struct {
        parts: std.ArrayList(Part),
        allocator: std.mem.Allocator,

        pub const Part = struct {
            text: []const u8,
            charset: ?[]const u8,
        };

        pub fn init(allocator: std.mem.Allocator) Header {
            return .{
                .parts = std.ArrayList(Part).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Header) void {
            self.parts.deinit();
        }

        pub fn append(self: *Header, text: []const u8, charset: ?[]const u8) !void {
            try self.parts.append(.{
                .text = text,
                .charset = charset,
            });
        }

        pub fn encode(self: *Header) ![]u8 {
            var result = std.ArrayList(u8).init(self.allocator);
            errdefer result.deinit();

            for (self.parts.items, 0..) |part, i| {
                if (i > 0) try result.append(' ');
                const encoded = try makeHeader(self.allocator, part.text, part.charset orelse "utf-8");
                defer self.allocator.free(encoded);
                try result.appendSlice(encoded);
            }

            return result.toOwnedSlice();
        }
    };
};

// ============================================================================
// email.utils - Utilities
// ============================================================================

pub const utils = struct {
    /// Parse an email address
    pub fn parseaddr(address: []const u8) struct { name: []const u8, email: []const u8 } {
        // Simple parsing: "Name <email>" or just "email"
        if (std.mem.indexOf(u8, address, "<")) |lt_pos| {
            if (std.mem.indexOf(u8, address, ">")) |gt_pos| {
                const name = std.mem.trim(u8, address[0..lt_pos], " \t\"");
                const email = address[lt_pos + 1 .. gt_pos];
                return .{ .name = name, .email = email };
            }
        }
        return .{ .name = "", .email = std.mem.trim(u8, address, " \t") };
    }

    /// Format an email address
    pub fn formataddr(allocator: std.mem.Allocator, name: []const u8, email: []const u8) ![]u8 {
        if (name.len == 0) {
            return allocator.dupe(u8, email);
        }

        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        // Check if name needs quoting
        var needs_quote = false;
        for (name) |c| {
            if (c == '"' or c == ',' or c == '<' or c == '>') {
                needs_quote = true;
                break;
            }
        }

        if (needs_quote) {
            try result.append('"');
            for (name) |c| {
                if (c == '"' or c == '\\') {
                    try result.append('\\');
                }
                try result.append(c);
            }
            try result.append('"');
        } else {
            try result.appendSlice(name);
        }

        try result.appendSlice(" <");
        try result.appendSlice(email);
        try result.append('>');

        return result.toOwnedSlice();
    }

    /// Get a list of addresses from a header
    pub fn getaddresses(allocator: std.mem.Allocator, fieldvalues: []const []const u8) ![]struct { name: []const u8, email: []const u8 } {
        var result = std.ArrayList(struct { name: []const u8, email: []const u8 }).init(allocator);
        errdefer result.deinit();

        for (fieldvalues) |value| {
            var parts = std.mem.splitScalar(u8, value, ',');
            while (parts.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " \t");
                if (trimmed.len > 0) {
                    try result.append(parseaddr(trimmed));
                }
            }
        }

        return result.toOwnedSlice();
    }

    /// Format a date for email
    pub fn formatdate(localtime: bool, usegmt: bool) []const u8 {
        _ = localtime;
        _ = usegmt;
        // Would format current time as RFC 2822 date
        return "Thu, 01 Jan 1970 00:00:00 +0000";
    }

    /// Parse a date from email
    pub fn parsedate(date: []const u8) ?struct {
        year: i32,
        month: u8,
        day: u8,
        hour: u8,
        minute: u8,
        second: u8,
    } {
        _ = date;
        // Would parse RFC 2822 date
        return null;
    }

    /// Create a unique message ID
    pub fn makeMessageId(allocator: std.mem.Allocator, domain: ?[]const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.append('<');

        // Generate random part
        var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = rng.random();
        var buf: [16]u8 = undefined;
        for (&buf) |*b| {
            b.* = random.int(u8);
        }

        const hex = "0123456789abcdef";
        for (buf) |b| {
            try result.append(hex[b >> 4]);
            try result.append(hex[b & 0x0F]);
        }

        try result.append('@');
        try result.appendSlice(domain orelse "localhost");
        try result.append('>');

        return result.toOwnedSlice();
    }

    /// Quote a string for use in headers
    pub fn quoteString(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        try result.append('"');
        for (str) |c| {
            if (c == '"' or c == '\\') {
                try result.append('\\');
            }
            try result.append(c);
        }
        try result.append('"');

        return result.toOwnedSlice();
    }
};

// ============================================================================
// email.policy - Email policies
// ============================================================================

pub const Policy = struct {
    max_line_length: usize,
    utf8: bool,
    cte_type: []const u8,

    pub const default = Policy{
        .max_line_length = 78,
        .utf8 = false,
        .cte_type = "7bit",
    };

    pub const compat32 = Policy{
        .max_line_length = 998,
        .utf8 = false,
        .cte_type = "7bit",
    };

    pub const smtp = Policy{
        .max_line_length = 998,
        .utf8 = false,
        .cte_type = "7bit",
    };

    pub const smtputf8 = Policy{
        .max_line_length = 998,
        .utf8 = true,
        .cte_type = "8bit",
    };
};

// ============================================================================
// email.encoders - Content transfer encodings
// ============================================================================

pub const encoders = struct {
    /// Encode as base64
    pub fn encodeBase64(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        const encoded_len = std.base64.standard.Encoder.calcSize(data.len);
        var encoded = try allocator.alloc(u8, encoded_len);
        _ = std.base64.standard.Encoder.encode(encoded, data);
        return encoded;
    }

    /// Encode as quoted-printable
    pub fn encodeQuopri(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var line_len: usize = 0;
        const hex = "0123456789ABCDEF";

        for (data) |c| {
            if (c == '\r' or c == '\n') {
                try result.append(c);
                line_len = 0;
            } else if (c >= 33 and c <= 126 and c != '=') {
                if (line_len >= 75) {
                    try result.appendSlice("=\r\n");
                    line_len = 0;
                }
                try result.append(c);
                line_len += 1;
            } else {
                if (line_len >= 73) {
                    try result.appendSlice("=\r\n");
                    line_len = 0;
                }
                try result.append('=');
                try result.append(hex[c >> 4]);
                try result.append(hex[c & 0x0F]);
                line_len += 3;
            }
        }

        return result.toOwnedSlice();
    }

    /// Encode as 7bit (no-op, just validates)
    pub fn encode7bit(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        return allocator.dupe(u8, data);
    }

    /// Encode as 8bit (no-op)
    pub fn encode8bit(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        return allocator.dupe(u8, data);
    }
};

// ============================================================================
// email.generator - Message generation
// ============================================================================

pub const generator = struct {
    pub const Generator = struct {
        allocator: std.mem.Allocator,
        max_header_len: usize,

        pub fn init(allocator: std.mem.Allocator, max_header_len: usize) Generator {
            return .{
                .allocator = allocator,
                .max_header_len = max_header_len,
            };
        }

        pub fn flatten(self: *Generator, msg: *Message) ![]u8 {
            _ = self;
            return msg.asString();
        }
    };

    pub const BytesGenerator = Generator;
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a simple text email
pub fn createTextMessage(allocator: std.mem.Allocator, from: []const u8, to: []const u8, subject: []const u8, body: []const u8) !*Message {
    var msg = try allocator.create(Message);
    msg.* = Message.init(allocator);

    try msg.set("From", from);
    try msg.set("To", to);
    try msg.set("Subject", subject);
    try msg.set("MIME-Version", "1.0");
    try msg.set("Content-Type", "text/plain; charset=\"utf-8\"");
    try msg.setPayload(body);

    return msg;
}

// ============================================================================
// Tests
// ============================================================================

test "Message basic" {
    const allocator = std.testing.allocator;

    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.set("Subject", "Test");
    try msg.set("From", "sender@example.com");

    try std.testing.expectEqualStrings("Test", msg.get("Subject").?);
    try std.testing.expectEqualStrings("sender@example.com", msg.get("From").?);
}

test "Message headers case insensitive" {
    const allocator = std.testing.allocator;

    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.set("Content-Type", "text/plain");
    try std.testing.expectEqualStrings("text/plain", msg.get("content-type").?);
    try std.testing.expectEqualStrings("text/plain", msg.get("CONTENT-TYPE").?);
}

test "Message content type" {
    const allocator = std.testing.allocator;

    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.set("Content-Type", "text/html; charset=\"utf-8\"");

    try std.testing.expectEqualStrings("text/html", msg.getContentType());
    try std.testing.expectEqualStrings("text", msg.getContentMainType());
    try std.testing.expectEqualStrings("html", msg.getContentSubtype());
    try std.testing.expectEqualStrings("utf-8", msg.getCharset().?);
}

test "parseaddr" {
    const result1 = utils.parseaddr("John Doe <john@example.com>");
    try std.testing.expectEqualStrings("John Doe", result1.name);
    try std.testing.expectEqualStrings("john@example.com", result1.email);

    const result2 = utils.parseaddr("simple@example.com");
    try std.testing.expectEqualStrings("", result2.name);
    try std.testing.expectEqualStrings("simple@example.com", result2.email);
}

test "formataddr" {
    const allocator = std.testing.allocator;

    const result1 = try utils.formataddr(allocator, "John Doe", "john@example.com");
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("John Doe <john@example.com>", result1);

    const result2 = try utils.formataddr(allocator, "", "simple@example.com");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("simple@example.com", result2);
}

test "parser basic" {
    const allocator = std.testing.allocator;

    const email_text =
        \\Subject: Test Email
        \\From: sender@example.com
        \\To: recipient@example.com
        \\
        \\This is the body.
    ;

    const msg = try parser.parseMessage(allocator, email_text);
    defer {
        msg.deinit();
        allocator.destroy(msg);
    }

    try std.testing.expectEqualStrings("Test Email", msg.get("Subject").?);
    try std.testing.expectEqualStrings("sender@example.com", msg.get("From").?);
    try std.testing.expectEqualStrings("This is the body.", msg.getPayload().?);
}

test "MIMEText" {
    const allocator = std.testing.allocator;

    var mime_text = try mime.MIMEText.init(allocator, "Hello, world!", "plain", "utf-8");
    defer mime_text.deinit();

    try std.testing.expectEqualStrings("text/plain", mime_text.message.getContentMainType() ++ "/" ++ mime_text.message.getContentSubtype());
}

test "encode base64" {
    const allocator = std.testing.allocator;

    const encoded = try encoders.encodeBase64(allocator, "Hello");
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("SGVsbG8=", encoded);
}

test "quote string" {
    const allocator = std.testing.allocator;

    const quoted = try utils.quoteString(allocator, "test \"value\"");
    defer allocator.free(quoted);

    try std.testing.expectEqualStrings("\"test \\\"value\\\"\"", quoted);
}
