//! CPython source: Lib/encodings/cp862.py
//!
//! DOS Hebrew codepage
//!
//! Mirrors: CPython Lib/encodings/cp862.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp862";
pub const aliases = [_][]const u8{ "ibm862", "862" };

const UNDEF = charmap.UNDEFINED;

/// CP862 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9A: Hebrew letters
    table[0x80] = 0x05D0; // HEBREW LETTER ALEF
    table[0x81] = 0x05D1; // HEBREW LETTER BET
    table[0x82] = 0x05D2; // HEBREW LETTER GIMEL
    table[0x83] = 0x05D3; // HEBREW LETTER DALET
    table[0x84] = 0x05D4; // HEBREW LETTER HE
    table[0x85] = 0x05D5; // HEBREW LETTER VAV
    table[0x86] = 0x05D6; // HEBREW LETTER ZAYIN
    table[0x87] = 0x05D7; // HEBREW LETTER HET
    table[0x88] = 0x05D8; // HEBREW LETTER TET
    table[0x89] = 0x05D9; // HEBREW LETTER YOD
    table[0x8A] = 0x05DA; // HEBREW LETTER FINAL KAF
    table[0x8B] = 0x05DB; // HEBREW LETTER KAF
    table[0x8C] = 0x05DC; // HEBREW LETTER LAMED
    table[0x8D] = 0x05DD; // HEBREW LETTER FINAL MEM
    table[0x8E] = 0x05DE; // HEBREW LETTER MEM
    table[0x8F] = 0x05DF; // HEBREW LETTER FINAL NUN
    table[0x90] = 0x05E0; // HEBREW LETTER NUN
    table[0x91] = 0x05E1; // HEBREW LETTER SAMEKH
    table[0x92] = 0x05E2; // HEBREW LETTER AYIN
    table[0x93] = 0x05E3; // HEBREW LETTER FINAL PE
    table[0x94] = 0x05E4; // HEBREW LETTER PE
    table[0x95] = 0x05E5; // HEBREW LETTER FINAL TSADI
    table[0x96] = 0x05E6; // HEBREW LETTER TSADI
    table[0x97] = 0x05E7; // HEBREW LETTER QOF
    table[0x98] = 0x05E8; // HEBREW LETTER RESH
    table[0x99] = 0x05E9; // HEBREW LETTER SHIN
    table[0x9A] = 0x05EA; // HEBREW LETTER TAV
    table[0x9B] = 0x00A2; // CENT SIGN
    table[0x9C] = 0x00A3; // POUND SIGN
    table[0x9D] = 0x00A5; // YEN SIGN
    table[0x9E] = 0x20A7; // PESETA SIGN
    table[0x9F] = 0x0192; // LATIN SMALL LETTER F WITH HOOK
    // 0xA0-0xAF
    table[0xA0] = 0x00E1; // LATIN SMALL LETTER A WITH ACUTE
    table[0xA1] = 0x00ED; // LATIN SMALL LETTER I WITH ACUTE
    table[0xA2] = 0x00F3; // LATIN SMALL LETTER O WITH ACUTE
    table[0xA3] = 0x00FA; // LATIN SMALL LETTER U WITH ACUTE
    table[0xA4] = 0x00F1; // LATIN SMALL LETTER N WITH TILDE
    table[0xA5] = 0x00D1; // LATIN CAPITAL LETTER N WITH TILDE
    table[0xA6] = 0x00AA; // FEMININE ORDINAL INDICATOR
    table[0xA7] = 0x00BA; // MASCULINE ORDINAL INDICATOR
    table[0xA8] = 0x00BF; // INVERTED QUESTION MARK
    table[0xA9] = 0x2310; // REVERSED NOT SIGN
    table[0xAA] = 0x00AC; // NOT SIGN
    table[0xAB] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xAC] = 0x00BC; // VULGAR FRACTION ONE QUARTER
    table[0xAD] = 0x00A1; // INVERTED EXCLAMATION MARK
    table[0xAE] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xAF] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    // 0xB0-0xDF: Box drawing characters
    table[0xB0] = 0x2591; // LIGHT SHADE
    table[0xB1] = 0x2592; // MEDIUM SHADE
    table[0xB2] = 0x2593; // DARK SHADE
    table[0xB3] = 0x2502; // BOX DRAWINGS LIGHT VERTICAL
    table[0xB4] = 0x2524; // BOX DRAWINGS LIGHT VERTICAL AND LEFT
    table[0xB5] = 0x2561; // BOX DRAWINGS VERTICAL SINGLE AND LEFT DOUBLE
    table[0xB6] = 0x2562; // BOX DRAWINGS VERTICAL DOUBLE AND LEFT SINGLE
    table[0xB7] = 0x2556; // BOX DRAWINGS DOWN DOUBLE AND LEFT SINGLE
    table[0xB8] = 0x2555; // BOX DRAWINGS DOWN SINGLE AND LEFT DOUBLE
    table[0xB9] = 0x2563; // BOX DRAWINGS DOUBLE VERTICAL AND LEFT
    table[0xBA] = 0x2551; // BOX DRAWINGS DOUBLE VERTICAL
    table[0xBB] = 0x2557; // BOX DRAWINGS DOUBLE DOWN AND LEFT
    table[0xBC] = 0x255D; // BOX DRAWINGS DOUBLE UP AND LEFT
    table[0xBD] = 0x255C; // BOX DRAWINGS UP DOUBLE AND LEFT SINGLE
    table[0xBE] = 0x255B; // BOX DRAWINGS UP SINGLE AND LEFT DOUBLE
    table[0xBF] = 0x2510; // BOX DRAWINGS LIGHT DOWN AND LEFT
    table[0xC0] = 0x2514; // BOX DRAWINGS LIGHT UP AND RIGHT
    table[0xC1] = 0x2534; // BOX DRAWINGS LIGHT UP AND HORIZONTAL
    table[0xC2] = 0x252C; // BOX DRAWINGS LIGHT DOWN AND HORIZONTAL
    table[0xC3] = 0x251C; // BOX DRAWINGS LIGHT VERTICAL AND RIGHT
    table[0xC4] = 0x2500; // BOX DRAWINGS LIGHT HORIZONTAL
    table[0xC5] = 0x253C; // BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL
    table[0xC6] = 0x255E; // BOX DRAWINGS VERTICAL SINGLE AND RIGHT DOUBLE
    table[0xC7] = 0x255F; // BOX DRAWINGS VERTICAL DOUBLE AND RIGHT SINGLE
    table[0xC8] = 0x255A; // BOX DRAWINGS DOUBLE UP AND RIGHT
    table[0xC9] = 0x2554; // BOX DRAWINGS DOUBLE DOWN AND RIGHT
    table[0xCA] = 0x2569; // BOX DRAWINGS DOUBLE UP AND HORIZONTAL
    table[0xCB] = 0x2566; // BOX DRAWINGS DOUBLE DOWN AND HORIZONTAL
    table[0xCC] = 0x2560; // BOX DRAWINGS DOUBLE VERTICAL AND RIGHT
    table[0xCD] = 0x2550; // BOX DRAWINGS DOUBLE HORIZONTAL
    table[0xCE] = 0x256C; // BOX DRAWINGS DOUBLE VERTICAL AND HORIZONTAL
    table[0xCF] = 0x2567; // BOX DRAWINGS UP SINGLE AND HORIZONTAL DOUBLE
    table[0xD0] = 0x2568; // BOX DRAWINGS UP DOUBLE AND HORIZONTAL SINGLE
    table[0xD1] = 0x2564; // BOX DRAWINGS DOWN SINGLE AND HORIZONTAL DOUBLE
    table[0xD2] = 0x2565; // BOX DRAWINGS DOWN DOUBLE AND HORIZONTAL SINGLE
    table[0xD3] = 0x2559; // BOX DRAWINGS UP DOUBLE AND RIGHT SINGLE
    table[0xD4] = 0x2558; // BOX DRAWINGS UP SINGLE AND RIGHT DOUBLE
    table[0xD5] = 0x2552; // BOX DRAWINGS DOWN SINGLE AND RIGHT DOUBLE
    table[0xD6] = 0x2553; // BOX DRAWINGS DOWN DOUBLE AND RIGHT SINGLE
    table[0xD7] = 0x256B; // BOX DRAWINGS VERTICAL DOUBLE AND HORIZONTAL SINGLE
    table[0xD8] = 0x256A; // BOX DRAWINGS VERTICAL SINGLE AND HORIZONTAL DOUBLE
    table[0xD9] = 0x2518; // BOX DRAWINGS LIGHT UP AND LEFT
    table[0xDA] = 0x250C; // BOX DRAWINGS LIGHT DOWN AND RIGHT
    table[0xDB] = 0x2588; // FULL BLOCK
    table[0xDC] = 0x2584; // LOWER HALF BLOCK
    table[0xDD] = 0x258C; // LEFT HALF BLOCK
    table[0xDE] = 0x2590; // RIGHT HALF BLOCK
    table[0xDF] = 0x2580; // UPPER HALF BLOCK
    // 0xE0-0xFF
    table[0xE0] = 0x03B1; // GREEK SMALL LETTER ALPHA
    table[0xE1] = 0x00DF; // LATIN SMALL LETTER SHARP S
    table[0xE2] = 0x0393; // GREEK CAPITAL LETTER GAMMA
    table[0xE3] = 0x03C0; // GREEK SMALL LETTER PI
    table[0xE4] = 0x03A3; // GREEK CAPITAL LETTER SIGMA
    table[0xE5] = 0x03C3; // GREEK SMALL LETTER SIGMA
    table[0xE6] = 0x00B5; // MICRO SIGN
    table[0xE7] = 0x03C4; // GREEK SMALL LETTER TAU
    table[0xE8] = 0x03A6; // GREEK CAPITAL LETTER PHI
    table[0xE9] = 0x0398; // GREEK CAPITAL LETTER THETA
    table[0xEA] = 0x03A9; // GREEK CAPITAL LETTER OMEGA
    table[0xEB] = 0x03B4; // GREEK SMALL LETTER DELTA
    table[0xEC] = 0x221E; // INFINITY
    table[0xED] = 0x03C6; // GREEK SMALL LETTER PHI
    table[0xEE] = 0x03B5; // GREEK SMALL LETTER EPSILON
    table[0xEF] = 0x2229; // INTERSECTION
    table[0xF0] = 0x2261; // IDENTICAL TO
    table[0xF1] = 0x00B1; // PLUS-MINUS SIGN
    table[0xF2] = 0x2265; // GREATER-THAN OR EQUAL TO
    table[0xF3] = 0x2264; // LESS-THAN OR EQUAL TO
    table[0xF4] = 0x2320; // TOP HALF INTEGRAL
    table[0xF5] = 0x2321; // BOTTOM HALF INTEGRAL
    table[0xF6] = 0x00F7; // DIVISION SIGN
    table[0xF7] = 0x2248; // ALMOST EQUAL TO
    table[0xF8] = 0x00B0; // DEGREE SIGN
    table[0xF9] = 0x2219; // BULLET OPERATOR
    table[0xFA] = 0x00B7; // MIDDLE DOT
    table[0xFB] = 0x221A; // SQUARE ROOT
    table[0xFC] = 0x207F; // SUPERSCRIPT LATIN SMALL LETTER N
    table[0xFD] = 0x00B2; // SUPERSCRIPT TWO
    table[0xFE] = 0x25A0; // BLACK SQUARE
    table[0xFF] = 0x00A0; // NO-BREAK SPACE
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "cp862 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
