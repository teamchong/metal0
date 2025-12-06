//! Python 'cp1258' Codec (Windows-1258 / Vietnamese)
//!
//! Windows Vietnamese codepage
//!
//! Mirrors: CPython Lib/encodings/cp1258.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp1258";
pub const aliases = [_][]const u8{ "windows-1258" };

const UNDEF = charmap.UNDEFINED;

/// CP1258 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F
    table[0x80] = 0x20AC; // EURO SIGN
    table[0x81] = UNDEF;
    table[0x82] = 0x201A; // SINGLE LOW-9 QUOTATION MARK
    table[0x83] = 0x0192; // LATIN SMALL LETTER F WITH HOOK
    table[0x84] = 0x201E; // DOUBLE LOW-9 QUOTATION MARK
    table[0x85] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0x86] = 0x2020; // DAGGER
    table[0x87] = 0x2021; // DOUBLE DAGGER
    table[0x88] = 0x02C6; // MODIFIER LETTER CIRCUMFLEX ACCENT
    table[0x89] = 0x2030; // PER MILLE SIGN
    table[0x8A] = UNDEF;
    table[0x8B] = 0x2039; // SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    table[0x8C] = 0x0152; // LATIN CAPITAL LIGATURE OE
    table[0x8D] = UNDEF;
    table[0x8E] = UNDEF;
    table[0x8F] = UNDEF;
    table[0x90] = UNDEF;
    table[0x91] = 0x2018; // LEFT SINGLE QUOTATION MARK
    table[0x92] = 0x2019; // RIGHT SINGLE QUOTATION MARK
    table[0x93] = 0x201C; // LEFT DOUBLE QUOTATION MARK
    table[0x94] = 0x201D; // RIGHT DOUBLE QUOTATION MARK
    table[0x95] = 0x2022; // BULLET
    table[0x96] = 0x2013; // EN DASH
    table[0x97] = 0x2014; // EM DASH
    table[0x98] = 0x02DC; // SMALL TILDE
    table[0x99] = 0x2122; // TRADE MARK SIGN
    table[0x9A] = UNDEF;
    table[0x9B] = 0x203A; // SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    table[0x9C] = 0x0153; // LATIN SMALL LIGATURE OE
    table[0x9D] = UNDEF;
    table[0x9E] = UNDEF;
    table[0x9F] = 0x0178; // LATIN CAPITAL LETTER Y WITH DIAERESIS
    // 0xA0-0xBF: mostly Latin-1 with Vietnamese additions
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = 0x00A1; // INVERTED EXCLAMATION MARK
    table[0xA2] = 0x00A2; // CENT SIGN
    table[0xA3] = 0x00A3; // POUND SIGN
    table[0xA4] = 0x00A4; // CURRENCY SIGN
    table[0xA5] = 0x00A5; // YEN SIGN
    table[0xA6] = 0x00A6; // BROKEN BAR
    table[0xA7] = 0x00A7; // SECTION SIGN
    table[0xA8] = 0x00A8; // DIAERESIS
    table[0xA9] = 0x00A9; // COPYRIGHT SIGN
    table[0xAA] = 0x00AA; // FEMININE ORDINAL INDICATOR
    table[0xAB] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xAC] = 0x00AC; // NOT SIGN
    table[0xAD] = 0x00AD; // SOFT HYPHEN
    table[0xAE] = 0x00AE; // REGISTERED SIGN
    table[0xAF] = 0x00AF; // MACRON
    table[0xB0] = 0x00B0; // DEGREE SIGN
    table[0xB1] = 0x00B1; // PLUS-MINUS SIGN
    table[0xB2] = 0x00B2; // SUPERSCRIPT TWO
    table[0xB3] = 0x00B3; // SUPERSCRIPT THREE
    table[0xB4] = 0x00B4; // ACUTE ACCENT
    table[0xB5] = 0x00B5; // MICRO SIGN
    table[0xB6] = 0x00B6; // PILCROW SIGN
    table[0xB7] = 0x00B7; // MIDDLE DOT
    table[0xB8] = 0x00B8; // CEDILLA
    table[0xB9] = 0x00B9; // SUPERSCRIPT ONE
    table[0xBA] = 0x00BA; // MASCULINE ORDINAL INDICATOR
    table[0xBB] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xBC] = 0x00BC; // VULGAR FRACTION ONE QUARTER
    table[0xBD] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xBE] = 0x00BE; // VULGAR FRACTION THREE QUARTERS
    table[0xBF] = 0x00BF; // INVERTED QUESTION MARK
    // 0xC0-0xFF: Vietnamese letters
    table[0xC0] = 0x00C0; // LATIN CAPITAL LETTER A WITH GRAVE
    table[0xC1] = 0x00C1; // LATIN CAPITAL LETTER A WITH ACUTE
    table[0xC2] = 0x00C2; // LATIN CAPITAL LETTER A WITH CIRCUMFLEX
    table[0xC3] = 0x0102; // LATIN CAPITAL LETTER A WITH BREVE
    table[0xC4] = 0x00C4; // LATIN CAPITAL LETTER A WITH DIAERESIS
    table[0xC5] = 0x00C5; // LATIN CAPITAL LETTER A WITH RING ABOVE
    table[0xC6] = 0x00C6; // LATIN CAPITAL LETTER AE
    table[0xC7] = 0x00C7; // LATIN CAPITAL LETTER C WITH CEDILLA
    table[0xC8] = 0x00C8; // LATIN CAPITAL LETTER E WITH GRAVE
    table[0xC9] = 0x00C9; // LATIN CAPITAL LETTER E WITH ACUTE
    table[0xCA] = 0x00CA; // LATIN CAPITAL LETTER E WITH CIRCUMFLEX
    table[0xCB] = 0x00CB; // LATIN CAPITAL LETTER E WITH DIAERESIS
    table[0xCC] = 0x0300; // COMBINING GRAVE ACCENT
    table[0xCD] = 0x00CD; // LATIN CAPITAL LETTER I WITH ACUTE
    table[0xCE] = 0x00CE; // LATIN CAPITAL LETTER I WITH CIRCUMFLEX
    table[0xCF] = 0x00CF; // LATIN CAPITAL LETTER I WITH DIAERESIS
    table[0xD0] = 0x0110; // LATIN CAPITAL LETTER D WITH STROKE
    table[0xD1] = 0x00D1; // LATIN CAPITAL LETTER N WITH TILDE
    table[0xD2] = 0x0309; // COMBINING HOOK ABOVE
    table[0xD3] = 0x00D3; // LATIN CAPITAL LETTER O WITH ACUTE
    table[0xD4] = 0x00D4; // LATIN CAPITAL LETTER O WITH CIRCUMFLEX
    table[0xD5] = 0x01A0; // LATIN CAPITAL LETTER O WITH HORN
    table[0xD6] = 0x00D6; // LATIN CAPITAL LETTER O WITH DIAERESIS
    table[0xD7] = 0x00D7; // MULTIPLICATION SIGN
    table[0xD8] = 0x00D8; // LATIN CAPITAL LETTER O WITH STROKE
    table[0xD9] = 0x00D9; // LATIN CAPITAL LETTER U WITH GRAVE
    table[0xDA] = 0x00DA; // LATIN CAPITAL LETTER U WITH ACUTE
    table[0xDB] = 0x00DB; // LATIN CAPITAL LETTER U WITH CIRCUMFLEX
    table[0xDC] = 0x00DC; // LATIN CAPITAL LETTER U WITH DIAERESIS
    table[0xDD] = 0x01AF; // LATIN CAPITAL LETTER U WITH HORN
    table[0xDE] = 0x0303; // COMBINING TILDE
    table[0xDF] = 0x00DF; // LATIN SMALL LETTER SHARP S
    table[0xE0] = 0x00E0; // LATIN SMALL LETTER A WITH GRAVE
    table[0xE1] = 0x00E1; // LATIN SMALL LETTER A WITH ACUTE
    table[0xE2] = 0x00E2; // LATIN SMALL LETTER A WITH CIRCUMFLEX
    table[0xE3] = 0x0103; // LATIN SMALL LETTER A WITH BREVE
    table[0xE4] = 0x00E4; // LATIN SMALL LETTER A WITH DIAERESIS
    table[0xE5] = 0x00E5; // LATIN SMALL LETTER A WITH RING ABOVE
    table[0xE6] = 0x00E6; // LATIN SMALL LETTER AE
    table[0xE7] = 0x00E7; // LATIN SMALL LETTER C WITH CEDILLA
    table[0xE8] = 0x00E8; // LATIN SMALL LETTER E WITH GRAVE
    table[0xE9] = 0x00E9; // LATIN SMALL LETTER E WITH ACUTE
    table[0xEA] = 0x00EA; // LATIN SMALL LETTER E WITH CIRCUMFLEX
    table[0xEB] = 0x00EB; // LATIN SMALL LETTER E WITH DIAERESIS
    table[0xEC] = 0x0301; // COMBINING ACUTE ACCENT
    table[0xED] = 0x00ED; // LATIN SMALL LETTER I WITH ACUTE
    table[0xEE] = 0x00EE; // LATIN SMALL LETTER I WITH CIRCUMFLEX
    table[0xEF] = 0x00EF; // LATIN SMALL LETTER I WITH DIAERESIS
    table[0xF0] = 0x0111; // LATIN SMALL LETTER D WITH STROKE
    table[0xF1] = 0x00F1; // LATIN SMALL LETTER N WITH TILDE
    table[0xF2] = 0x0323; // COMBINING DOT BELOW
    table[0xF3] = 0x00F3; // LATIN SMALL LETTER O WITH ACUTE
    table[0xF4] = 0x00F4; // LATIN SMALL LETTER O WITH CIRCUMFLEX
    table[0xF5] = 0x01A1; // LATIN SMALL LETTER O WITH HORN
    table[0xF6] = 0x00F6; // LATIN SMALL LETTER O WITH DIAERESIS
    table[0xF7] = 0x00F7; // DIVISION SIGN
    table[0xF8] = 0x00F8; // LATIN SMALL LETTER O WITH STROKE
    table[0xF9] = 0x00F9; // LATIN SMALL LETTER U WITH GRAVE
    table[0xFA] = 0x00FA; // LATIN SMALL LETTER U WITH ACUTE
    table[0xFB] = 0x00FB; // LATIN SMALL LETTER U WITH CIRCUMFLEX
    table[0xFC] = 0x00FC; // LATIN SMALL LETTER U WITH DIAERESIS
    table[0xFD] = 0x01B0; // LATIN SMALL LETTER U WITH HORN
    table[0xFE] = 0x20AB; // DONG SIGN
    table[0xFF] = 0x00FF; // LATIN SMALL LETTER Y WITH DIAERESIS
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "cp1258 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
