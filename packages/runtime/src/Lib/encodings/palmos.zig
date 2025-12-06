//! Python 'palmos' Codec (PalmOS 3.5)
//!
//! Character Mapping Codec for PalmOS 3.5
//! Based on iso8859_15 with card suit symbols and Windows-1252 extensions
//!
//! Mirrors: CPython Lib/encodings/palmos.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "palmos";
pub const aliases = [_][]const u8{};

/// PalmOS decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F: Same as ASCII
    for (0..0x80) |i| {
        table[i] = @intCast(i);
    }
    // 0x80-0x9F: Windows-1252-like with card suits
    table[0x80] = 0x20AC; // EURO SIGN
    table[0x81] = 0x0081; // <control>
    table[0x82] = 0x201A; // SINGLE LOW-9 QUOTATION MARK
    table[0x83] = 0x0192; // LATIN SMALL LETTER F WITH HOOK
    table[0x84] = 0x201E; // DOUBLE LOW-9 QUOTATION MARK
    table[0x85] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0x86] = 0x2020; // DAGGER
    table[0x87] = 0x2021; // DOUBLE DAGGER
    table[0x88] = 0x02C6; // MODIFIER LETTER CIRCUMFLEX ACCENT
    table[0x89] = 0x2030; // PER MILLE SIGN
    table[0x8A] = 0x0160; // LATIN CAPITAL LETTER S WITH CARON
    table[0x8B] = 0x2039; // SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    table[0x8C] = 0x0152; // LATIN CAPITAL LIGATURE OE
    table[0x8D] = 0x2666; // BLACK DIAMOND SUIT
    table[0x8E] = 0x2663; // BLACK CLUB SUIT
    table[0x8F] = 0x2665; // BLACK HEART SUIT
    table[0x90] = 0x2660; // BLACK SPADE SUIT
    table[0x91] = 0x2018; // LEFT SINGLE QUOTATION MARK
    table[0x92] = 0x2019; // RIGHT SINGLE QUOTATION MARK
    table[0x93] = 0x201C; // LEFT DOUBLE QUOTATION MARK
    table[0x94] = 0x201D; // RIGHT DOUBLE QUOTATION MARK
    table[0x95] = 0x2022; // BULLET
    table[0x96] = 0x2013; // EN DASH
    table[0x97] = 0x2014; // EM DASH
    table[0x98] = 0x02DC; // SMALL TILDE
    table[0x99] = 0x2122; // TRADE MARK SIGN
    table[0x9A] = 0x0161; // LATIN SMALL LETTER S WITH CARON
    table[0x9B] = 0x203A; // SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    table[0x9C] = 0x0153; // LATIN SMALL LIGATURE OE
    table[0x9D] = 0x009D; // <control>
    table[0x9E] = 0x009E; // <control>
    table[0x9F] = 0x0178; // LATIN CAPITAL LETTER Y WITH DIAERESIS
    // 0xA0-0xFF: Same as Latin-1 (ISO-8859-1)
    for (0xA0..0x100) |i| {
        table[i] = @intCast(i);
    }
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "palmos decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "palmos decode euro sign" {
    // 0x80 decodes to Euro sign (U+20AC)
    const result = try decode(std.testing.allocator, &[_]u8{0x80}, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xE2\x82\xAC", result.output); // UTF-8 for U+20AC
}

test "palmos decode card suits" {
    // 0x8D = diamond, 0x8E = club, 0x8F = heart, 0x90 = spade
    const result = try decode(std.testing.allocator, &[_]u8{ 0x8D, 0x8E, 0x8F, 0x90 }, .strict);
    defer std.testing.allocator.free(result.output);
    // U+2666, U+2663, U+2665, U+2660
    try std.testing.expectEqualStrings("\xE2\x99\xA6\xE2\x99\xA3\xE2\x99\xA5\xE2\x99\xA0", result.output);
}
