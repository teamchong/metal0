//! CPython source: Lib/encodings/shift_jis.py
//!
//! Implements Shift JIS encoding for Japanese text.
//! Single-byte ASCII + half-width katakana, double-byte for kanji.
//!
//! Note: Full implementation requires ~7000+ mapping entries.
//! This provides the codec framework with common characters.
//!
//! Mirrors: CPython Lib/encodings/shift_jis.py

const std = @import("std");

pub const name = "shift_jis";
pub const aliases = [_][]const u8{ "csshiftjis", "shiftjis", "sjis", "s_jis" };

pub const DecodeResult = struct {
    output: []u8,
    bytes_consumed: usize,
};

pub const EncodeResult = struct {
    output: []u8,
    chars_consumed: usize,
};

pub const ErrorMode = enum {
    strict,
    replace,
    ignore,
    xmlcharrefreplace,
    backslashreplace,
};

// Half-width katakana (0xA1-0xDF) maps to U+FF61-U+FF9F
fn decodeHalfWidthKatakana(byte: u8) ?u21 {
    if (byte >= 0xA1 and byte <= 0xDF) {
        return 0xFF61 + (byte - 0xA1);
    }
    return null;
}

fn encodeHalfWidthKatakana(cp: u21) ?u8 {
    if (cp >= 0xFF61 and cp <= 0xFF9F) {
        return @intCast(0xA1 + (cp - 0xFF61));
    }
    return null;
}

// Check if first byte indicates double-byte character
fn isLeadByte(b: u8) bool {
    return (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC);
}

// Decode a double-byte Shift_JIS sequence to Unicode
// This is a simplified mapping for common characters
fn decodeDoubleByte(b1: u8, b2: u8) ?u21 {
    // Validate trail byte range
    if (!((b2 >= 0x40 and b2 <= 0x7E) or (b2 >= 0x80 and b2 <= 0xFC))) {
        return null;
    }

    // Convert to JIS row/cell
    var row: u16 = undefined;
    var cell: u16 = undefined;

    if (b1 >= 0x81 and b1 <= 0x9F) {
        row = (b1 - 0x81) * 2;
    } else if (b1 >= 0xE0 and b1 <= 0xFC) {
        row = (b1 - 0xE0 + 31) * 2;
    } else {
        return null;
    }

    if (b2 >= 0x40 and b2 <= 0x7E) {
        cell = b2 - 0x40;
    } else if (b2 >= 0x80 and b2 <= 0x9E) {
        cell = b2 - 0x80 + 63;
    } else if (b2 >= 0x9F and b2 <= 0xFC) {
        row += 1;
        cell = b2 - 0x9F;
    } else {
        return null;
    }

    // JIS X 0208 to Unicode mapping for common characters
    // Row 1-2: Symbols and punctuation
    if (row == 0) {
        // First row - common symbols
        return switch (cell) {
            0 => 0x3000, // Ideographic space
            1 => 0x3001, // Ideographic comma
            2 => 0x3002, // Ideographic full stop
            3 => 0xFF0C, // Fullwidth comma
            4 => 0xFF0E, // Fullwidth full stop
            5 => 0x30FB, // Katakana middle dot
            6 => 0xFF1A, // Fullwidth colon
            7 => 0xFF1B, // Fullwidth semicolon
            else => null,
        };
    }

    // Hiragana (rows 4-5, starting at U+3041)
    if (row >= 3 and row <= 4) {
        const hiragana_offset = (row - 3) * 94 + cell;
        if (hiragana_offset < 83) {
            return 0x3041 + hiragana_offset;
        }
    }

    // Katakana (rows 5-6, starting at U+30A1)
    if (row >= 5 and row <= 6) {
        const katakana_offset = (row - 5) * 94 + cell;
        if (katakana_offset < 86) {
            return 0x30A1 + katakana_offset;
        }
    }

    // Full mapping would require ~7000 entries
    // Return null for unmapped characters
    return null;
}

/// Decode Shift_JIS to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        const b1 = input[i];

        if (b1 < 0x80) {
            // ASCII
            try result.append(allocator, b1);
            i += 1;
        } else if (decodeHalfWidthKatakana(b1)) |cp| {
            // Half-width katakana
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, &buf) catch unreachable;
            try result.appendSlice(allocator, buf[0..len]);
            i += 1;
        } else if (isLeadByte(b1)) {
            // Double-byte character
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD"); // U+FFFD
                i += 1;
                continue;
            }

            const b2 = input[i + 1];
            if (decodeDoubleByte(b1, b2)) |cp| {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cp, &buf) catch {
                    try result.appendSlice(allocator, "\xEF\xBF\xBD");
                    i += 2;
                    continue;
                };
                try result.appendSlice(allocator, buf[0..len]);
            } else {
                if (mode == .strict) return error.InvalidSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
            }
            i += 2;
        } else {
            // Invalid byte
            if (mode == .strict) return error.InvalidByte;
            try result.appendSlice(allocator, "\xEF\xBF\xBD");
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to Shift_JIS
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII
            try result.append(allocator, @intCast(cp));
        } else if (encodeHalfWidthKatakana(cp)) |byte| {
            // Half-width katakana
            try result.append(allocator, byte);
        } else {
            // Use CJK mapping tables for full support
            const cjk = @import("cjk_mappings.zig");
            if (cjk.encodeJisx0208(cp)) |jis_code| {
                // Transform JIS X 0208 to Shift-JIS
                const sjis = cjk.jisToShiftJis(jis_code);
                try result.append(allocator, sjis.c1);
                try result.append(allocator, sjis.c2);
            } else if (cjk.encodeCp932Ext(cp)) |code| {
                // CP932 extension characters
                try result.append(allocator, @intCast(code >> 8));
                try result.append(allocator, @intCast(code & 0xFF));
            } else {
                // No mapping available
                if (mode == .strict) return error.UnencodableCharacter;
                try result.append(allocator, '?');
            }
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(allocator),
        .chars_consumed = input.len,
    };
}

test "shift_jis decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "shift_jis decode half-width katakana" {
    // 0xA1 = half-width ideographic full stop (U+FF61)
    const result = try decode(std.testing.allocator, &[_]u8{0xA1}, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xEF\xBD\xA1", result.output); // U+FF61
}

test "shift_jis encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
