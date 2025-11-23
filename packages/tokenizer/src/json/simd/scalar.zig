/// Scalar fallback implementations for SIMD operations
/// Used when SIMD is not available or data is too small
const std = @import("std");

/// Find next special JSON character: { } [ ] : , " \
pub fn findSpecialChar(data: []const u8, offset: usize) ?usize {
    var i = offset;
    while (i < data.len) : (i += 1) {
        const c = data[i];
        switch (c) {
            '{', '}', '[', ']', ':', ',', '"', '\\' => return i,
            else => {},
        }
    }
    return null;
}

/// Find closing quote, tracking escapes
pub fn findClosingQuote(data: []const u8, offset: usize) ?usize {
    var i = offset;
    while (i < data.len) : (i += 1) {
        const c = data[i];
        if (c == '"') {
            return i;
        } else if (c == '\\') {
            i += 1; // Skip escaped character
            if (i >= data.len) return null;
        } else if (c < 0x20) {
            // Control characters must be escaped
            return null;
        }
    }
    return null;
}

/// Validate UTF-8 encoding
pub fn validateUtf8(data: []const u8) bool {
    var i: usize = 0;
    while (i < data.len) {
        const c = data[i];

        if (c < 0x80) {
            // ASCII
            i += 1;
        } else if (c < 0xC0) {
            // Invalid - continuation byte without leader
            return false;
        } else if (c < 0xE0) {
            // 2-byte sequence
            if (i + 1 >= data.len) return false;
            if (!isContinuation(data[i + 1])) return false;
            i += 2;
        } else if (c < 0xF0) {
            // 3-byte sequence
            if (i + 2 >= data.len) return false;
            if (!isContinuation(data[i + 1])) return false;
            if (!isContinuation(data[i + 2])) return false;
            i += 3;
        } else if (c < 0xF8) {
            // 4-byte sequence
            if (i + 3 >= data.len) return false;
            if (!isContinuation(data[i + 1])) return false;
            if (!isContinuation(data[i + 2])) return false;
            if (!isContinuation(data[i + 3])) return false;
            i += 4;
        } else {
            // Invalid UTF-8
            return false;
        }
    }
    return true;
}

/// Check if byte is UTF-8 continuation byte (0b10xxxxxx)
inline fn isContinuation(byte: u8) bool {
    return (byte & 0xC0) == 0x80;
}

/// Count characters matching target
pub fn countMatching(data: []const u8, target: u8) usize {
    var count: usize = 0;
    for (data) |c| {
        if (c == target) count += 1;
    }
    return count;
}

/// Check if string has any escape sequences
pub fn hasEscapes(data: []const u8) bool {
    for (data) |c| {
        if (c == '\\') return true;
    }
    return false;
}

test "findSpecialChar" {
    const data = "hello{world}";
    try std.testing.expectEqual(@as(?usize, 5), findSpecialChar(data, 0));
    try std.testing.expectEqual(@as(?usize, 11), findSpecialChar(data, 6));
    try std.testing.expectEqual(@as(?usize, null), findSpecialChar(data, 12));
}

test "findClosingQuote" {
    const data = "hello\"world";
    try std.testing.expectEqual(@as(?usize, 5), findClosingQuote(data, 0));

    // Escaped quote: hello\"world"end -> quote at position 12
    const escaped = "hello\\\"world\"end";
    try std.testing.expectEqual(@as(?usize, 12), findClosingQuote(escaped, 0));
}

test "validateUtf8" {
    try std.testing.expect(validateUtf8("hello"));
    try std.testing.expect(validateUtf8("hello 世界"));
    try std.testing.expect(!validateUtf8(&[_]u8{0xFF, 0xFE})); // Invalid
}
