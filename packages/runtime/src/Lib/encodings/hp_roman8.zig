//! Python 'hp_roman8' Codec (HP Roman-8)
//!
//! HP Roman-8 encoding used on HP systems
//!
//! Mirrors: CPython Lib/encodings/hp_roman8.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "hp-roman8";
pub const aliases = [_][]const u8{ "hp_roman8", "roman8", "r8", "csHPRoman8" };

const UNDEF = charmap.UNDEFINED;

/// HP Roman8 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F
    table[0x80] = UNDEF;
    table[0x81] = UNDEF;
    table[0x82] = UNDEF;
    table[0x83] = UNDEF;
    table[0x84] = UNDEF;
    table[0x85] = UNDEF;
    table[0x86] = UNDEF;
    table[0x87] = UNDEF;
    table[0x88] = UNDEF;
    table[0x89] = UNDEF;
    table[0x8A] = UNDEF;
    table[0x8B] = UNDEF;
    table[0x8C] = UNDEF;
    table[0x8D] = UNDEF;
    table[0x8E] = UNDEF;
    table[0x8F] = UNDEF;
    table[0x90] = UNDEF;
    table[0x91] = UNDEF;
    table[0x92] = UNDEF;
    table[0x93] = UNDEF;
    table[0x94] = UNDEF;
    table[0x95] = UNDEF;
    table[0x96] = UNDEF;
    table[0x97] = UNDEF;
    table[0x98] = UNDEF;
    table[0x99] = UNDEF;
    table[0x9A] = UNDEF;
    table[0x9B] = UNDEF;
    table[0x9C] = UNDEF;
    table[0x9D] = UNDEF;
    table[0x9E] = UNDEF;
    table[0x9F] = UNDEF;
    // 0xA0-0xAF
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = 0x00C0; // LATIN CAPITAL LETTER A WITH GRAVE
    table[0xA2] = 0x00C2; // LATIN CAPITAL LETTER A WITH CIRCUMFLEX
    table[0xA3] = 0x00C8; // LATIN CAPITAL LETTER E WITH GRAVE
    table[0xA4] = 0x00CA; // LATIN CAPITAL LETTER E WITH CIRCUMFLEX
    table[0xA5] = 0x00CB; // LATIN CAPITAL LETTER E WITH DIAERESIS
    table[0xA6] = 0x00CE; // LATIN CAPITAL LETTER I WITH CIRCUMFLEX
    table[0xA7] = 0x00CF; // LATIN CAPITAL LETTER I WITH DIAERESIS
    table[0xA8] = 0x00B4; // ACUTE ACCENT
    table[0xA9] = 0x02CB; // MODIFIER LETTER GRAVE ACCENT
    table[0xAA] = 0x02C6; // MODIFIER LETTER CIRCUMFLEX ACCENT
    table[0xAB] = 0x00A8; // DIAERESIS
    table[0xAC] = 0x02DC; // SMALL TILDE
    table[0xAD] = 0x00D9; // LATIN CAPITAL LETTER U WITH GRAVE
    table[0xAE] = 0x00DB; // LATIN CAPITAL LETTER U WITH CIRCUMFLEX
    table[0xAF] = 0x20A4; // LIRA SIGN
    // 0xB0-0xBF
    table[0xB0] = 0x00AF; // MACRON
    table[0xB1] = 0x00DD; // LATIN CAPITAL LETTER Y WITH ACUTE
    table[0xB2] = 0x00FD; // LATIN SMALL LETTER Y WITH ACUTE
    table[0xB3] = 0x00B0; // DEGREE SIGN
    table[0xB4] = 0x00C7; // LATIN CAPITAL LETTER C WITH CEDILLA
    table[0xB5] = 0x00E7; // LATIN SMALL LETTER C WITH CEDILLA
    table[0xB6] = 0x00D1; // LATIN CAPITAL LETTER N WITH TILDE
    table[0xB7] = 0x00F1; // LATIN SMALL LETTER N WITH TILDE
    table[0xB8] = 0x00A1; // INVERTED EXCLAMATION MARK
    table[0xB9] = 0x00BF; // INVERTED QUESTION MARK
    table[0xBA] = 0x00A4; // CURRENCY SIGN
    table[0xBB] = 0x00A3; // POUND SIGN
    table[0xBC] = 0x00A5; // YEN SIGN
    table[0xBD] = 0x00A7; // SECTION SIGN
    table[0xBE] = 0x0192; // LATIN SMALL LETTER F WITH HOOK
    table[0xBF] = 0x00A2; // CENT SIGN
    // 0xC0-0xCF
    table[0xC0] = 0x00E2; // LATIN SMALL LETTER A WITH CIRCUMFLEX
    table[0xC1] = 0x00EA; // LATIN SMALL LETTER E WITH CIRCUMFLEX
    table[0xC2] = 0x00F4; // LATIN SMALL LETTER O WITH CIRCUMFLEX
    table[0xC3] = 0x00FB; // LATIN SMALL LETTER U WITH CIRCUMFLEX
    table[0xC4] = 0x00E1; // LATIN SMALL LETTER A WITH ACUTE
    table[0xC5] = 0x00E9; // LATIN SMALL LETTER E WITH ACUTE
    table[0xC6] = 0x00F3; // LATIN SMALL LETTER O WITH ACUTE
    table[0xC7] = 0x00FA; // LATIN SMALL LETTER U WITH ACUTE
    table[0xC8] = 0x00E0; // LATIN SMALL LETTER A WITH GRAVE
    table[0xC9] = 0x00E8; // LATIN SMALL LETTER E WITH GRAVE
    table[0xCA] = 0x00F2; // LATIN SMALL LETTER O WITH GRAVE
    table[0xCB] = 0x00F9; // LATIN SMALL LETTER U WITH GRAVE
    table[0xCC] = 0x00E4; // LATIN SMALL LETTER A WITH DIAERESIS
    table[0xCD] = 0x00EB; // LATIN SMALL LETTER E WITH DIAERESIS
    table[0xCE] = 0x00F6; // LATIN SMALL LETTER O WITH DIAERESIS
    table[0xCF] = 0x00FC; // LATIN SMALL LETTER U WITH DIAERESIS
    // 0xD0-0xDF
    table[0xD0] = 0x00C5; // LATIN CAPITAL LETTER A WITH RING ABOVE
    table[0xD1] = 0x00EE; // LATIN SMALL LETTER I WITH CIRCUMFLEX
    table[0xD2] = 0x00D8; // LATIN CAPITAL LETTER O WITH STROKE
    table[0xD3] = 0x00C6; // LATIN CAPITAL LETTER AE
    table[0xD4] = 0x00E5; // LATIN SMALL LETTER A WITH RING ABOVE
    table[0xD5] = 0x00ED; // LATIN SMALL LETTER I WITH ACUTE
    table[0xD6] = 0x00F8; // LATIN SMALL LETTER O WITH STROKE
    table[0xD7] = 0x00E6; // LATIN SMALL LETTER AE
    table[0xD8] = 0x00C4; // LATIN CAPITAL LETTER A WITH DIAERESIS
    table[0xD9] = 0x00EC; // LATIN SMALL LETTER I WITH GRAVE
    table[0xDA] = 0x00D6; // LATIN CAPITAL LETTER O WITH DIAERESIS
    table[0xDB] = 0x00DC; // LATIN CAPITAL LETTER U WITH DIAERESIS
    table[0xDC] = 0x00C9; // LATIN CAPITAL LETTER E WITH ACUTE
    table[0xDD] = 0x00EF; // LATIN SMALL LETTER I WITH DIAERESIS
    table[0xDE] = 0x00DF; // LATIN SMALL LETTER SHARP S
    table[0xDF] = 0x00D4; // LATIN CAPITAL LETTER O WITH CIRCUMFLEX
    // 0xE0-0xEF
    table[0xE0] = 0x00C1; // LATIN CAPITAL LETTER A WITH ACUTE
    table[0xE1] = 0x00C3; // LATIN CAPITAL LETTER A WITH TILDE
    table[0xE2] = 0x00E3; // LATIN SMALL LETTER A WITH TILDE
    table[0xE3] = 0x00D0; // LATIN CAPITAL LETTER ETH
    table[0xE4] = 0x00F0; // LATIN SMALL LETTER ETH
    table[0xE5] = 0x00CD; // LATIN CAPITAL LETTER I WITH ACUTE
    table[0xE6] = 0x00CC; // LATIN CAPITAL LETTER I WITH GRAVE
    table[0xE7] = 0x00D3; // LATIN CAPITAL LETTER O WITH ACUTE
    table[0xE8] = 0x00D2; // LATIN CAPITAL LETTER O WITH GRAVE
    table[0xE9] = 0x00D5; // LATIN CAPITAL LETTER O WITH TILDE
    table[0xEA] = 0x00F5; // LATIN SMALL LETTER O WITH TILDE
    table[0xEB] = 0x0160; // LATIN CAPITAL LETTER S WITH CARON
    table[0xEC] = 0x0161; // LATIN SMALL LETTER S WITH CARON
    table[0xED] = 0x00DA; // LATIN CAPITAL LETTER U WITH ACUTE
    table[0xEE] = 0x0178; // LATIN CAPITAL LETTER Y WITH DIAERESIS
    table[0xEF] = 0x00FF; // LATIN SMALL LETTER Y WITH DIAERESIS
    // 0xF0-0xFF
    table[0xF0] = 0x00DE; // LATIN CAPITAL LETTER THORN
    table[0xF1] = 0x00FE; // LATIN SMALL LETTER THORN
    table[0xF2] = 0x00B7; // MIDDLE DOT
    table[0xF3] = 0x00B5; // MICRO SIGN
    table[0xF4] = 0x00B6; // PILCROW SIGN
    table[0xF5] = 0x00BE; // VULGAR FRACTION THREE QUARTERS
    table[0xF6] = 0x2014; // EM DASH
    table[0xF7] = 0x00BC; // VULGAR FRACTION ONE QUARTER
    table[0xF8] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xF9] = 0x00AA; // FEMININE ORDINAL INDICATOR
    table[0xFA] = 0x00BA; // MASCULINE ORDINAL INDICATOR
    table[0xFB] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xFC] = 0x25A0; // BLACK SQUARE
    table[0xFD] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xFE] = 0x00B1; // PLUS-MINUS SIGN
    table[0xFF] = UNDEF;
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "hp_roman8 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
