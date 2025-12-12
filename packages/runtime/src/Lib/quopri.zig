//! CPython source: Lib/quopri.py
//!
//! Provides functions for encoding and decoding the quoted-printable
//! transfer encoding as defined in RFC 1521.
//!
//! Mirrors: CPython Lib/quopri.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

const MAXLINESIZE: usize = 76;
const HEX_DIGITS = "0123456789ABCDEF";

/// Characters that don't need encoding (printable ASCII minus '=')
fn needsQuoting(c: u8, quotetabs: bool, header: bool) bool {
    if (c == '=') return true;
    if (header and c == '_') return false;
    if (header and c == ' ') return true;
    if (quotetabs and (c == '\t' or c == ' ')) return true;
    // Printable ASCII (space to tilde, excluding =)
    return c < 32 or c > 126;
}

// ============================================================================
// encode - Encode a file
// ============================================================================

/// Encode a file's contents to quoted-printable format
pub fn encode(allocator: std.mem.Allocator, input: []const u8, quotetabs: bool, header: bool) ![]u8 {
    var result: std.ArrayList(u8) = .{};

    var line_len: usize = 0;

    for (input, 0..) |c, i| {
        const is_last = i + 1 >= input.len;
        const next_is_newline = !is_last and input[i + 1] == '\n';

        if (c == '\n') {
            try result.append(allocator, '\n');
            line_len = 0;
            continue;
        }

        if (c == '\r' and !is_last and input[i + 1] == '\n') {
            // CR-LF - skip CR
            continue;
        }

        // Check if we need to encode this character
        var encoded: [3]u8 = undefined;
        var encoded_len: usize = 0;

        if (needsQuoting(c, quotetabs, header)) {
            encoded[0] = '=';
            encoded[1] = HEX_DIGITS[c >> 4];
            encoded[2] = HEX_DIGITS[c & 0x0F];
            encoded_len = 3;
        } else if (header and c == ' ') {
            encoded[0] = '_';
            encoded_len = 1;
        } else {
            encoded[0] = c;
            encoded_len = 1;
        }

        // Check if we need a soft line break
        // Account for trailing space/tab that might need =\n
        const extra = if ((c == ' ' or c == '\t') and (is_last or next_is_newline)) @as(usize, 1) else @as(usize, 0);

        if (line_len + encoded_len + extra >= MAXLINESIZE) {
            try result.append(allocator, '=');
            try result.append(allocator, '\n');
            line_len = 0;
        }

        try result.appendSlice(allocator, encoded[0..encoded_len]);
        line_len += encoded_len;

        // Trailing space/tab before newline needs soft break
        if ((c == ' ' or c == '\t') and (is_last or next_is_newline)) {
            if (line_len + 1 >= MAXLINESIZE) {
                try result.append(allocator, '=');
                try result.append(allocator, '\n');
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// decode - Decode a file
// ============================================================================

/// Decode quoted-printable data
pub fn decode(allocator: std.mem.Allocator, input: []const u8, header: bool) ![]u8 {
    var result: std.ArrayList(u8) = .{};

    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];

        if (header and c == '_') {
            // In headers, _ represents space
            try result.append(allocator, ' ');
            i += 1;
        } else if (c == '=') {
            if (i + 2 < input.len) {
                const h1 = input[i + 1];
                const h2 = input[i + 2];

                if (h1 == '\n' or (h1 == '\r' and h2 == '\n')) {
                    // Soft line break
                    i += if (h1 == '\r') @as(usize, 3) else @as(usize, 2);
                } else if (hexValue(h1)) |v1| {
                    if (hexValue(h2)) |v2| {
                        try result.append(allocator, (v1 << 4) | v2);
                        i += 3;
                    } else {
                        try result.append(allocator, c);
                        i += 1;
                    }
                } else {
                    try result.append(allocator, c);
                    i += 1;
                }
            } else if (i + 1 < input.len and input[i + 1] == '\n') {
                // Soft line break at end
                i += 2;
            } else {
                try result.append(allocator, c);
                i += 1;
            }
        } else {
            try result.append(allocator, c);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Get hex value of a character
fn hexValue(c: u8) ?u4 {
    if (c >= '0' and c <= '9') return @intCast(c - '0');
    if (c >= 'A' and c <= 'F') return @intCast(c - 'A' + 10);
    if (c >= 'a' and c <= 'f') return @intCast(c - 'a' + 10);
    return null;
}

// ============================================================================
// encodestring / decodestring - String versions
// ============================================================================

/// Encode a string to quoted-printable
pub fn encodestring(allocator: std.mem.Allocator, s: []const u8, quotetabs: bool, header: bool) ![]u8 {
    return encode(allocator, s, quotetabs, header);
}

/// Decode a quoted-printable string
pub fn decodestring(allocator: std.mem.Allocator, s: []const u8, header: bool) ![]u8 {
    return decode(allocator, s, header);
}

// ============================================================================
// b2a_qp / a2b_qp - Binary <-> ASCII conversions
// ============================================================================

/// Encode binary data to quoted-printable ASCII
pub fn b2a_qp(allocator: std.mem.Allocator, data: []const u8, quotetabs: bool, istext: bool, header: bool) ![]u8 {
    _ = istext; // Currently unused
    return encode(allocator, data, quotetabs, header);
}

/// Decode quoted-printable ASCII to binary
pub fn a2b_qp(allocator: std.mem.Allocator, data: []const u8, header: bool) ![]u8 {
    return decode(allocator, data, header);
}

// ============================================================================
// Tests
// ============================================================================

test "encode simple" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "Hello World", false, false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "encode special chars" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "Hello=World", false, false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello=3DWorld", result);
}

test "encode high bytes" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "Hello\x80World", false, false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello=80World", result);
}

test "decode simple" {
    const allocator = std.testing.allocator;
    const result = try decode(allocator, "Hello World", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "decode encoded" {
    const allocator = std.testing.allocator;
    const result = try decode(allocator, "Hello=3DWorld", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello=World", result);
}

test "decode soft line break" {
    const allocator = std.testing.allocator;
    const result = try decode(allocator, "Hello=\nWorld", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("HelloWorld", result);
}

test "decode header underscore" {
    const allocator = std.testing.allocator;
    const result = try decode(allocator, "Hello_World", true);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "hexValue" {
    try std.testing.expectEqual(@as(?u4, 0), hexValue('0'));
    try std.testing.expectEqual(@as(?u4, 9), hexValue('9'));
    try std.testing.expectEqual(@as(?u4, 10), hexValue('A'));
    try std.testing.expectEqual(@as(?u4, 15), hexValue('F'));
    try std.testing.expectEqual(@as(?u4, 10), hexValue('a'));
    try std.testing.expectEqual(@as(?u4, 15), hexValue('f'));
    try std.testing.expectEqual(@as(?u4, null), hexValue('G'));
}

test "roundtrip" {
    const allocator = std.testing.allocator;
    const original = "Hello\x00\x80\xFF=World\nLine2";
    const encoded = try encode(allocator, original, false, false);
    defer allocator.free(encoded);
    const decoded = try decode(allocator, encoded, false);
    defer allocator.free(decoded);
    try std.testing.expectEqualStrings(original, decoded);
}
