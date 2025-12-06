//! Python 'cp1257' Codec (Windows-1257 / Baltic)
//!
//! Windows Baltic codepage
//!
//! Mirrors: CPython Lib/encodings/cp1257.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp1257";
pub const aliases = [_][]const u8{ "windows-1257" };

const UNDEF = charmap.UNDEFINED;

/// CP1257 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F
    table[0x80] = 0x20AC; // EURO SIGN
    table[0x81] = UNDEF;
    table[0x82] = 0x201A; // SINGLE LOW-9 QUOTATION MARK
    table[0x83] = UNDEF;
    table[0x84] = 0x201E; // DOUBLE LOW-9 QUOTATION MARK
    table[0x85] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0x86] = 0x2020; // DAGGER
    table[0x87] = 0x2021; // DOUBLE DAGGER
    table[0x88] = UNDEF;
    table[0x89] = 0x2030; // PER MILLE SIGN
    table[0x8A] = UNDEF;
    table[0x8B] = 0x2039; // SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    table[0x8C] = UNDEF;
    table[0x8D] = 0x00A8; // DIAERESIS
    table[0x8E] = 0x02C7; // CARON
    table[0x8F] = 0x00B8; // CEDILLA
    table[0x90] = UNDEF;
    table[0x91] = 0x2018; // LEFT SINGLE QUOTATION MARK
    table[0x92] = 0x2019; // RIGHT SINGLE QUOTATION MARK
    table[0x93] = 0x201C; // LEFT DOUBLE QUOTATION MARK
    table[0x94] = 0x201D; // RIGHT DOUBLE QUOTATION MARK
    table[0x95] = 0x2022; // BULLET
    table[0x96] = 0x2013; // EN DASH
    table[0x97] = 0x2014; // EM DASH
    table[0x98] = UNDEF;
    table[0x99] = 0x2122; // TRADE MARK SIGN
    table[0x9A] = UNDEF;
    table[0x9B] = 0x203A; // SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    table[0x9C] = UNDEF;
    table[0x9D] = 0x00AF; // MACRON
    table[0x9E] = 0x02DB; // OGONEK
    table[0x9F] = UNDEF;
    // 0xA0-0xFF
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = UNDEF;
    table[0xA2] = 0x00A2; // CENT SIGN
    table[0xA3] = 0x00A3; // POUND SIGN
    table[0xA4] = 0x00A4; // CURRENCY SIGN
    table[0xA5] = UNDEF;
    table[0xA6] = 0x00A6; // BROKEN BAR
    table[0xA7] = 0x00A7; // SECTION SIGN
    table[0xA8] = 0x00D8; // LATIN CAPITAL LETTER O WITH STROKE
    table[0xA9] = 0x00A9; // COPYRIGHT SIGN
    table[0xAA] = 0x0156; // LATIN CAPITAL LETTER R WITH CEDILLA
    table[0xAB] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xAC] = 0x00AC; // NOT SIGN
    table[0xAD] = 0x00AD; // SOFT HYPHEN
    table[0xAE] = 0x00AE; // REGISTERED SIGN
    table[0xAF] = 0x00C6; // LATIN CAPITAL LETTER AE
    table[0xB0] = 0x00B0; // DEGREE SIGN
    table[0xB1] = 0x00B1; // PLUS-MINUS SIGN
    table[0xB2] = 0x00B2; // SUPERSCRIPT TWO
    table[0xB3] = 0x00B3; // SUPERSCRIPT THREE
    table[0xB4] = 0x00B4; // ACUTE ACCENT
    table[0xB5] = 0x00B5; // MICRO SIGN
    table[0xB6] = 0x00B6; // PILCROW SIGN
    table[0xB7] = 0x00B7; // MIDDLE DOT
    table[0xB8] = 0x00F8; // LATIN SMALL LETTER O WITH STROKE
    table[0xB9] = 0x00B9; // SUPERSCRIPT ONE
    table[0xBA] = 0x0157; // LATIN SMALL LETTER R WITH CEDILLA
    table[0xBB] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xBC] = 0x00BC; // VULGAR FRACTION ONE QUARTER
    table[0xBD] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xBE] = 0x00BE; // VULGAR FRACTION THREE QUARTERS
    table[0xBF] = 0x00E6; // LATIN SMALL LETTER AE
    table[0xC0] = 0x0104; // LATIN CAPITAL LETTER A WITH OGONEK
    table[0xC1] = 0x012E; // LATIN CAPITAL LETTER I WITH OGONEK
    table[0xC2] = 0x0100; // LATIN CAPITAL LETTER A WITH MACRON
    table[0xC3] = 0x0106; // LATIN CAPITAL LETTER C WITH ACUTE
    table[0xC4] = 0x00C4; // LATIN CAPITAL LETTER A WITH DIAERESIS
    table[0xC5] = 0x00C5; // LATIN CAPITAL LETTER A WITH RING ABOVE
    table[0xC6] = 0x0118; // LATIN CAPITAL LETTER E WITH OGONEK
    table[0xC7] = 0x0112; // LATIN CAPITAL LETTER E WITH MACRON
    table[0xC8] = 0x010C; // LATIN CAPITAL LETTER C WITH CARON
    table[0xC9] = 0x00C9; // LATIN CAPITAL LETTER E WITH ACUTE
    table[0xCA] = 0x0179; // LATIN CAPITAL LETTER Z WITH ACUTE
    table[0xCB] = 0x0116; // LATIN CAPITAL LETTER E WITH DOT ABOVE
    table[0xCC] = 0x0122; // LATIN CAPITAL LETTER G WITH CEDILLA
    table[0xCD] = 0x0136; // LATIN CAPITAL LETTER K WITH CEDILLA
    table[0xCE] = 0x012A; // LATIN CAPITAL LETTER I WITH MACRON
    table[0xCF] = 0x013B; // LATIN CAPITAL LETTER L WITH CEDILLA
    table[0xD0] = 0x0160; // LATIN CAPITAL LETTER S WITH CARON
    table[0xD1] = 0x0143; // LATIN CAPITAL LETTER N WITH ACUTE
    table[0xD2] = 0x0145; // LATIN CAPITAL LETTER N WITH CEDILLA
    table[0xD3] = 0x00D3; // LATIN CAPITAL LETTER O WITH ACUTE
    table[0xD4] = 0x014C; // LATIN CAPITAL LETTER O WITH MACRON
    table[0xD5] = 0x00D5; // LATIN CAPITAL LETTER O WITH TILDE
    table[0xD6] = 0x00D6; // LATIN CAPITAL LETTER O WITH DIAERESIS
    table[0xD7] = 0x00D7; // MULTIPLICATION SIGN
    table[0xD8] = 0x0172; // LATIN CAPITAL LETTER U WITH OGONEK
    table[0xD9] = 0x0141; // LATIN CAPITAL LETTER L WITH STROKE
    table[0xDA] = 0x015A; // LATIN CAPITAL LETTER S WITH ACUTE
    table[0xDB] = 0x016A; // LATIN CAPITAL LETTER U WITH MACRON
    table[0xDC] = 0x00DC; // LATIN CAPITAL LETTER U WITH DIAERESIS
    table[0xDD] = 0x017B; // LATIN CAPITAL LETTER Z WITH DOT ABOVE
    table[0xDE] = 0x017D; // LATIN CAPITAL LETTER Z WITH CARON
    table[0xDF] = 0x00DF; // LATIN SMALL LETTER SHARP S
    table[0xE0] = 0x0105; // LATIN SMALL LETTER A WITH OGONEK
    table[0xE1] = 0x012F; // LATIN SMALL LETTER I WITH OGONEK
    table[0xE2] = 0x0101; // LATIN SMALL LETTER A WITH MACRON
    table[0xE3] = 0x0107; // LATIN SMALL LETTER C WITH ACUTE
    table[0xE4] = 0x00E4; // LATIN SMALL LETTER A WITH DIAERESIS
    table[0xE5] = 0x00E5; // LATIN SMALL LETTER A WITH RING ABOVE
    table[0xE6] = 0x0119; // LATIN SMALL LETTER E WITH OGONEK
    table[0xE7] = 0x0113; // LATIN SMALL LETTER E WITH MACRON
    table[0xE8] = 0x010D; // LATIN SMALL LETTER C WITH CARON
    table[0xE9] = 0x00E9; // LATIN SMALL LETTER E WITH ACUTE
    table[0xEA] = 0x017A; // LATIN SMALL LETTER Z WITH ACUTE
    table[0xEB] = 0x0117; // LATIN SMALL LETTER E WITH DOT ABOVE
    table[0xEC] = 0x0123; // LATIN SMALL LETTER G WITH CEDILLA
    table[0xED] = 0x0137; // LATIN SMALL LETTER K WITH CEDILLA
    table[0xEE] = 0x012B; // LATIN SMALL LETTER I WITH MACRON
    table[0xEF] = 0x013C; // LATIN SMALL LETTER L WITH CEDILLA
    table[0xF0] = 0x0161; // LATIN SMALL LETTER S WITH CARON
    table[0xF1] = 0x0144; // LATIN SMALL LETTER N WITH ACUTE
    table[0xF2] = 0x0146; // LATIN SMALL LETTER N WITH CEDILLA
    table[0xF3] = 0x00F3; // LATIN SMALL LETTER O WITH ACUTE
    table[0xF4] = 0x014D; // LATIN SMALL LETTER O WITH MACRON
    table[0xF5] = 0x00F5; // LATIN SMALL LETTER O WITH TILDE
    table[0xF6] = 0x00F6; // LATIN SMALL LETTER O WITH DIAERESIS
    table[0xF7] = 0x00F7; // DIVISION SIGN
    table[0xF8] = 0x0173; // LATIN SMALL LETTER U WITH OGONEK
    table[0xF9] = 0x0142; // LATIN SMALL LETTER L WITH STROKE
    table[0xFA] = 0x015B; // LATIN SMALL LETTER S WITH ACUTE
    table[0xFB] = 0x016B; // LATIN SMALL LETTER U WITH MACRON
    table[0xFC] = 0x00FC; // LATIN SMALL LETTER U WITH DIAERESIS
    table[0xFD] = 0x017C; // LATIN SMALL LETTER Z WITH DOT ABOVE
    table[0xFE] = 0x017E; // LATIN SMALL LETTER Z WITH CARON
    table[0xFF] = 0x02D9; // DOT ABOVE
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "cp1257 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
