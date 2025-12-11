//! Header encoding and decoding
//!
//! Provides functions for encoding and decoding email headers.

const std = @import("std");

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
                        var j: usize = 0;
                        while (j < text.?.len) {
                            const c = text.?[j];
                            if (c == '_') {
                                try result.append(' ');
                                j += 1;
                            } else if (c == '=' and j + 2 < text.?.len) {
                                // Decode hex pair
                                const hex_chars = text.?[j + 1 .. j + 3];
                                if (std.fmt.parseInt(u8, hex_chars, 16)) |byte| {
                                    try result.append(byte);
                                    j += 3;
                                } else |_| {
                                    try result.append(c);
                                    j += 1;
                                }
                            } else {
                                try result.append(c);
                                j += 1;
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

/// Decode header (alias for decodeHeader)
pub fn decode_header(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    return decodeHeader(allocator, value);
}

/// Make header (alias for makeHeader)
pub fn make_header(allocator: std.mem.Allocator, decoded_value: []const u8, charset: []const u8) ![]u8 {
    return makeHeader(allocator, decoded_value, charset);
}
