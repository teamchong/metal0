//! email._encoded_words - RFC 2047 encoded word handling
//! Reference: cpython/Lib/email/_encoded_words.py
//!
//! This is an internal module for handling RFC 2047 encoded words in headers.
//! Format: =?charset?encoding?encoded_text?=

const std = @import("std");
const base64mime = @import("base64mime.zig");
const quoprimime = @import("quoprimime.zig");

// ============================================================================
// Constants
// ============================================================================

/// Special characters that need encoding
pub const _ESPECIALS = "()<>@,;:\\\"/[]?.=";

/// Pattern for encoded words
/// CPython: _cte_encoders and _cte_decoders
pub const Encoding = enum {
    q, // Quoted-Printable
    b, // Base64

    pub fn fromChar(c: u8) ?Encoding {
        return switch (c) {
            'q', 'Q' => .q,
            'b', 'B' => .b,
            else => null,
        };
    }

    pub fn toChar(self: Encoding) u8 {
        return switch (self) {
            .q => 'q',
            .b => 'b',
        };
    }
};

// ============================================================================
// Decoding
// ============================================================================

/// Decode an RFC 2047 encoded word
/// CPython: def decode(ew)
/// Returns: (decoded_bytes, charset, lang, defects)
pub fn decode(allocator: std.mem.Allocator, ew: []const u8) !DecodeResult {
    var result = DecodeResult{
        .decoded = &[_]u8{},
        .charset = "us-ascii",
        .lang = null,
        .defects = .{},
    };

    // Check format: =?charset?encoding?text?=
    if (ew.len < 8 or !std.mem.startsWith(u8, ew, "=?") or !std.mem.endsWith(u8, ew, "?=")) {
        try result.defects.append(allocator, "Invalid encoded word format");
        result.decoded = try allocator.dupe(u8, ew);
        return result;
    }

    // Parse components
    const inner = ew[2 .. ew.len - 2];
    var parts = std.mem.splitScalar(u8, inner, '?');

    const charset = parts.next() orelse {
        try result.defects.append(allocator, "Missing charset");
        result.decoded = try allocator.dupe(u8, ew);
        return result;
    };
    result.charset = charset;

    // Check for language tag in charset (charset*lang)
    if (std.mem.indexOf(u8, charset, "*")) |star| {
        result.charset = charset[0..star];
        result.lang = charset[star + 1 ..];
    }

    const encoding_str = parts.next() orelse {
        try result.defects.append(allocator, "Missing encoding");
        result.decoded = try allocator.dupe(u8, ew);
        return result;
    };

    if (encoding_str.len != 1) {
        try result.defects.append(allocator, "Invalid encoding");
        result.decoded = try allocator.dupe(u8, ew);
        return result;
    }

    const encoding = Encoding.fromChar(encoding_str[0]) orelse {
        try result.defects.append(allocator, "Unknown encoding");
        result.decoded = try allocator.dupe(u8, ew);
        return result;
    };

    const encoded_text = parts.next() orelse {
        try result.defects.append(allocator, "Missing encoded text");
        result.decoded = try allocator.dupe(u8, ew);
        return result;
    };

    // Decode based on encoding type
    result.decoded = switch (encoding) {
        .q => quoprimime.decode(allocator, encoded_text) catch blk: {
            try result.defects.append(allocator, "QP decode error");
            break :blk try allocator.dupe(u8, encoded_text);
        },
        .b => base64mime.decode(allocator, encoded_text) catch blk: {
            try result.defects.append(allocator, "Base64 decode error");
            break :blk try allocator.dupe(u8, encoded_text);
        },
    };

    return result;
}

/// Result of decoding an encoded word
pub const DecodeResult = struct {
    decoded: []u8,
    charset: []const u8,
    lang: ?[]const u8,
    defects: std.ArrayList([]const u8),

    pub fn deinit(self: *DecodeResult, allocator: std.mem.Allocator) void {
        allocator.free(self.decoded);
        self.defects.deinit(allocator);
    }
};

// ============================================================================
// Encoding
// ============================================================================

/// Encode a string as an RFC 2047 encoded word
/// CPython: def encode(string, charset='utf-8', encoding=None)
pub fn encode(allocator: std.mem.Allocator, text: []const u8, charset: []const u8, encoding: ?Encoding) ![]u8 {
    // Choose encoding if not specified
    const enc = encoding orelse chooseEncoding(text);

    // Encode the text
    const encoded_text = switch (enc) {
        .q => try encodeQ(allocator, text),
        .b => try base64mime.encodeBase64(allocator, text),
    };
    defer allocator.free(encoded_text);

    // Format: =?charset?enc?text?=
    return std.fmt.allocPrint(allocator, "=?{s}?{c}?{s}?=", .{
        charset, enc.toChar(), encoded_text,
    });
}

/// Encode text using Q encoding (RFC 2047 style)
fn encodeQ(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (text) |c| {
        if (c == ' ') {
            try result.append(allocator, '_');
        } else if (needsQEncoding(c)) {
            try result.append(allocator, '=');
            try result.append(allocator, "0123456789ABCDEF"[c >> 4]);
            try result.append(allocator, "0123456789ABCDEF"[c & 0x0F]);
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Check if character needs Q encoding
fn needsQEncoding(c: u8) bool {
    // Printable ASCII except space and especials
    if (c == ' ' or c == '_' or c == '?' or c == '=') return true;
    if (c < 33 or c > 126) return true;
    for (_ESPECIALS) |s| {
        if (c == s) return true;
    }
    return false;
}

/// Choose best encoding for text
/// CPython: def _choose_encoding(string)
fn chooseEncoding(text: []const u8) Encoding {
    // Count characters that need encoding
    var q_len: usize = 0;
    for (text) |c| {
        if (needsQEncoding(c)) {
            q_len += 3;
        } else {
            q_len += 1;
        }
    }

    // Base64 encoding length
    const b_len = (text.len + 2) / 3 * 4;

    // Use Q if it's shorter
    return if (q_len <= b_len) .q else .b;
}

// ============================================================================
// Header Line Folding
// ============================================================================

/// Split encoded words at maximum line length
/// CPython: def _ew_split_decode(header, maxlen)
pub fn ewSplitDecode(allocator: std.mem.Allocator, header: []const u8, maxlen: usize) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    if (header.len <= maxlen) {
        try result.append(allocator, try allocator.dupe(u8, header));
        return result.toOwnedSlice(allocator);
    }

    // Simple split at maxlen boundaries
    var pos: usize = 0;
    while (pos < header.len) {
        const end = @min(pos + maxlen, header.len);
        try result.append(allocator, try allocator.dupe(u8, header[pos..end]));
        pos = end;
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "decode base64" {
    const allocator = std.testing.allocator;
    var result = try decode(allocator, "=?utf-8?b?SGVsbG8=?=");
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("Hello", result.decoded);
    try std.testing.expectEqualStrings("utf-8", result.charset);
}

test "decode qp" {
    const allocator = std.testing.allocator;
    var result = try decode(allocator, "=?utf-8?q?Hello_World?=");
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("Hello World", result.decoded);
}

test "encode" {
    const allocator = std.testing.allocator;
    const encoded = try encode(allocator, "Hello World", "utf-8", .q);
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("=?utf-8?q?Hello_World?=", encoded);
}

test "chooseEncoding" {
    // Short ASCII text - Q is better
    try std.testing.expect(chooseEncoding("Hello") == .q);

    // Binary data - B is better
    const binary = &[_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07 };
    try std.testing.expect(chooseEncoding(binary) == .b);
}
