//! CPython source: Lib/encodings/mac_turkish.py
//!
//! Macintosh Turkish encoding
//!
//! Mirrors: CPython Lib/encodings/mac_turkish.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "mac-turkish";
pub const aliases = [_][]const u8{ "mac_turkish", "macturkish" };

const UNDEF = charmap.UNDEFINED;

/// Mac Turkish decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F
    table[0x80] = 0x00C4; // LATIN CAPITAL LETTER A WITH DIAERESIS
    table[0x81] = 0x00C5; // LATIN CAPITAL LETTER A WITH RING ABOVE
    table[0x82] = 0x00C7; // LATIN CAPITAL LETTER C WITH CEDILLA
    table[0x83] = 0x00C9; // LATIN CAPITAL LETTER E WITH ACUTE
    table[0x84] = 0x00D1; // LATIN CAPITAL LETTER N WITH TILDE
    table[0x85] = 0x00D6; // LATIN CAPITAL LETTER O WITH DIAERESIS
    table[0x86] = 0x00DC; // LATIN CAPITAL LETTER U WITH DIAERESIS
    table[0x87] = 0x00E1; // LATIN SMALL LETTER A WITH ACUTE
    table[0x88] = 0x00E0; // LATIN SMALL LETTER A WITH GRAVE
    table[0x89] = 0x00E2; // LATIN SMALL LETTER A WITH CIRCUMFLEX
    table[0x8A] = 0x00E4; // LATIN SMALL LETTER A WITH DIAERESIS
    table[0x8B] = 0x00E3; // LATIN SMALL LETTER A WITH TILDE
    table[0x8C] = 0x00E5; // LATIN SMALL LETTER A WITH RING ABOVE
    table[0x8D] = 0x00E7; // LATIN SMALL LETTER C WITH CEDILLA
    table[0x8E] = 0x00E9; // LATIN SMALL LETTER E WITH ACUTE
    table[0x8F] = 0x00E8; // LATIN SMALL LETTER E WITH GRAVE
    table[0x90] = 0x00EA; // LATIN SMALL LETTER E WITH CIRCUMFLEX
    table[0x91] = 0x00EB; // LATIN SMALL LETTER E WITH DIAERESIS
    table[0x92] = 0x00ED; // LATIN SMALL LETTER I WITH ACUTE
    table[0x93] = 0x00EC; // LATIN SMALL LETTER I WITH GRAVE
    table[0x94] = 0x00EE; // LATIN SMALL LETTER I WITH CIRCUMFLEX
    table[0x95] = 0x00EF; // LATIN SMALL LETTER I WITH DIAERESIS
    table[0x96] = 0x00F1; // LATIN SMALL LETTER N WITH TILDE
    table[0x97] = 0x00F3; // LATIN SMALL LETTER O WITH ACUTE
    table[0x98] = 0x00F2; // LATIN SMALL LETTER O WITH GRAVE
    table[0x99] = 0x00F4; // LATIN SMALL LETTER O WITH CIRCUMFLEX
    table[0x9A] = 0x00F6; // LATIN SMALL LETTER O WITH DIAERESIS
    table[0x9B] = 0x00F5; // LATIN SMALL LETTER O WITH TILDE
    table[0x9C] = 0x00FA; // LATIN SMALL LETTER U WITH ACUTE
    table[0x9D] = 0x00F9; // LATIN SMALL LETTER U WITH GRAVE
    table[0x9E] = 0x00FB; // LATIN SMALL LETTER U WITH CIRCUMFLEX
    table[0x9F] = 0x00FC; // LATIN SMALL LETTER U WITH DIAERESIS
    // 0xA0-0xAF
    table[0xA0] = 0x2020; // DAGGER
    table[0xA1] = 0x00B0; // DEGREE SIGN
    table[0xA2] = 0x00A2; // CENT SIGN
    table[0xA3] = 0x00A3; // POUND SIGN
    table[0xA4] = 0x00A7; // SECTION SIGN
    table[0xA5] = 0x2022; // BULLET
    table[0xA6] = 0x00B6; // PILCROW SIGN
    table[0xA7] = 0x00DF; // LATIN SMALL LETTER SHARP S
    table[0xA8] = 0x00AE; // REGISTERED SIGN
    table[0xA9] = 0x00A9; // COPYRIGHT SIGN
    table[0xAA] = 0x2122; // TRADE MARK SIGN
    table[0xAB] = 0x00B4; // ACUTE ACCENT
    table[0xAC] = 0x00A8; // DIAERESIS
    table[0xAD] = 0x2260; // NOT EQUAL TO
    table[0xAE] = 0x00C6; // LATIN CAPITAL LETTER AE
    table[0xAF] = 0x00D8; // LATIN CAPITAL LETTER O WITH STROKE
    // 0xB0-0xBF
    table[0xB0] = 0x221E; // INFINITY
    table[0xB1] = 0x00B1; // PLUS-MINUS SIGN
    table[0xB2] = 0x2264; // LESS-THAN OR EQUAL TO
    table[0xB3] = 0x2265; // GREATER-THAN OR EQUAL TO
    table[0xB4] = 0x00A5; // YEN SIGN
    table[0xB5] = 0x00B5; // MICRO SIGN
    table[0xB6] = 0x2202; // PARTIAL DIFFERENTIAL
    table[0xB7] = 0x2211; // N-ARY SUMMATION
    table[0xB8] = 0x220F; // N-ARY PRODUCT
    table[0xB9] = 0x03C0; // GREEK SMALL LETTER PI
    table[0xBA] = 0x222B; // INTEGRAL
    table[0xBB] = 0x00AA; // FEMININE ORDINAL INDICATOR
    table[0xBC] = 0x00BA; // MASCULINE ORDINAL INDICATOR
    table[0xBD] = 0x03A9; // GREEK CAPITAL LETTER OMEGA
    table[0xBE] = 0x00E6; // LATIN SMALL LETTER AE
    table[0xBF] = 0x00F8; // LATIN SMALL LETTER O WITH STROKE
    // 0xC0-0xCF
    table[0xC0] = 0x00BF; // INVERTED QUESTION MARK
    table[0xC1] = 0x00A1; // INVERTED EXCLAMATION MARK
    table[0xC2] = 0x00AC; // NOT SIGN
    table[0xC3] = 0x221A; // SQUARE ROOT
    table[0xC4] = 0x0192; // LATIN SMALL LETTER F WITH HOOK
    table[0xC5] = 0x2248; // ALMOST EQUAL TO
    table[0xC6] = 0x2206; // INCREMENT
    table[0xC7] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xC8] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xC9] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0xCA] = 0x00A0; // NO-BREAK SPACE
    table[0xCB] = 0x00C0; // LATIN CAPITAL LETTER A WITH GRAVE
    table[0xCC] = 0x00C3; // LATIN CAPITAL LETTER A WITH TILDE
    table[0xCD] = 0x00D5; // LATIN CAPITAL LETTER O WITH TILDE
    table[0xCE] = 0x0152; // LATIN CAPITAL LIGATURE OE
    table[0xCF] = 0x0153; // LATIN SMALL LIGATURE OE
    // 0xD0-0xDF
    table[0xD0] = 0x2013; // EN DASH
    table[0xD1] = 0x2014; // EM DASH
    table[0xD2] = 0x201C; // LEFT DOUBLE QUOTATION MARK
    table[0xD3] = 0x201D; // RIGHT DOUBLE QUOTATION MARK
    table[0xD4] = 0x2018; // LEFT SINGLE QUOTATION MARK
    table[0xD5] = 0x2019; // RIGHT SINGLE QUOTATION MARK
    table[0xD6] = 0x00F7; // DIVISION SIGN
    table[0xD7] = 0x25CA; // LOZENGE
    table[0xD8] = 0x00FF; // LATIN SMALL LETTER Y WITH DIAERESIS
    table[0xD9] = 0x0178; // LATIN CAPITAL LETTER Y WITH DIAERESIS
    table[0xDA] = 0x011E; // LATIN CAPITAL LETTER G WITH BREVE
    table[0xDB] = 0x011F; // LATIN SMALL LETTER G WITH BREVE
    table[0xDC] = 0x0130; // LATIN CAPITAL LETTER I WITH DOT ABOVE
    table[0xDD] = 0x0131; // LATIN SMALL LETTER DOTLESS I
    table[0xDE] = 0x015E; // LATIN CAPITAL LETTER S WITH CEDILLA
    table[0xDF] = 0x015F; // LATIN SMALL LETTER S WITH CEDILLA
    // 0xE0-0xFF
    table[0xE0] = 0x2021; // DOUBLE DAGGER
    table[0xE1] = 0x00B7; // MIDDLE DOT
    table[0xE2] = 0x201A; // SINGLE LOW-9 QUOTATION MARK
    table[0xE3] = 0x201E; // DOUBLE LOW-9 QUOTATION MARK
    table[0xE4] = 0x2030; // PER MILLE SIGN
    table[0xE5] = 0x00C2; // LATIN CAPITAL LETTER A WITH CIRCUMFLEX
    table[0xE6] = 0x00CA; // LATIN CAPITAL LETTER E WITH CIRCUMFLEX
    table[0xE7] = 0x00C1; // LATIN CAPITAL LETTER A WITH ACUTE
    table[0xE8] = 0x00CB; // LATIN CAPITAL LETTER E WITH DIAERESIS
    table[0xE9] = 0x00C8; // LATIN CAPITAL LETTER E WITH GRAVE
    table[0xEA] = 0x00CD; // LATIN CAPITAL LETTER I WITH ACUTE
    table[0xEB] = 0x00CE; // LATIN CAPITAL LETTER I WITH CIRCUMFLEX
    table[0xEC] = 0x00CF; // LATIN CAPITAL LETTER I WITH DIAERESIS
    table[0xED] = 0x00CC; // LATIN CAPITAL LETTER I WITH GRAVE
    table[0xEE] = 0x00D3; // LATIN CAPITAL LETTER O WITH ACUTE
    table[0xEF] = 0x00D4; // LATIN CAPITAL LETTER O WITH CIRCUMFLEX
    table[0xF0] = UNDEF;
    table[0xF1] = 0x00D2; // LATIN CAPITAL LETTER O WITH GRAVE
    table[0xF2] = 0x00DA; // LATIN CAPITAL LETTER U WITH ACUTE
    table[0xF3] = 0x00DB; // LATIN CAPITAL LETTER U WITH CIRCUMFLEX
    table[0xF4] = 0x00D9; // LATIN CAPITAL LETTER U WITH GRAVE
    table[0xF5] = UNDEF;
    table[0xF6] = 0x02C6; // MODIFIER LETTER CIRCUMFLEX ACCENT
    table[0xF7] = 0x02DC; // SMALL TILDE
    table[0xF8] = 0x00AF; // MACRON
    table[0xF9] = 0x02D8; // BREVE
    table[0xFA] = 0x02D9; // DOT ABOVE
    table[0xFB] = 0x02DA; // RING ABOVE
    table[0xFC] = 0x00B8; // CEDILLA
    table[0xFD] = 0x02DD; // DOUBLE ACUTE ACCENT
    table[0xFE] = 0x02DB; // OGONEK
    table[0xFF] = 0x02C7; // CARON
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "mac_turkish decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
