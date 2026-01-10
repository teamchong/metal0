//! email.base64mime - Base64 encoding for MIME
//! Reference: cpython/Lib/email/base64mime.py
//!
//! CPython __all__: ['body_decode', 'body_encode', 'decode', 'decodestring',
//!                   'header_encode', 'header_length']

const std = @import("std");
const encoders = @import("encoders.zig");

// Re-export base64 encoding from encoders (DRY)
pub const encodeBase64 = encoders.encodeBase64;
pub const encode_base64 = encoders.encode_base64;

/// CRLF line ending
pub const CRLF = "\r\n";
pub const NL = "\n";
pub const EMPTYSTRING = "";
pub const MISC_LEN: usize = 7; // =?charset?b?...?= overhead

/// Maximum line length for base64 encoded headers
pub const MAX_LINE_LEN: usize = 76;

/// Encode a string for use in a MIME header
/// CPython: def header_encode(header_bytes, charset='iso-8859-1')
pub fn header_encode(allocator: std.mem.Allocator, header_bytes: []const u8, charset: []const u8) ![]u8 {
    if (header_bytes.len == 0) {
        return allocator.dupe(u8, "");
    }

    const encoded = try encodeBase64(allocator, header_bytes);
    defer allocator.free(encoded);

    // Format: =?charset?b?encoded_text?=
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, "=?");
    try result.appendSlice(allocator, charset);
    try result.appendSlice(allocator, "?b?");
    try result.appendSlice(allocator, encoded);
    try result.appendSlice(allocator, "?=");

    return result.toOwnedSlice(allocator);
}

/// Return the length of the header encoded string
/// CPython: def header_length(bytearray)
pub fn header_length(header_bytes: []const u8) usize {
    const encoded_len = std.base64.standard.Encoder.calcSize(header_bytes.len);
    return encoded_len + MISC_LEN;
}

/// Encode the body of an email message using base64
/// CPython: def body_encode(s, maxlinelen=76, eol=NL)
pub fn body_encode(allocator: std.mem.Allocator, s: []const u8, maxlinelen: usize, eol: []const u8) ![]u8 {
    if (s.len == 0) {
        return allocator.dupe(u8, "");
    }

    const encoded = try encodeBase64(allocator, s);
    defer allocator.free(encoded);

    // Split into lines of maxlinelen
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var pos: usize = 0;
    while (pos < encoded.len) {
        const end = @min(pos + maxlinelen, encoded.len);
        try result.appendSlice(allocator, encoded[pos..end]);
        if (end < encoded.len) {
            try result.appendSlice(allocator, eol);
        }
        pos = end;
    }

    return result.toOwnedSlice(allocator);
}

/// Decode a base64 encoded string
/// CPython: def decode(string)
pub fn decode(allocator: std.mem.Allocator, string: []const u8) ![]u8 {
    // Remove whitespace
    var clean = std.ArrayList(u8){};
    defer clean.deinit(allocator);

    for (string) |c| {
        if (c != ' ' and c != '\t' and c != '\r' and c != '\n') {
            try clean.append(allocator, c);
        }
    }

    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(clean.items);
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);

    try std.base64.standard.Decoder.decode(decoded, clean.items);
    return decoded;
}

/// Alias for decode
/// CPython: decodestring = decode
pub const decodestring = decode;

/// Alias for decode
/// CPython: body_decode = decode
pub const body_decode = decode;

// ============================================================================
// Tests
// ============================================================================

test "header_encode" {
    const allocator = std.testing.allocator;
    const result = try header_encode(allocator, "Hello", "utf-8");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("=?utf-8?b?SGVsbG8=?=", result);
}

test "header_length" {
    try std.testing.expectEqual(@as(usize, 15), header_length("Hello")); // 8 + 7
}

test "body_encode" {
    const allocator = std.testing.allocator;
    const result = try body_encode(allocator, "Hello", 76, "\n");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("SGVsbG8=", result);
}

test "decode" {
    const allocator = std.testing.allocator;
    const result = try decode(allocator, "SGVsbG8=");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello", result);
}
