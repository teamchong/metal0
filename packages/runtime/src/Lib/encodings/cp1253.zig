//! Python 'cp1253' Codec (Windows-1253 / Greek)
//!
//! Windows Greek codepage
//!
//! Mirrors: CPython Lib/encodings/cp1253.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp1253";
pub const aliases = [_][]const u8{ "windows-1253" };

const UNDEF = charmap.UNDEFINED;

/// CP1253 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0xFF
    table[0x80] = 0x20AC; // EURO SIGN
    table[0x81] = UNDEF;
    table[0x82] = 0x201A; // SINGLE LOW-9 QUOTATION MARK
    table[0x83] = 0x0192; // LATIN SMALL LETTER F WITH HOOK
    table[0x84] = 0x201E; // DOUBLE LOW-9 QUOTATION MARK
    table[0x85] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0x86] = 0x2020; // DAGGER
    table[0x87] = 0x2021; // DOUBLE DAGGER
    table[0x88] = UNDEF;
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
    table[0x98] = UNDEF;
    table[0x99] = 0x2122; // TRADE MARK SIGN
    table[0x9A] = UNDEF;
    table[0x9B] = 0x203A; // SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    table[0x9C] = UNDEF;
    table[0x9D] = UNDEF;
    table[0x9E] = UNDEF;
    table[0x9F] = UNDEF;
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = 0x0385; // GREEK DIALYTIKA TONOS
    table[0xA2] = 0x0386; // GREEK CAPITAL LETTER ALPHA WITH TONOS
    table[0xA3] = 0x00A3; // POUND SIGN
    table[0xA4] = 0x00A4; // CURRENCY SIGN
    table[0xA5] = 0x00A5; // YEN SIGN
    table[0xA6] = 0x00A6; // BROKEN BAR
    table[0xA7] = 0x00A7; // SECTION SIGN
    table[0xA8] = 0x00A8; // DIAERESIS
    table[0xA9] = 0x00A9; // COPYRIGHT SIGN
    table[0xAA] = UNDEF;
    table[0xAB] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xAC] = 0x00AC; // NOT SIGN
    table[0xAD] = 0x00AD; // SOFT HYPHEN
    table[0xAE] = 0x00AE; // REGISTERED SIGN
    table[0xAF] = 0x2015; // HORIZONTAL BAR
    table[0xB0] = 0x00B0; // DEGREE SIGN
    table[0xB1] = 0x00B1; // PLUS-MINUS SIGN
    table[0xB2] = 0x00B2; // SUPERSCRIPT TWO
    table[0xB3] = 0x00B3; // SUPERSCRIPT THREE
    table[0xB4] = 0x0384; // GREEK TONOS
    table[0xB5] = 0x00B5; // MICRO SIGN
    table[0xB6] = 0x00B6; // PILCROW SIGN
    table[0xB7] = 0x00B7; // MIDDLE DOT
    table[0xB8] = 0x0388; // GREEK CAPITAL LETTER EPSILON WITH TONOS
    table[0xB9] = 0x0389; // GREEK CAPITAL LETTER ETA WITH TONOS
    table[0xBA] = 0x038A; // GREEK CAPITAL LETTER IOTA WITH TONOS
    table[0xBB] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xBC] = 0x038C; // GREEK CAPITAL LETTER OMICRON WITH TONOS
    table[0xBD] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xBE] = 0x038E; // GREEK CAPITAL LETTER UPSILON WITH TONOS
    table[0xBF] = 0x038F; // GREEK CAPITAL LETTER OMEGA WITH TONOS
    table[0xC0] = 0x0390; // GREEK SMALL LETTER IOTA WITH DIALYTIKA AND TONOS
    for (0xC1..0xD2) |i| table[i] = 0x0391 + @as(u21, @intCast(i)) - 0xC1; // Alpha to Rho
    table[0xD2] = UNDEF;
    for (0xD3..0xDA) |i| table[i] = 0x03A3 + @as(u21, @intCast(i)) - 0xD3; // Sigma to Omega
    table[0xDA] = 0x03AA; // GREEK CAPITAL LETTER IOTA WITH DIALYTIKA
    table[0xDB] = 0x03AB; // GREEK CAPITAL LETTER UPSILON WITH DIALYTIKA
    table[0xDC] = 0x03AC; // GREEK SMALL LETTER ALPHA WITH TONOS
    table[0xDD] = 0x03AD; // GREEK SMALL LETTER EPSILON WITH TONOS
    table[0xDE] = 0x03AE; // GREEK SMALL LETTER ETA WITH TONOS
    table[0xDF] = 0x03AF; // GREEK SMALL LETTER IOTA WITH TONOS
    table[0xE0] = 0x03B0; // GREEK SMALL LETTER UPSILON WITH DIALYTIKA AND TONOS
    for (0xE1..0xF2) |i| table[i] = 0x03B1 + @as(u21, @intCast(i)) - 0xE1; // alpha to rho
    table[0xF2] = 0x03C2; // GREEK SMALL LETTER FINAL SIGMA
    for (0xF3..0xFA) |i| table[i] = 0x03C3 + @as(u21, @intCast(i)) - 0xF3; // sigma to omega
    table[0xFA] = 0x03CA; // GREEK SMALL LETTER IOTA WITH DIALYTIKA
    table[0xFB] = 0x03CB; // GREEK SMALL LETTER UPSILON WITH DIALYTIKA
    table[0xFC] = 0x03CC; // GREEK SMALL LETTER OMICRON WITH TONOS
    table[0xFD] = 0x03CD; // GREEK SMALL LETTER UPSILON WITH TONOS
    table[0xFE] = 0x03CE; // GREEK SMALL LETTER OMEGA WITH TONOS
    table[0xFF] = UNDEF;
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "cp1253 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
