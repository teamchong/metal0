//! CPython source: Lib/encodings/gb2312.py
//!
//! Implements GB2312 encoding for Simplified Chinese text.
//! Double-byte encoding with 94x94 grid structure.
//!
//! Note: Full implementation requires ~7000+ mapping entries.
//! This provides the codec framework with common characters.
//!
//! Mirrors: CPython Lib/encodings/gb2312.py

const std = @import("std");

pub const name = "gb2312";
pub const aliases = [_][]const u8{ "chinese", "csiso58gb231280", "euc-cn", "euccn", "eucgb2312-cn", "gb2312-80", "gb2312-1980", "iso-ir-58" };

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

// Check if byte is a valid GB2312 lead byte (high byte of EUC-CN)
fn isLeadByte(b: u8) bool {
    return b >= 0xA1 and b <= 0xF7;
}

// Check if byte is a valid GB2312 trail byte
fn isTrailByte(b: u8) bool {
    return b >= 0xA1 and b <= 0xFE;
}

// Decode GB2312 double-byte to Unicode
// Returns null for unmapped characters
fn decodeDoubleByte(b1: u8, b2: u8) ?u21 {
    if (!isLeadByte(b1) or !isTrailByte(b2)) return null;

    const row = b1 - 0xA1; // 0-86
    const col = b2 - 0xA1; // 0-93

    // Row 1 (0): Chinese punctuation and symbols
    if (row == 0) {
        return switch (col) {
            0 => 0x3000, // Ideographic space
            1 => 0x3001, // Ideographic comma
            2 => 0x3002, // Ideographic full stop
            3 => 0x00B7, // Middle dot
            4 => 0x02C9, // Modifier letter macron
            5 => 0x02C7, // Caron
            6 => 0x00A8, // Diaeresis
            7 => 0x3003, // Ditto mark
            8 => 0x3005, // Ideographic iteration mark
            9 => 0x2014, // Em dash (mapped from 0x2015)
            10 => 0xFF5E, // Fullwidth tilde
            11 => 0x2016, // Double vertical line
            12 => 0x2026, // Horizontal ellipsis
            13 => 0x2018, // Left single quotation mark
            14 => 0x2019, // Right single quotation mark
            15 => 0x201C, // Left double quotation mark
            16 => 0x201D, // Right double quotation mark
            17 => 0x3014, // Left tortoise shell bracket
            18 => 0x3015, // Right tortoise shell bracket
            else => null,
        };
    }

    // Row 3 (2): Numbers and ASCII punctuation (fullwidth)
    if (row == 2) {
        if (col >= 0 and col < 10) {
            // Fullwidth digits 0-9 (U+FF10-U+FF19)
            return 0xFF10 + col;
        }
    }

    // Row 4 (3): Uppercase Latin (fullwidth)
    if (row == 3) {
        if (col >= 1 and col <= 26) {
            // Fullwidth A-Z (U+FF21-U+FF3A)
            return 0xFF21 + (col - 1);
        }
    }

    // Row 5 (4): Lowercase Latin (fullwidth)
    if (row == 4) {
        if (col >= 1 and col <= 26) {
            // Fullwidth a-z (U+FF41-U+FF5A)
            return 0xFF41 + (col - 1);
        }
    }

    // Row 6 (5): Hiragana
    if (row == 5) {
        if (col < 83) {
            return 0x3041 + col;
        }
    }

    // Row 7 (6): Katakana
    if (row == 6) {
        if (col < 86) {
            return 0x30A1 + col;
        }
    }

    // Rows 16-87 (15-86): Chinese characters (CJK Unified Ideographs)
    // Full mapping would require ~6000+ entries
    // This is a placeholder for the framework

    return null;
}

/// Decode GB2312 (EUC-CN) to UTF-8
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
            // Double-byte character
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice("\xEF\xBF\xBD"); // U+FFFD
                i += 1;
                continue;
            }

            const b2 = input[i + 1];
            if (decodeDoubleByte(b1, b2)) |cp| {
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
            // Invalid byte
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

/// Encode UTF-8 to GB2312
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII
            try result.append(@intCast(cp));
        } else {
            // Would need reverse mapping for full support
            // Check for fullwidth digits/letters
            if (cp >= 0xFF10 and cp <= 0xFF19) {
                // Fullwidth digits
                const col: u8 = @intCast(cp - 0xFF10);
                try result.append(0xA3);
                try result.append(0xB0 + col);
            } else if (cp >= 0xFF21 and cp <= 0xFF3A) {
                // Fullwidth uppercase
                const col: u8 = @intCast(cp - 0xFF21 + 1);
                try result.append(0xA3);
                try result.append(0xC1 + col - 1);
            } else if (cp >= 0xFF41 and cp <= 0xFF5A) {
                // Fullwidth lowercase
                const col: u8 = @intCast(cp - 0xFF41 + 1);
                try result.append(0xA3);
                try result.append(0xE1 + col - 1);
            } else {
                if (mode == .strict) return error.UnencodableCharacter;
                try result.append('?');
            }
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(),
        .chars_consumed = input.len,
    };
}

test "gb2312 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "gb2312 decode ideographic space" {
    // 0xA1A1 = ideographic space (U+3000)
    const result = try decode(std.testing.allocator, &[_]u8{ 0xA1, 0xA1 }, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xE3\x80\x80", result.output); // U+3000
}

test "gb2312 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
