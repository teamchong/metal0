//! CPython source: Lib/encodings/cp1254.py
//!
//! Windows Turkish codepage (similar to Latin-5 with extra characters)
//!
//! Mirrors: CPython Lib/encodings/cp1254.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp1254";
pub const aliases = [_][]const u8{ "windows-1254" };

const UNDEF = charmap.UNDEFINED;

/// CP1254 decode table (similar to cp1252 with Turkish changes)
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F (Windows-specific)
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
    table[0x8A] = 0x0160; // LATIN CAPITAL LETTER S WITH CARON
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
    table[0x9A] = 0x0161; // LATIN SMALL LETTER S WITH CARON
    table[0x9B] = 0x203A; // SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    table[0x9C] = 0x0153; // LATIN SMALL LIGATURE OE
    table[0x9D] = UNDEF;
    table[0x9E] = UNDEF;
    table[0x9F] = 0x0178; // LATIN CAPITAL LETTER Y WITH DIAERESIS
    // 0xA0-0xCF same as Latin-1
    for (0xA0..0xD0) |i| table[i] = @intCast(i);
    // Turkish modifications
    table[0xD0] = 0x011E; // LATIN CAPITAL LETTER G WITH BREVE
    for (0xD1..0xDD) |i| table[i] = @intCast(i);
    table[0xDD] = 0x0130; // LATIN CAPITAL LETTER I WITH DOT ABOVE
    table[0xDE] = 0x015E; // LATIN CAPITAL LETTER S WITH CEDILLA
    for (0xDF..0xF0) |i| table[i] = @intCast(i);
    table[0xF0] = 0x011F; // LATIN SMALL LETTER G WITH BREVE
    for (0xF1..0xFD) |i| table[i] = @intCast(i);
    table[0xFD] = 0x0131; // LATIN SMALL LETTER DOTLESS I
    table[0xFE] = 0x015F; // LATIN SMALL LETTER S WITH CEDILLA
    table[0xFF] = 0x00FF;
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "cp1254 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
