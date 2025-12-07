//! CPython source: Lib/encodings/euc_kr.py
//!
//! Implements EUC-KR encoding for Korean text.
//! Extended Unix Code for Korean - also known as KS X 1001.
//!
//! Note: Full implementation requires ~8000+ mapping entries.
//! This provides the codec framework with common characters.
//!
//! Mirrors: CPython Lib/encodings/euc_kr.py

const std = @import("std");

pub const name = "euc_kr";
pub const aliases = [_][]const u8{ "euckr", "korean", "ksc5601", "ks_c_5601", "ks_c_5601-1987", "ksx1001", "ks_x_1001" };

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

// Check if byte is a valid lead byte (0xA1-0xFE)
fn isLeadByte(b: u8) bool {
    return b >= 0xA1 and b <= 0xFE;
}

// Check if byte is a valid trail byte (0xA1-0xFE)
fn isTrailByte(b: u8) bool {
    return b >= 0xA1 and b <= 0xFE;
}

// Decode KS X 1001 double-byte to Unicode
fn decodeKSX1001(b1: u8, b2: u8) ?u21 {
    if (!isLeadByte(b1) or !isTrailByte(b2)) return null;

    const row = b1 - 0xA1; // 0-93
    const col = b2 - 0xA1; // 0-93

    // Row 1: Special characters
    if (row == 0) {
        return switch (col) {
            0 => 0x3000, // Ideographic space
            1 => 0x3001, // Ideographic comma
            2 => 0x3002, // Ideographic full stop
            3 => 0x00B7, // Middle dot
            4 => 0x2025, // Two dot leader
            5 => 0x2026, // Horizontal ellipsis
            6 => 0x00A8, // Diaeresis
            7 => 0x3003, // Ditto mark
            else => null,
        };
    }

    // Row 4: Hangul Jamo (consonants, U+3131-U+314E)
    if (row == 3) {
        if (col < 30) {
            return 0x3131 + col;
        }
    }

    // Row 5: Hangul Jamo (vowels, U+314F-U+3163)
    if (row == 4) {
        if (col < 21) {
            return 0x314F + col;
        }
    }

    // Rows 16-40: Hangul syllables (U+AC00-U+D7A3)
    // This is a simplified mapping - full mapping is complex
    if (row >= 15 and row <= 40) {
        // Hangul syllables start at row 16 (index 15)
        const syllable_row = row - 15;
        const syllable_index = syllable_row * 94 + col;

        // There are 2350 syllables in KS X 1001
        if (syllable_index < 2350) {
            // This is a simplified linear mapping
            // Real mapping is more complex with gaps
            return 0xAC00 + syllable_index;
        }
    }

    // Full mapping would require ~8000 entries
    return null;
}

/// Decode EUC-KR to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        const b1 = input[i];

        if (b1 < 0x80) {
            // ASCII
            try result.append(b1);
            i += 1;
        } else if (isLeadByte(b1)) {
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice("\xEF\xBF\xBD");
                i += 1;
                continue;
            }

            const b2 = input[i + 1];
            if (decodeKSX1001(b1, b2)) |cp| {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cp, &buf) catch {
                    try result.appendSlice("\xEF\xBF\xBD");
                    i += 2;
                    continue;
                };
                try result.appendSlice(buf[0..len]);
            } else {
                if (mode == .strict) return error.InvalidSequence;
                try result.appendSlice("\xEF\xBF\xBD");
            }
            i += 2;
        } else {
            if (mode == .strict) return error.InvalidByte;
            try result.appendSlice("\xEF\xBF\xBD");
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to EUC-KR
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII
            try result.append(@intCast(cp));
        } else if (cp >= 0x3131 and cp <= 0x314E) {
            // Hangul Jamo consonants
            const col: u8 = @intCast(cp - 0x3131);
            try result.append(0xA4);
            try result.append(0xA1 + col);
        } else if (cp >= 0x314F and cp <= 0x3163) {
            // Hangul Jamo vowels
            const col: u8 = @intCast(cp - 0x314F);
            try result.append(0xA5);
            try result.append(0xA1 + col);
        } else {
            // Would need reverse mapping for full support
            if (mode == .strict) return error.UnencodableCharacter;
            try result.append('?');
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(),
        .chars_consumed = input.len,
    };
}

test "euc_kr decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "euc_kr decode ideographic space" {
    // 0xA1A1 = ideographic space (U+3000)
    const result = try decode(std.testing.allocator, &[_]u8{ 0xA1, 0xA1 }, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xE3\x80\x80", result.output);
}

test "euc_kr encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
