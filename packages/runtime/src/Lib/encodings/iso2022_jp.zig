//! CPython source: Lib/encodings/iso2022_jp.py
//!
//! Implements ISO-2022-JP encoding for Japanese text.
//! 7-bit encoding using escape sequences to switch character sets.
//!
//! Escape sequences:
//!   ESC ( B  - ASCII
//!   ESC ( J  - JIS X 0201 Roman
//!   ESC $ @  - JIS X 0208-1978
//!   ESC $ B  - JIS X 0208-1983
//!
//! Mirrors: CPython Lib/encodings/iso2022_jp.py

const std = @import("std");

pub const name = "iso2022_jp";
pub const aliases = [_][]const u8{ "csiso2022jp", "iso2022jp", "iso-2022-jp" };

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

const CharSet = enum {
    ascii,
    jis_x_0201_roman,
    jis_x_0208_1978,
    jis_x_0208_1983,
};

const ESC = 0x1B;

// Parse escape sequence starting at position i
// Returns new character set and bytes consumed (including ESC)
fn parseEscapeSequence(input: []const u8, i: usize) ?struct { charset: CharSet, len: usize } {
    if (i + 2 >= input.len) return null;
    if (input[i] != ESC) return null;

    const b1 = input[i + 1];
    const b2 = input[i + 2];

    if (b1 == '(' and b2 == 'B') return .{ .charset = .ascii, .len = 3 };
    if (b1 == '(' and b2 == 'J') return .{ .charset = .jis_x_0201_roman, .len = 3 };

    if (i + 3 < input.len) {
        if (b1 == '$' and b2 == '@') return .{ .charset = .jis_x_0208_1978, .len = 3 };
        if (b1 == '$' and b2 == 'B') return .{ .charset = .jis_x_0208_1983, .len = 3 };
    }

    return null;
}

// Decode JIS X 0208 double-byte to Unicode
fn decodeJISX0208(b1: u8, b2: u8) ?u21 {
    if (b1 < 0x21 or b1 > 0x7E or b2 < 0x21 or b2 > 0x7E) return null;

    const row = b1 - 0x21;
    const col = b2 - 0x21;

    // Row 1: Symbols
    if (row == 0) {
        return switch (col) {
            0 => 0x3000, // Ideographic space
            1 => 0x3001, // Ideographic comma
            2 => 0x3002, // Ideographic full stop
            3 => 0xFF0C, // Fullwidth comma
            4 => 0xFF0E, // Fullwidth full stop
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

/// Decode ISO-2022-JP to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var charset: CharSet = .ascii;
    var i: usize = 0;

    while (i < input.len) {
        // Check for escape sequence
        if (input[i] == ESC) {
            if (parseEscapeSequence(input, i)) |esc| {
                charset = esc.charset;
                i += esc.len;
                continue;
            }
            // Invalid escape sequence
            if (mode == .strict) return error.InvalidSequence;
            try result.appendSlice(allocator, "\xEF\xBF\xBD");
            i += 1;
            continue;
        }

        switch (charset) {
            .ascii, .jis_x_0201_roman => {
                if (input[i] < 0x80) {
                    try result.append(allocator, input[i]);
                } else {
                    if (mode == .strict) return error.InvalidByte;
                    try result.appendSlice(allocator, "\xEF\xBF\xBD");
                }
                i += 1;
            },
            .jis_x_0208_1978, .jis_x_0208_1983 => {
                if (i + 1 >= input.len) {
                    if (mode == .strict) return error.IncompleteSequence;
                    try result.appendSlice(allocator, "\xEF\xBF\xBD");
                    i += 1;
                    continue;
                }

                const b1 = input[i];
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
            },
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to ISO-2022-JP
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var in_ascii = true;

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // Switch to ASCII if not already
            if (!in_ascii) {
                try result.appendSlice(allocator, &[_]u8{ ESC, '(', 'B' });
                in_ascii = true;
            }
            try result.append(allocator, @intCast(cp));
        } else {
            // Use CJK mapping tables for JIS X 0208 encoding
            const cjk = @import("cjk_mappings.zig");
            if (cjk.encodeJisx0208(cp)) |jis_code| {
                // Switch to JIS X 0208 if not already
                if (in_ascii) {
                    try result.appendSlice(allocator, &[_]u8{ ESC, '$', 'B' }); // JIS X 0208
                    in_ascii = false;
                }
                try result.append(allocator, @intCast(jis_code >> 8));
                try result.append(allocator, @intCast(jis_code & 0xFF));
            } else {
                // No mapping available
                if (mode == .strict) return error.UnencodableCharacter;
                if (!in_ascii) {
                    try result.appendSlice(allocator, &[_]u8{ ESC, '(', 'B' });
                    in_ascii = true;
                }
                try result.append(allocator, '?');
            }
        }
    }

    // End in ASCII mode
    if (!in_ascii) {
        try result.appendSlice(allocator, &[_]u8{ ESC, '(', 'B' });
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(allocator),
        .chars_consumed = input.len,
    };
}

test "iso2022_jp decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "iso2022_jp encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
