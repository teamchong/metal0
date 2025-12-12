//! CPython source: Lib/encodings/euc_jp.py
//!
//! Implements EUC-JP encoding for Japanese text.
//! Extended Unix Code for Japanese - commonly used in Unix systems.
//!
//! Note: Full implementation requires ~7000+ mapping entries.
//! This provides the codec framework with common characters.
//!
//! Mirrors: CPython Lib/encodings/euc_jp.py

const std = @import("std");

pub const name = "euc_jp";
pub const aliases = [_][]const u8{ "eucjp", "ujis", "u-jis" };

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

// EUC-JP byte classification
fn isG1LeadByte(b: u8) bool {
    // JIS X 0208 (2-byte): 0xA1-0xFE
    return b >= 0xA1 and b <= 0xFE;
}

fn isG2LeadByte(b: u8) bool {
    // JIS X 0201 half-width katakana (SS2 + byte)
    return b == 0x8E;
}

fn isG3LeadByte(b: u8) bool {
    // JIS X 0212 (SS3 + 2 bytes)
    return b == 0x8F;
}

// Decode JIS X 0208 double-byte to Unicode
fn decodeJISX0208(b1: u8, b2: u8) ?u21 {
    if (b1 < 0xA1 or b1 > 0xFE or b2 < 0xA1 or b2 > 0xFE) return null;

    const row = b1 - 0xA1; // 0-93
    const col = b2 - 0xA1; // 0-93

    // Row 1: Symbols
    if (row == 0) {
        return switch (col) {
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

    // Row 4: Hiragana (U+3041-U+3093)
    if (row == 3) {
        if (col < 83) {
            return 0x3041 + col;
        }
    }

    // Row 5: Katakana (U+30A1-U+30F6)
    if (row == 4) {
        if (col < 86) {
            return 0x30A1 + col;
        }
    }

    // Full mapping would require ~7000 entries
    return null;
}

/// Decode EUC-JP to UTF-8
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
        } else if (isG2LeadByte(b1)) {
            // SS2 + half-width katakana
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
                i += 1;
                continue;
            }
            const b2 = input[i + 1];
            if (b2 >= 0xA1 and b2 <= 0xDF) {
                // Half-width katakana U+FF61-U+FF9F
                const cp: u21 = 0xFF61 + (b2 - 0xA1);
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cp, &buf) catch unreachable;
                try result.appendSlice(allocator, buf[0..len]);
            } else {
                if (mode == .strict) return error.InvalidSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
            }
            i += 2;
        } else if (isG3LeadByte(b1)) {
            // SS3 + JIS X 0212
            if (i + 2 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
                i += 1;
                continue;
            }
            // JIS X 0212 mapping not implemented
            if (mode == .strict) return error.InvalidSequence;
            try result.appendSlice(allocator, "\xEF\xBF\xBD");
            i += 3;
        } else if (isG1LeadByte(b1)) {
            // JIS X 0208 double-byte
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
                i += 1;
                continue;
            }

            const b2 = input[i + 1];
            if (decodeJISX0208(b1, b2)) |cp| {
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

/// Encode UTF-8 to EUC-JP
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII
            try result.append(allocator, @intCast(cp));
        } else if (cp >= 0xFF61 and cp <= 0xFF9F) {
            // Half-width katakana
            try result.append(allocator, 0x8E);
            try result.append(allocator, @intCast(0xA1 + (cp - 0xFF61)));
        } else {
            // Use CJK mapping tables for full support
            const cjk = @import("cjk_mappings.zig");
            if (cjk.encodeJisx0208(cp)) |jis_code| {
                // JIS X 0208 -> EUC-JP: add 0x80 to each byte
                try result.append(allocator, @as(u8, @intCast(jis_code >> 8)) | 0x80);
                try result.append(allocator, @as(u8, @intCast(jis_code & 0xFF)) | 0x80);
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

test "euc_jp decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "euc_jp decode ideographic space" {
    // 0xA1A1 = ideographic space (U+3000)
    const result = try decode(std.testing.allocator, &[_]u8{ 0xA1, 0xA1 }, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xE3\x80\x80", result.output);
}

test "euc_jp encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
