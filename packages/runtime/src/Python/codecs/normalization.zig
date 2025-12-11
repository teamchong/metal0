/// codecs/normalization - Encoding Name Normalization
/// Handles normalization and validation of encoding names

const std = @import("std");

// ============================================================================
// Encoding Name Normalization
// ============================================================================

/// Normalize an encoding name:
/// - Convert to lowercase
/// - Replace spaces and underscores with hyphens
/// Mirrors: normalizestring() in codecs.c
pub fn normalizeEncoding(buf: []u8, encoding: []const u8) []const u8 {
    const len = @min(encoding.len, buf.len - 1);
    for (0..len) |i| {
        var ch = encoding[i];
        if (ch == ' ' or ch == '_') {
            ch = '-';
        } else if (ch >= 'A' and ch <= 'Z') {
            ch = ch - 'A' + 'a';
        }
        buf[i] = ch;
    }
    return buf[0..len];
}

/// Check if encoding name is valid ASCII
pub fn isValidEncodingName(encoding: []const u8) bool {
    for (encoding) |ch| {
        if (ch > 127) return false;
    }
    return encoding.len > 0;
}

// ============================================================================
// Tests
// ============================================================================

test "normalize encoding" {
    var buf: [256]u8 = undefined;

    const n1 = normalizeEncoding(&buf, "UTF-8");
    try std.testing.expectEqualStrings("utf-8", n1);

    const n2 = normalizeEncoding(&buf, "ISO_8859_1");
    try std.testing.expectEqualStrings("iso-8859-1", n2);

    const n3 = normalizeEncoding(&buf, "US ASCII");
    try std.testing.expectEqualStrings("us-ascii", n3);
}
