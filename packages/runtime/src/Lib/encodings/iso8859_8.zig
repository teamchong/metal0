//! CPython source: Lib/encodings/iso8859_8.py
//!
//! Hebrew alphabet
//!
//! Mirrors: CPython Lib/encodings/iso8859_8.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "iso8859-8";
pub const aliases = [_][]const u8{ "iso-8859-8", "hebrew", "iso_8859_8" };

const UNDEF = charmap.UNDEFINED;

/// ISO-8859-8 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x9F same as Latin-1
    for (0..0xA0) |i| table[i] = @intCast(i);
    // 0xA0-0xFF
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = UNDEF;
    table[0xA2] = 0x00A2; // CENT SIGN
    table[0xA3] = 0x00A3; // POUND SIGN
    table[0xA4] = 0x00A4; // CURRENCY SIGN
    table[0xA5] = 0x00A5; // YEN SIGN
    table[0xA6] = 0x00A6; // BROKEN BAR
    table[0xA7] = 0x00A7; // SECTION SIGN
    table[0xA8] = 0x00A8; // DIAERESIS
    table[0xA9] = 0x00A9; // COPYRIGHT SIGN
    table[0xAA] = 0x00D7; // MULTIPLICATION SIGN
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
    table[0xBA] = 0x00F7; // DIVISION SIGN
    table[0xBB] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xBC] = 0x00BC; // VULGAR FRACTION ONE QUARTER
    table[0xBD] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xBE] = 0x00BE; // VULGAR FRACTION THREE QUARTERS
    table[0xBF] = UNDEF;
    table[0xC0] = UNDEF;
    table[0xC1] = UNDEF;
    table[0xC2] = UNDEF;
    table[0xC3] = UNDEF;
    table[0xC4] = UNDEF;
    table[0xC5] = UNDEF;
    table[0xC6] = UNDEF;
    table[0xC7] = UNDEF;
    table[0xC8] = UNDEF;
    table[0xC9] = UNDEF;
    table[0xCA] = UNDEF;
    table[0xCB] = UNDEF;
    table[0xCC] = UNDEF;
    table[0xCD] = UNDEF;
    table[0xCE] = UNDEF;
    table[0xCF] = UNDEF;
    table[0xD0] = UNDEF;
    table[0xD1] = UNDEF;
    table[0xD2] = UNDEF;
    table[0xD3] = UNDEF;
    table[0xD4] = UNDEF;
    table[0xD5] = UNDEF;
    table[0xD6] = UNDEF;
    table[0xD7] = UNDEF;
    table[0xD8] = UNDEF;
    table[0xD9] = UNDEF;
    table[0xDA] = UNDEF;
    table[0xDB] = UNDEF;
    table[0xDC] = UNDEF;
    table[0xDD] = UNDEF;
    table[0xDE] = UNDEF;
    table[0xDF] = 0x2017; // DOUBLE LOW LINE
    table[0xE0] = 0x05D0; // HEBREW LETTER ALEF
    table[0xE1] = 0x05D1; // HEBREW LETTER BET
    table[0xE2] = 0x05D2; // HEBREW LETTER GIMEL
    table[0xE3] = 0x05D3; // HEBREW LETTER DALET
    table[0xE4] = 0x05D4; // HEBREW LETTER HE
    table[0xE5] = 0x05D5; // HEBREW LETTER VAV
    table[0xE6] = 0x05D6; // HEBREW LETTER ZAYIN
    table[0xE7] = 0x05D7; // HEBREW LETTER HET
    table[0xE8] = 0x05D8; // HEBREW LETTER TET
    table[0xE9] = 0x05D9; // HEBREW LETTER YOD
    table[0xEA] = 0x05DA; // HEBREW LETTER FINAL KAF
    table[0xEB] = 0x05DB; // HEBREW LETTER KAF
    table[0xEC] = 0x05DC; // HEBREW LETTER LAMED
    table[0xED] = 0x05DD; // HEBREW LETTER FINAL MEM
    table[0xEE] = 0x05DE; // HEBREW LETTER MEM
    table[0xEF] = 0x05DF; // HEBREW LETTER FINAL NUN
    table[0xF0] = 0x05E0; // HEBREW LETTER NUN
    table[0xF1] = 0x05E1; // HEBREW LETTER SAMEKH
    table[0xF2] = 0x05E2; // HEBREW LETTER AYIN
    table[0xF3] = 0x05E3; // HEBREW LETTER FINAL PE
    table[0xF4] = 0x05E4; // HEBREW LETTER PE
    table[0xF5] = 0x05E5; // HEBREW LETTER FINAL TSADI
    table[0xF6] = 0x05E6; // HEBREW LETTER TSADI
    table[0xF7] = 0x05E7; // HEBREW LETTER QOF
    table[0xF8] = 0x05E8; // HEBREW LETTER RESH
    table[0xF9] = 0x05E9; // HEBREW LETTER SHIN
    table[0xFA] = 0x05EA; // HEBREW LETTER TAV
    table[0xFB] = UNDEF;
    table[0xFC] = UNDEF;
    table[0xFD] = 0x200E; // LEFT-TO-RIGHT MARK
    table[0xFE] = 0x200F; // RIGHT-TO-LEFT MARK
    table[0xFF] = UNDEF;
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "iso8859_8 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
