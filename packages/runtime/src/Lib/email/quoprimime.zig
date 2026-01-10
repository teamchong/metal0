//! email.quoprimime - Quoted-Printable encoding for MIME
//! Reference: cpython/Lib/email/quoprimime.py
//!
//! CPython __all__: ['body_decode', 'body_encode', 'body_length',
//!                   'decode', 'decodestring', 'header_decode',
//!                   'header_encode', 'header_length', 'quote', 'unquote']

const std = @import("std");
const encoders = @import("encoders.zig");

// Re-export from encoders (DRY)
pub const encodeQuopri = encoders.encodeQuopri;
pub const encode_quopri = encoders.encode_quopri;

/// CRLF line ending
pub const CRLF = "\r\n";
pub const NL = "\n";

/// Characters that don't need quoting in body
const BODY_SAFE = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-./ :;<>?@[]^_`{|}~";

/// Characters that don't need quoting in header
const HEADER_SAFE = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!*+-/ ";

/// Hex digits
const HEX = "0123456789ABCDEF";

/// Quote a single character
/// CPython: def quote(c)
pub fn quote(allocator: std.mem.Allocator, c: u8) ![]u8 {
    var result = try allocator.alloc(u8, 3);
    result[0] = '=';
    result[1] = HEX[c >> 4];
    result[2] = HEX[c & 0x0F];
    return result;
}

/// Unquote a quoted string (=XX)
/// CPython: def unquote(s)
pub fn unquote(s: []const u8) ?u8 {
    if (s.len < 3 or s[0] != '=') return null;
    const hi = std.fmt.charToDigit(s[1], 16) catch return null;
    const lo = std.fmt.charToDigit(s[2], 16) catch return null;
    return (hi << 4) | lo;
}

/// Encode a string for use in a MIME header using QP
/// CPython: def header_encode(header_bytes, charset='iso-8859-1')
pub fn header_encode(allocator: std.mem.Allocator, header_bytes: []const u8, charset: []const u8) ![]u8 {
    if (header_bytes.len == 0) {
        return allocator.dupe(u8, "");
    }

    var encoded = std.ArrayList(u8){};
    defer encoded.deinit(allocator);

    for (header_bytes) |c| {
        if (c == ' ') {
            try encoded.append(allocator, '_');
        } else if (std.mem.indexOfScalar(u8, HEADER_SAFE, c) != null) {
            try encoded.append(allocator, c);
        } else {
            try encoded.append(allocator, '=');
            try encoded.append(allocator, HEX[c >> 4]);
            try encoded.append(allocator, HEX[c & 0x0F]);
        }
    }

    // Format: =?charset?q?encoded_text?=
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, "=?");
    try result.appendSlice(allocator, charset);
    try result.appendSlice(allocator, "?q?");
    try result.appendSlice(allocator, encoded.items);
    try result.appendSlice(allocator, "?=");

    return result.toOwnedSlice(allocator);
}

/// Calculate the length of a header-encoded string
/// CPython: def header_length(bytearray)
pub fn header_length(header_bytes: []const u8) usize {
    var length: usize = 0;
    for (header_bytes) |c| {
        if (c == ' ' or std.mem.indexOfScalar(u8, HEADER_SAFE, c) != null) {
            length += 1;
        } else {
            length += 3;
        }
    }
    return length + 7; // =?charset?q?...?= overhead
}

/// Encode the body using QP
/// CPython: def body_encode(body, maxlinelen=76, eol=NL)
pub fn body_encode(allocator: std.mem.Allocator, body: []const u8, maxlinelen: usize, eol: []const u8) ![]u8 {
    _ = maxlinelen;
    _ = eol;
    return encodeQuopri(allocator, body);
}

/// Calculate length of body-encoded string
/// CPython: def body_length(bytearray)
pub fn body_length(body: []const u8) usize {
    var length: usize = 0;
    for (body) |c| {
        if (c == '\r' or c == '\n') {
            length += 1;
        } else if (c >= 33 and c <= 126 and c != '=') {
            length += 1;
        } else {
            length += 3;
        }
    }
    return length;
}

/// Decode a QP string
/// CPython: def decode(encoded, eol=NL)
pub fn decode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '=') {
            if (i + 2 < encoded.len) {
                // Check for soft line break
                if (encoded[i + 1] == '\r' and i + 2 < encoded.len and encoded[i + 2] == '\n') {
                    i += 3;
                    continue;
                }
                if (encoded[i + 1] == '\n') {
                    i += 2;
                    continue;
                }
                // Try to decode hex
                if (unquote(encoded[i .. i + 3])) |c| {
                    try result.append(allocator, c);
                    i += 3;
                    continue;
                }
            }
            try result.append(allocator, encoded[i]);
            i += 1;
        } else if (encoded[i] == '_') {
            try result.append(allocator, ' ');
            i += 1;
        } else {
            try result.append(allocator, encoded[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Alias for decode
/// CPython: decodestring = decode
pub const decodestring = decode;

/// Alias for decode (for body)
/// CPython: body_decode = decode
pub const body_decode = decode;

/// Alias for decode (for header)
/// CPython: header_decode = decode
pub const header_decode = decode;

// ============================================================================
// Tests
// ============================================================================

test "quote" {
    const allocator = std.testing.allocator;
    const result = try quote(allocator, 0xAB);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("=AB", result);
}

test "unquote" {
    try std.testing.expectEqual(@as(u8, 0xAB), unquote("=AB").?);
    try std.testing.expect(unquote("abc") == null);
}

test "header_encode" {
    const allocator = std.testing.allocator;
    const result = try header_encode(allocator, "Hello World", "utf-8");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("=?utf-8?q?Hello_World?=", result);
}

test "decode" {
    const allocator = std.testing.allocator;
    const result = try decode(allocator, "Hello_World");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}
