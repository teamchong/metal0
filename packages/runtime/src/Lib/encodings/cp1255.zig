//! CPython source: Lib/encodings/cp1255.py
//!
//! Windows Hebrew codepage
//!
//! Mirrors: CPython Lib/encodings/cp1255.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp1255";
pub const aliases = [_][]const u8{ "windows-1255" };

const UNDEF = charmap.UNDEFINED;

/// CP1255 decode table
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
    table[0x8C] = UNDEF;
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
    table[0x9C] = UNDEF;
    table[0x9D] = UNDEF;
    table[0x9E] = UNDEF;
    table[0x9F] = UNDEF;
    // 0xA0-0xBF
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = 0x00A1; // INVERTED EXCLAMATION MARK
    table[0xA2] = 0x00A2; // CENT SIGN
    table[0xA3] = 0x00A3; // POUND SIGN
    table[0xA4] = 0x20AA; // NEW SHEQEL SIGN
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
    table[0xBF] = 0x00BF; // INVERTED QUESTION MARK
    // 0xC0-0xC9: Hebrew vowel marks
    table[0xC0] = 0x05B0; // HEBREW POINT SHEVA
    table[0xC1] = 0x05B1; // HEBREW POINT HATAF SEGOL
    table[0xC2] = 0x05B2; // HEBREW POINT HATAF PATAH
    table[0xC3] = 0x05B3; // HEBREW POINT HATAF QAMATS
    table[0xC4] = 0x05B4; // HEBREW POINT HIRIQ
    table[0xC5] = 0x05B5; // HEBREW POINT TSERE
    table[0xC6] = 0x05B6; // HEBREW POINT SEGOL
    table[0xC7] = 0x05B7; // HEBREW POINT PATAH
    table[0xC8] = 0x05B8; // HEBREW POINT QAMATS
    table[0xC9] = 0x05B9; // HEBREW POINT HOLAM
    table[0xCA] = UNDEF;
    table[0xCB] = 0x05BB; // HEBREW POINT QUBUTS
    table[0xCC] = 0x05BC; // HEBREW POINT DAGESH OR MAPIQ
    table[0xCD] = 0x05BD; // HEBREW POINT METEG
    table[0xCE] = 0x05BE; // HEBREW PUNCTUATION MAQAF
    table[0xCF] = 0x05BF; // HEBREW POINT RAFE
    table[0xD0] = 0x05C0; // HEBREW PUNCTUATION PASEQ
    table[0xD1] = 0x05C1; // HEBREW POINT SHIN DOT
    table[0xD2] = 0x05C2; // HEBREW POINT SIN DOT
    table[0xD3] = 0x05C3; // HEBREW PUNCTUATION SOF PASUQ
    table[0xD4] = 0x05F0; // HEBREW LIGATURE YIDDISH DOUBLE VAV
    table[0xD5] = 0x05F1; // HEBREW LIGATURE YIDDISH VAV YOD
    table[0xD6] = 0x05F2; // HEBREW LIGATURE YIDDISH DOUBLE YOD
    table[0xD7] = 0x05F3; // HEBREW PUNCTUATION GERESH
    table[0xD8] = 0x05F4; // HEBREW PUNCTUATION GERSHAYIM
    table[0xD9] = UNDEF;
    table[0xDA] = UNDEF;
    table[0xDB] = UNDEF;
    table[0xDC] = UNDEF;
    table[0xDD] = UNDEF;
    table[0xDE] = UNDEF;
    table[0xDF] = UNDEF;
    // 0xE0-0xFA: Hebrew letters
    for (0xE0..0xFB) |i| table[i] = 0x05D0 + @as(u21, @intCast(i)) - 0xE0;
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

test "cp1255 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
