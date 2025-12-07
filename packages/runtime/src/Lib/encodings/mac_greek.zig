//! CPython source: Lib/encodings/mac_greek.py
//!
//! Macintosh Greek encoding
//!
//! Mirrors: CPython Lib/encodings/mac_greek.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "mac-greek";
pub const aliases = [_][]const u8{ "mac_greek", "macgreek" };

const UNDEF = charmap.UNDEFINED;

/// Mac Greek decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F
    table[0x80] = 0x00C4; // LATIN CAPITAL LETTER A WITH DIAERESIS
    table[0x81] = 0x00B9; // SUPERSCRIPT ONE
    table[0x82] = 0x00B2; // SUPERSCRIPT TWO
    table[0x83] = 0x00C9; // LATIN CAPITAL LETTER E WITH ACUTE
    table[0x84] = 0x00B3; // SUPERSCRIPT THREE
    table[0x85] = 0x00D6; // LATIN CAPITAL LETTER O WITH DIAERESIS
    table[0x86] = 0x00DC; // LATIN CAPITAL LETTER U WITH DIAERESIS
    table[0x87] = 0x0385; // GREEK DIALYTIKA TONOS
    table[0x88] = 0x00E0; // LATIN SMALL LETTER A WITH GRAVE
    table[0x89] = 0x00E2; // LATIN SMALL LETTER A WITH CIRCUMFLEX
    table[0x8A] = 0x00E4; // LATIN SMALL LETTER A WITH DIAERESIS
    table[0x8B] = 0x0384; // GREEK TONOS
    table[0x8C] = 0x00A8; // DIAERESIS
    table[0x8D] = 0x00E7; // LATIN SMALL LETTER C WITH CEDILLA
    table[0x8E] = 0x00E9; // LATIN SMALL LETTER E WITH ACUTE
    table[0x8F] = 0x00E8; // LATIN SMALL LETTER E WITH GRAVE
    table[0x90] = 0x00EA; // LATIN SMALL LETTER E WITH CIRCUMFLEX
    table[0x91] = 0x00EB; // LATIN SMALL LETTER E WITH DIAERESIS
    table[0x92] = 0x00A3; // POUND SIGN
    table[0x93] = 0x2122; // TRADE MARK SIGN
    table[0x94] = 0x00EE; // LATIN SMALL LETTER I WITH CIRCUMFLEX
    table[0x95] = 0x00EF; // LATIN SMALL LETTER I WITH DIAERESIS
    table[0x96] = 0x2022; // BULLET
    table[0x97] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0x98] = 0x2030; // PER MILLE SIGN
    table[0x99] = 0x00F4; // LATIN SMALL LETTER O WITH CIRCUMFLEX
    table[0x9A] = 0x00F6; // LATIN SMALL LETTER O WITH DIAERESIS
    table[0x9B] = 0x00A6; // BROKEN BAR
    table[0x9C] = 0x00AD; // SOFT HYPHEN
    table[0x9D] = 0x00F9; // LATIN SMALL LETTER U WITH GRAVE
    table[0x9E] = 0x00FB; // LATIN SMALL LETTER U WITH CIRCUMFLEX
    table[0x9F] = 0x00FC; // LATIN SMALL LETTER U WITH DIAERESIS
    // 0xA0-0xAF
    table[0xA0] = 0x2020; // DAGGER
    table[0xA1] = 0x0393; // GREEK CAPITAL LETTER GAMMA
    table[0xA2] = 0x0394; // GREEK CAPITAL LETTER DELTA
    table[0xA3] = 0x0398; // GREEK CAPITAL LETTER THETA
    table[0xA4] = 0x039B; // GREEK CAPITAL LETTER LAMDA
    table[0xA5] = 0x039E; // GREEK CAPITAL LETTER XI
    table[0xA6] = 0x03A0; // GREEK CAPITAL LETTER PI
    table[0xA7] = 0x00DF; // LATIN SMALL LETTER SHARP S
    table[0xA8] = 0x00AE; // REGISTERED SIGN
    table[0xA9] = 0x00A9; // COPYRIGHT SIGN
    table[0xAA] = 0x03A3; // GREEK CAPITAL LETTER SIGMA
    table[0xAB] = 0x03AA; // GREEK CAPITAL LETTER IOTA WITH DIALYTIKA
    table[0xAC] = 0x00A7; // SECTION SIGN
    table[0xAD] = 0x2260; // NOT EQUAL TO
    table[0xAE] = 0x00B0; // DEGREE SIGN
    table[0xAF] = 0x0387; // GREEK ANO TELEIA
    // 0xB0-0xBF
    table[0xB0] = 0x0391; // GREEK CAPITAL LETTER ALPHA
    table[0xB1] = 0x00B1; // PLUS-MINUS SIGN
    table[0xB2] = 0x2264; // LESS-THAN OR EQUAL TO
    table[0xB3] = 0x2265; // GREATER-THAN OR EQUAL TO
    table[0xB4] = 0x00A5; // YEN SIGN
    table[0xB5] = 0x0392; // GREEK CAPITAL LETTER BETA
    table[0xB6] = 0x0395; // GREEK CAPITAL LETTER EPSILON
    table[0xB7] = 0x0396; // GREEK CAPITAL LETTER ZETA
    table[0xB8] = 0x0397; // GREEK CAPITAL LETTER ETA
    table[0xB9] = 0x0399; // GREEK CAPITAL LETTER IOTA
    table[0xBA] = 0x039A; // GREEK CAPITAL LETTER KAPPA
    table[0xBB] = 0x039C; // GREEK CAPITAL LETTER MU
    table[0xBC] = 0x03A6; // GREEK CAPITAL LETTER PHI
    table[0xBD] = 0x03AB; // GREEK CAPITAL LETTER UPSILON WITH DIALYTIKA
    table[0xBE] = 0x03A8; // GREEK CAPITAL LETTER PSI
    table[0xBF] = 0x03A9; // GREEK CAPITAL LETTER OMEGA
    // 0xC0-0xCF
    table[0xC0] = 0x03AC; // GREEK SMALL LETTER ALPHA WITH TONOS
    table[0xC1] = 0x039D; // GREEK CAPITAL LETTER NU
    table[0xC2] = 0x00AC; // NOT SIGN
    table[0xC3] = 0x039F; // GREEK CAPITAL LETTER OMICRON
    table[0xC4] = 0x03A1; // GREEK CAPITAL LETTER RHO
    table[0xC5] = 0x2248; // ALMOST EQUAL TO
    table[0xC6] = 0x03A4; // GREEK CAPITAL LETTER TAU
    table[0xC7] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xC8] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xC9] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0xCA] = 0x00A0; // NO-BREAK SPACE
    table[0xCB] = 0x03A5; // GREEK CAPITAL LETTER UPSILON
    table[0xCC] = 0x03A7; // GREEK CAPITAL LETTER CHI
    table[0xCD] = 0x0386; // GREEK CAPITAL LETTER ALPHA WITH TONOS
    table[0xCE] = 0x0388; // GREEK CAPITAL LETTER EPSILON WITH TONOS
    table[0xCF] = 0x0153; // LATIN SMALL LIGATURE OE
    // 0xD0-0xDF
    table[0xD0] = 0x2013; // EN DASH
    table[0xD1] = 0x2015; // HORIZONTAL BAR
    table[0xD2] = 0x201C; // LEFT DOUBLE QUOTATION MARK
    table[0xD3] = 0x201D; // RIGHT DOUBLE QUOTATION MARK
    table[0xD4] = 0x2018; // LEFT SINGLE QUOTATION MARK
    table[0xD5] = 0x2019; // RIGHT SINGLE QUOTATION MARK
    table[0xD6] = 0x00F7; // DIVISION SIGN
    table[0xD7] = 0x0389; // GREEK CAPITAL LETTER ETA WITH TONOS
    table[0xD8] = 0x038A; // GREEK CAPITAL LETTER IOTA WITH TONOS
    table[0xD9] = 0x038C; // GREEK CAPITAL LETTER OMICRON WITH TONOS
    table[0xDA] = 0x038E; // GREEK CAPITAL LETTER UPSILON WITH TONOS
    table[0xDB] = 0x03AD; // GREEK SMALL LETTER EPSILON WITH TONOS
    table[0xDC] = 0x03AE; // GREEK SMALL LETTER ETA WITH TONOS
    table[0xDD] = 0x03AF; // GREEK SMALL LETTER IOTA WITH TONOS
    table[0xDE] = 0x03CC; // GREEK SMALL LETTER OMICRON WITH TONOS
    table[0xDF] = 0x038F; // GREEK CAPITAL LETTER OMEGA WITH TONOS
    // 0xE0-0xFF
    table[0xE0] = 0x03CD; // GREEK SMALL LETTER UPSILON WITH TONOS
    table[0xE1] = 0x03B1; // GREEK SMALL LETTER ALPHA
    table[0xE2] = 0x03B2; // GREEK SMALL LETTER BETA
    table[0xE3] = 0x03C8; // GREEK SMALL LETTER PSI
    table[0xE4] = 0x03B4; // GREEK SMALL LETTER DELTA
    table[0xE5] = 0x03B5; // GREEK SMALL LETTER EPSILON
    table[0xE6] = 0x03C6; // GREEK SMALL LETTER PHI
    table[0xE7] = 0x03B3; // GREEK SMALL LETTER GAMMA
    table[0xE8] = 0x03B7; // GREEK SMALL LETTER ETA
    table[0xE9] = 0x03B9; // GREEK SMALL LETTER IOTA
    table[0xEA] = 0x03BE; // GREEK SMALL LETTER XI
    table[0xEB] = 0x03BA; // GREEK SMALL LETTER KAPPA
    table[0xEC] = 0x03BB; // GREEK SMALL LETTER LAMDA
    table[0xED] = 0x03BC; // GREEK SMALL LETTER MU
    table[0xEE] = 0x03BD; // GREEK SMALL LETTER NU
    table[0xEF] = 0x03BF; // GREEK SMALL LETTER OMICRON
    table[0xF0] = 0x03C0; // GREEK SMALL LETTER PI
    table[0xF1] = 0x03CE; // GREEK SMALL LETTER OMEGA WITH TONOS
    table[0xF2] = 0x03C1; // GREEK SMALL LETTER RHO
    table[0xF3] = 0x03C3; // GREEK SMALL LETTER SIGMA
    table[0xF4] = 0x03C4; // GREEK SMALL LETTER TAU
    table[0xF5] = 0x03B8; // GREEK SMALL LETTER THETA
    table[0xF6] = 0x03C9; // GREEK SMALL LETTER OMEGA
    table[0xF7] = 0x03C2; // GREEK SMALL LETTER FINAL SIGMA
    table[0xF8] = 0x03C7; // GREEK SMALL LETTER CHI
    table[0xF9] = 0x03C5; // GREEK SMALL LETTER UPSILON
    table[0xFA] = 0x03B6; // GREEK SMALL LETTER ZETA
    table[0xFB] = 0x03CA; // GREEK SMALL LETTER IOTA WITH DIALYTIKA
    table[0xFC] = 0x03CB; // GREEK SMALL LETTER UPSILON WITH DIALYTIKA
    table[0xFD] = 0x0390; // GREEK SMALL LETTER IOTA WITH DIALYTIKA AND TONOS
    table[0xFE] = 0x03B0; // GREEK SMALL LETTER UPSILON WITH DIALYTIKA AND TONOS
    table[0xFF] = UNDEF;
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "mac_greek decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
