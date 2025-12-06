//! Python 'johab' Codec (Johab)
//!
//! Implements Johab encoding for Korean text.
//! Combines initial/medial/final (Choseong/Jungseong/Jongseong) in one unit.
//!
//! Note: Full implementation requires complex Hangul composition logic.
//! This provides the codec framework.
//!
//! Mirrors: CPython Lib/encodings/johab.py

const std = @import("std");

pub const name = "johab";
pub const aliases = [_][]const u8{ "cp1361", "ms1361" };

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

// Johab lead byte ranges
fn isLeadByte(b: u8) bool {
    return (b >= 0x84 and b <= 0xD3) or (b >= 0xD8 and b <= 0xDE) or (b >= 0xE0 and b <= 0xF9);
}

fn isTrailByte(b: u8) bool {
    return (b >= 0x31 and b <= 0x7E) or (b >= 0x91 and b <= 0xFE);
}

// Choseong (initial consonant) lookup - 19 Jamo
const choseong_base: u21 = 0x1100;
const jungseong_base: u21 = 0x1161;
const jongseong_base: u21 = 0x11A7;

// Decompose Johab syllable to Hangul components
fn decodeJohabSyllable(b1: u8, b2: u8) ?u21 {
    if (!isLeadByte(b1) or !isTrailByte(b2)) return null;

    // Johab encoding structure:
    // Bit 15: always 1
    // Bits 14-10: Choseong (initial)
    // Bits 9-5: Jungseong (medial)
    // Bits 4-0: Jongseong (final)

    const word: u16 = (@as(u16, b1) << 8) | b2;

    // Check high bit
    if ((word & 0x8000) == 0) return null;

    const cho_idx = (word >> 10) & 0x1F;
    const jung_idx = (word >> 5) & 0x1F;
    const jong_idx = word & 0x1F;

    // Validate indices (simplified)
    if (cho_idx < 2 or cho_idx > 20) return null;
    if (jung_idx < 3 or jung_idx > 23) return null;

    // Map to Hangul syllable block (U+AC00-U+D7A3)
    // Each syllable = (cho-2)*588 + (jung-3)*28 + jong
    const cho: u21 = cho_idx - 2;
    const jung: u21 = jung_idx - 3;
    const jong: u21 = if (jong_idx > 0) jong_idx else 0;

    if (cho >= 19 or jung >= 21 or jong >= 28) return null;

    return 0xAC00 + cho * 588 + jung * 28 + jong;
}

/// Decode Johab to UTF-8
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
            if (decodeJohabSyllable(b1, b2)) |cp| {
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

/// Encode UTF-8 to Johab
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII
            try result.append(@intCast(cp));
        } else if (cp >= 0xAC00 and cp <= 0xD7A3) {
            // Hangul syllable - decompose to Johab
            const syl = cp - 0xAC00;
            const cho: u16 = @intCast(syl / 588 + 2);
            const jung: u16 = @intCast((syl % 588) / 28 + 3);
            const jong: u16 = @intCast(syl % 28);

            // Compose Johab word
            const word: u16 = 0x8000 | (cho << 10) | (jung << 5) | jong;
            try result.append(@intCast(word >> 8));
            try result.append(@intCast(word & 0xFF));
        } else {
            if (mode == .strict) return error.UnencodableCharacter;
            try result.append('?');
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(),
        .chars_consumed = input.len,
    };
}

test "johab decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "johab encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
