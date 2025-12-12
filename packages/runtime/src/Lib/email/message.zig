//! Email message class and related types
//!
//! Provides the core Message class for email message handling.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const Policy = @import("policy.zig").Policy;

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
            .headers = .{},
            .payload = .{ .text = "" },
            .preamble = null,
            .epilogue = null,
            .defects = .{},
            .policy = null,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.headers.items) |h| {
            self.allocator.free(h.name);
            self.allocator.free(h.value);
        }
        self.headers.deinit(self.allocator);

        switch (self.payload) {
            .parts => |parts| {
                for (parts.items) |part| {
                    part.deinit();
                    self.allocator.destroy(part);
                }
                var mut_parts = parts;
                mut_parts.deinit(self.allocator);
            },
            .text => |t| {
                if (t.len > 0) self.allocator.free(t);
            },
        }

        if (self.preamble) |p| self.allocator.free(p);
        if (self.epilogue) |e| self.allocator.free(e);
        self.defects.deinit(self.allocator);
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
        var result: std.ArrayList([]const u8) = .{};
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                try result.append(self.allocator, h.value);
            }
        }
        return result.toOwnedSlice(self.allocator);
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
        try self.headers.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        });
    }

    /// Add a header (allows duplicates)
    pub fn addHeader(self: *Self, name: []const u8, value: []const u8) !void {
        try self.headers.append(self.allocator, .{
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
        var result: std.ArrayList([]const u8) = .{};
        var seen = hashmap_helper.StringHashMap(void).init(self.allocator);
        defer seen.deinit();

        for (self.headers.items) |h| {
            const lower = try std.ascii.allocLowerString(self.allocator, h.name);
            defer self.allocator.free(lower);
            if (!seen.contains(lower)) {
                try seen.put(try self.allocator.dupe(u8, lower), {});
                try result.append(self.allocator, h.name);
            }
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Get all header values
    pub fn values(self: *Self) ![][]const u8 {
        var result: std.ArrayList([]const u8) = .{};
        for (self.headers.items) |h| {
            try result.append(self.allocator, h.value);
        }
        return result.toOwnedSlice(self.allocator);
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
                var mut_parts = parts;
                mut_parts.deinit(self.allocator);
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
                try parts.append(self.allocator, part);
            },
            .text => |t| {
                if (t.len > 0) self.allocator.free(t);
                var parts: std.ArrayList(*Message) = .{};
                try parts.append(self.allocator, part);
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
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        // Write headers
        for (self.headers.items) |h| {
            try result.appendSlice(self.allocator, h.name);
            try result.appendSlice(self.allocator, ": ");
            try result.appendSlice(self.allocator, h.value);
            try result.appendSlice(self.allocator, "\r\n");
        }

        // Blank line before body
        try result.appendSlice(self.allocator, "\r\n");

        // Write payload
        switch (self.payload) {
            .text => |t| {
                try result.appendSlice(self.allocator, t);
            },
            .parts => |parts| {
                const boundary = self.getBoundary() orelse "boundary";
                if (self.preamble) |p| {
                    try result.appendSlice(self.allocator, p);
                    try result.appendSlice(self.allocator, "\r\n");
                }
                for (parts.items) |part| {
                    try result.appendSlice(self.allocator, "--");
                    try result.appendSlice(self.allocator, boundary);
                    try result.appendSlice(self.allocator, "\r\n");
                    const part_str = try part.asString();
                    defer self.allocator.free(part_str);
                    try result.appendSlice(self.allocator, part_str);
                    try result.appendSlice(self.allocator, "\r\n");
                }
                try result.appendSlice(self.allocator, "--");
                try result.appendSlice(self.allocator, boundary);
                try result.appendSlice(self.allocator, "--\r\n");
                if (self.epilogue) |e| {
                    try result.appendSlice(self.allocator, e);
                }
            },
        }

        return result.toOwnedSlice(self.allocator);
    }
};

/// Message iterator for walk()
pub const MessageIterator = struct {
    stack: std.ArrayList(*Message),
    allocator: std.mem.Allocator,

    pub fn init(root: *Message) MessageIterator {
        var stack: std.ArrayList(*Message) = .{};
        stack.append(root.allocator, root) catch {};
        return .{
            .stack = stack,
            .allocator = root.allocator,
        };
    }

    pub fn deinit(self: *MessageIterator) void {
        self.stack.deinit(self.allocator);
    }

    pub fn next(self: *MessageIterator) ?*Message {
        if (self.stack.items.len == 0) return null;

        const msg = self.stack.pop();

        // Add children to stack in reverse order
        if (msg.getParts()) |parts| {
            var i = parts.len;
            while (i > 0) {
                i -= 1;
                self.stack.append(self.allocator, parts[i]) catch {};
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
