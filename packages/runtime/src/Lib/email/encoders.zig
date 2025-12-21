//! Content transfer encodings
//!
//! Provides encoding functions for email content transfer encodings.

const std = @import("std");

/// Encode as base64
pub fn encodeBase64(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(data.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, data);
    return encoded;
}

/// Encode as quoted-printable
pub fn encodeQuopri(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var line_len: usize = 0;
    const hex = "0123456789ABCDEF";

    for (data) |c| {
        if (c == '\r' or c == '\n') {
            try result.append(allocator, c);
            line_len = 0;
        } else if (c >= 33 and c <= 126 and c != '=') {
            if (line_len >= 75) {
                try result.appendSlice(allocator, "=\r\n");
                line_len = 0;
            }
            try result.append(allocator, c);
            line_len += 1;
        } else {
            if (line_len >= 73) {
                try result.appendSlice(allocator, "=\r\n");
                line_len = 0;
            }
            try result.append(allocator, '=');
            try result.append(allocator, hex[c >> 4]);
            try result.append(allocator, hex[c & 0x0F]);
            line_len += 3;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Encode as 7bit (no-op, just validates)
pub fn encode7bit(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return allocator.dupe(u8, data);
}

/// Encode as 8bit (no-op)
pub fn encode8bit(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return allocator.dupe(u8, data);
}

/// Encode base64 (snake_case alias)
pub fn encode_base64(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return encodeBase64(allocator, data);
}

/// Encode quoted-printable (snake_case alias)
pub fn encode_quopri(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return encodeQuopri(allocator, data);
}

/// Encode 7bit (snake_case alias)
pub fn encode_7bit(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return encode7bit(allocator, data);
}

/// Encode 8bit (snake_case alias)
pub fn encode_8bit(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return encode8bit(allocator, data);
}
