//! CPython source: Lib/encodings/cp856.py
//!
//! DOS Hebrew codepage (IBM PC)
//!
//! Mirrors: CPython Lib/encodings/cp856.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp856";
pub const aliases = [_][]const u8{};

const UNDEF = charmap.UNDEFINED;

/// CP856 decode table
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
    table[0x9B] = UNDEF;
    table[0x9C] = 0x00A3; // POUND SIGN
    table[0x9D] = UNDEF;
    table[0x9E] = 0x00D7; // MULTIPLICATION SIGN
    table[0x9F] = UNDEF;
    // 0xA0-0xAF
    table[0xA0] = UNDEF;
    table[0xA1] = UNDEF;
    table[0xA2] = UNDEF;
    table[0xA3] = UNDEF;
    table[0xA4] = UNDEF;
    table[0xA5] = UNDEF;
    table[0xA6] = UNDEF;
    table[0xA7] = UNDEF;
    table[0xA8] = UNDEF;
    table[0xA9] = 0x00AE; // REGISTERED SIGN
    table[0xAA] = 0x00AC; // NOT SIGN
    table[0xAB] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xAC] = 0x00BC; // VULGAR FRACTION ONE QUARTER
    table[0xAD] = UNDEF;
    table[0xAE] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xAF] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    // 0xB0-0xDF: Box drawing characters
    table[0xB0] = 0x2591; // LIGHT SHADE
    table[0xB1] = 0x2592; // MEDIUM SHADE
    table[0xB2] = 0x2593; // DARK SHADE
    table[0xB3] = 0x2502; // BOX DRAWINGS LIGHT VERTICAL
    table[0xB4] = 0x2524; // BOX DRAWINGS LIGHT VERTICAL AND LEFT
    table[0xB5] = UNDEF;
    table[0xB6] = UNDEF;
    table[0xB7] = UNDEF;
    table[0xB8] = 0x00A9; // COPYRIGHT SIGN
    table[0xB9] = 0x2563; // BOX DRAWINGS DOUBLE VERTICAL AND LEFT
    table[0xBA] = 0x2551; // BOX DRAWINGS DOUBLE VERTICAL
    table[0xBB] = 0x2557; // BOX DRAWINGS DOUBLE DOWN AND LEFT
    table[0xBC] = 0x255D; // BOX DRAWINGS DOUBLE UP AND LEFT
    table[0xBD] = 0x00A2; // CENT SIGN
    table[0xBE] = 0x00A5; // YEN SIGN
    table[0xBF] = 0x2510; // BOX DRAWINGS LIGHT DOWN AND LEFT
    table[0xC0] = 0x2514; // BOX DRAWINGS LIGHT UP AND RIGHT
    table[0xC1] = 0x2534; // BOX DRAWINGS LIGHT UP AND HORIZONTAL
    table[0xC2] = 0x252C; // BOX DRAWINGS LIGHT DOWN AND HORIZONTAL
    table[0xC3] = 0x251C; // BOX DRAWINGS LIGHT VERTICAL AND RIGHT
    table[0xC4] = 0x2500; // BOX DRAWINGS LIGHT HORIZONTAL
    table[0xC5] = 0x253C; // BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL
    table[0xC6] = UNDEF;
    table[0xC7] = UNDEF;
    table[0xC8] = 0x255A; // BOX DRAWINGS DOUBLE UP AND RIGHT
    table[0xC9] = 0x2554; // BOX DRAWINGS DOUBLE DOWN AND RIGHT
    table[0xCA] = 0x2569; // BOX DRAWINGS DOUBLE UP AND HORIZONTAL
    table[0xCB] = 0x2566; // BOX DRAWINGS DOUBLE DOWN AND HORIZONTAL
    table[0xCC] = 0x2560; // BOX DRAWINGS DOUBLE VERTICAL AND RIGHT
    table[0xCD] = 0x2550; // BOX DRAWINGS DOUBLE HORIZONTAL
    table[0xCE] = 0x256C; // BOX DRAWINGS DOUBLE VERTICAL AND HORIZONTAL
    table[0xCF] = 0x00A4; // CURRENCY SIGN
    table[0xD0] = UNDEF;
    table[0xD1] = UNDEF;
    table[0xD2] = UNDEF;
    table[0xD3] = UNDEF;
    table[0xD4] = UNDEF;
    table[0xD5] = UNDEF;
    table[0xD6] = UNDEF;
    table[0xD7] = UNDEF;
    table[0xD8] = UNDEF;
    table[0xD9] = 0x2518; // BOX DRAWINGS LIGHT UP AND LEFT
    table[0xDA] = 0x250C; // BOX DRAWINGS LIGHT DOWN AND RIGHT
    table[0xDB] = 0x2588; // FULL BLOCK
    table[0xDC] = 0x2584; // LOWER HALF BLOCK
    table[0xDD] = 0x00A6; // BROKEN BAR
    table[0xDE] = UNDEF;
    table[0xDF] = 0x2580; // UPPER HALF BLOCK
    // 0xE0-0xFF
    table[0xE0] = UNDEF;
    table[0xE1] = UNDEF;
    table[0xE2] = UNDEF;
    table[0xE3] = UNDEF;
    table[0xE4] = UNDEF;
    table[0xE5] = UNDEF;
    table[0xE6] = 0x00B5; // MICRO SIGN
    table[0xE7] = UNDEF;
    table[0xE8] = UNDEF;
    table[0xE9] = UNDEF;
    table[0xEA] = UNDEF;
    table[0xEB] = UNDEF;
    table[0xEC] = UNDEF;
    table[0xED] = UNDEF;
    table[0xEE] = 0x00AF; // MACRON
    table[0xEF] = 0x00B4; // ACUTE ACCENT
    table[0xF0] = 0x00AD; // SOFT HYPHEN
    table[0xF1] = 0x00B1; // PLUS-MINUS SIGN
    table[0xF2] = 0x2017; // DOUBLE LOW LINE
    table[0xF3] = 0x00BE; // VULGAR FRACTION THREE QUARTERS
    table[0xF4] = 0x00B6; // PILCROW SIGN
    table[0xF5] = 0x00A7; // SECTION SIGN
    table[0xF6] = 0x00F7; // DIVISION SIGN
    table[0xF7] = 0x00B8; // CEDILLA
    table[0xF8] = 0x00B0; // DEGREE SIGN
    table[0xF9] = 0x00A8; // DIAERESIS
    table[0xFA] = 0x00B7; // MIDDLE DOT
    table[0xFB] = 0x00B9; // SUPERSCRIPT ONE
    table[0xFC] = 0x00B3; // SUPERSCRIPT THREE
    table[0xFD] = 0x00B2; // SUPERSCRIPT TWO
    table[0xFE] = 0x25A0; // BLACK SQUARE
    table[0xFF] = 0x00A0; // NO-BREAK SPACE
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "cp856 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
