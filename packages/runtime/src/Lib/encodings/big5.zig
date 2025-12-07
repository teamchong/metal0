//! CPython source: Lib/encodings/big5.py
//!
//! Implements Big5 encoding for Traditional Chinese text.
//! Double-byte encoding commonly used in Taiwan and Hong Kong.
//!
//! Note: Full implementation requires ~13000+ mapping entries.
//! This provides the codec framework with common characters.
//!
//! Mirrors: CPython Lib/encodings/big5.py

const std = @import("std");

pub const name = "big5";
pub const aliases = [_][]const u8{ "big5-tw", "csbig5" };

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

// Check if byte is a valid Big5 lead byte
fn isLeadByte(b: u8) bool {
    return (b >= 0x81 and b <= 0xFE);
}

// Check if byte is a valid Big5 trail byte
fn isTrailByte(b: u8) bool {
    return (b >= 0x40 and b <= 0x7E) or (b >= 0xA1 and b <= 0xFE);
}

// Decode Big5 double-byte to Unicode
// Returns null for unmapped characters
fn decodeDoubleByte(b1: u8, b2: u8) ?u21 {
    if (!isLeadByte(b1) or !isTrailByte(b2)) return null;

    // Level 1: Frequently used characters (0xA440-0xC67E)
    // Level 2: Less frequently used characters (0xC940-0xF9D5)

    // Special symbols area (0xA140-0xA3BF)
    if (b1 == 0xA1) {
        return switch (b2) {
            0x40 => 0x3000, // Ideographic space
            0x41 => 0xFF0C, // Fullwidth comma
            0x42 => 0x3001, // Ideographic comma
            0x43 => 0x3002, // Ideographic full stop
            0x44 => 0xFF0E, // Fullwidth full stop
            0x45 => 0x2027, // Hyphenation point
            0x46 => 0xFF1B, // Fullwidth semicolon
            0x47 => 0xFF1A, // Fullwidth colon
            0x48 => 0xFF1F, // Fullwidth question mark
            0x49 => 0xFF01, // Fullwidth exclamation mark
            0x4A => 0xFE30, // Presentation form for vertical two dot leader
            0x4B => 0x2026, // Horizontal ellipsis
            0x4C => 0x2025, // Two dot leader
            0x4D => 0xFE50, // Small comma
            0x4E => 0xFF64, // Halfwidth ideographic comma
            0x4F => 0xFE52, // Small full stop
            0x50 => 0x00B7, // Middle dot
            0x51 => 0xFE54, // Small semicolon
            0x52 => 0xFE55, // Small colon
            0x53 => 0xFE56, // Small question mark
            0x54 => 0xFE57, // Small exclamation mark
            0x55 => 0xFF5E, // Fullwidth tilde
            0x56 => 0x2574, // Box drawings light left
            0x57 => 0x2018, // Left single quotation mark
            0x58 => 0x2019, // Right single quotation mark
            0x59 => 0x201C, // Left double quotation mark
            0x5A => 0x201D, // Right double quotation mark
            0x5B => 0x3014, // Left tortoise shell bracket
            0x5C => 0x3015, // Right tortoise shell bracket
            0x5D => 0xFE59, // Small left parenthesis
            0x5E => 0xFE5A, // Small right parenthesis
            else => null,
        };
    }

    // Numbers row (0xA2AF-0xA2B8 for circled numbers)
    if (b1 == 0xA2) {
        // Fullwidth numbers are at A2AF-A2B8 (0-9)
        if (b2 >= 0xAF and b2 <= 0xB8) {
            return 0xFF10 + (b2 - 0xAF); // Fullwidth 0-9
        }
        // Uppercase letters A2C1-A2DA
        if (b2 >= 0xC1 and b2 <= 0xDA) {
            return 0xFF21 + (b2 - 0xC1); // Fullwidth A-Z
        }
        // Lowercase letters A2E1-A2FA
        if (b2 >= 0xE1 and b2 <= 0xFA) {
            return 0xFF41 + (b2 - 0xE1); // Fullwidth a-z
        }
    }

    // Hiragana (0xC6A1-0xC6F7)
    if (b1 == 0xC6 and b2 >= 0xA1 and b2 <= 0xF7) {
        const offset = b2 - 0xA1;
        if (offset < 83) {
            return 0x3041 + offset;
        }
    }

    // Katakana (0xC740-0xC794)
    if (b1 == 0xC7 and b2 >= 0x40 and b2 <= 0x94) {
        const offset: u21 = if (b2 <= 0x7E)
            b2 - 0x40
        else
            b2 - 0xA1 + 63;
        if (offset < 86) {
            return 0x30A1 + offset;
        }
    }

    // Full CJK character mapping would require ~13000 entries
    return null;
}

/// Decode Big5 to UTF-8
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

/// Encode UTF-8 to Big5
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII
            try result.append(@intCast(cp));
        } else {
            // Check for common mappings
            if (cp >= 0xFF10 and cp <= 0xFF19) {
                // Fullwidth digits
                try result.append(0xA2);
                try result.append(@as(u8, @intCast(0xAF + (cp - 0xFF10))));
            } else if (cp >= 0xFF21 and cp <= 0xFF3A) {
                // Fullwidth uppercase
                try result.append(0xA2);
                try result.append(@as(u8, @intCast(0xC1 + (cp - 0xFF21))));
            } else if (cp >= 0xFF41 and cp <= 0xFF5A) {
                // Fullwidth lowercase
                try result.append(0xA2);
                try result.append(@as(u8, @intCast(0xE1 + (cp - 0xFF41))));
            } else if (cp == 0x3000) {
                // Ideographic space
                try result.append(0xA1);
                try result.append(0x40);
            } else {
                // Would need reverse mapping for full support
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

test "big5 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "big5 decode ideographic space" {
    // 0xA140 = ideographic space (U+3000)
    const result = try decode(std.testing.allocator, &[_]u8{ 0xA1, 0x40 }, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xE3\x80\x80", result.output); // U+3000
}

test "big5 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
