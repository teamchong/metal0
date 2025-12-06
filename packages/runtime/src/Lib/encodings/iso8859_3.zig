//! Python 'iso8859-3' Codec (ISO-8859-3 / Latin-3)
//!
//! South European (Turkish, Maltese, Esperanto)
//!
//! Mirrors: CPython Lib/encodings/iso8859_3.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "iso8859-3";
pub const aliases = [_][]const u8{ "iso-8859-3", "latin3", "l3", "iso_8859_3" };

const UNDEF = charmap.UNDEFINED;

/// ISO-8859-3 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x9F same as Latin-1
    for (0..0xA0) |i| table[i] = @intCast(i);
    // 0xA0-0xFF
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = 0x0126; // LATIN CAPITAL LETTER H WITH STROKE
    table[0xA2] = 0x02D8; // BREVE
    table[0xA3] = 0x00A3; // POUND SIGN
    table[0xA4] = 0x00A4; // CURRENCY SIGN
    table[0xA5] = UNDEF;
    table[0xA6] = 0x0124; // LATIN CAPITAL LETTER H WITH CIRCUMFLEX
    table[0xA7] = 0x00A7; // SECTION SIGN
    table[0xA8] = 0x00A8; // DIAERESIS
    table[0xA9] = 0x0130; // LATIN CAPITAL LETTER I WITH DOT ABOVE
    table[0xAA] = 0x015E; // LATIN CAPITAL LETTER S WITH CEDILLA
    table[0xAB] = 0x011E; // LATIN CAPITAL LETTER G WITH BREVE
    table[0xAC] = 0x0134; // LATIN CAPITAL LETTER J WITH CIRCUMFLEX
    table[0xAD] = 0x00AD; // SOFT HYPHEN
    table[0xAE] = UNDEF;
    table[0xAF] = 0x017B; // LATIN CAPITAL LETTER Z WITH DOT ABOVE
    table[0xB0] = 0x00B0; // DEGREE SIGN
    table[0xB1] = 0x0127; // LATIN SMALL LETTER H WITH STROKE
    table[0xB2] = 0x00B2; // SUPERSCRIPT TWO
    table[0xB3] = 0x00B3; // SUPERSCRIPT THREE
    table[0xB4] = 0x00B4; // ACUTE ACCENT
    table[0xB5] = 0x00B5; // MICRO SIGN
    table[0xB6] = 0x0125; // LATIN SMALL LETTER H WITH CIRCUMFLEX
    table[0xB7] = 0x00B7; // MIDDLE DOT
    table[0xB8] = 0x00B8; // CEDILLA
    table[0xB9] = 0x0131; // LATIN SMALL LETTER DOTLESS I
    table[0xBA] = 0x015F; // LATIN SMALL LETTER S WITH CEDILLA
    table[0xBB] = 0x011F; // LATIN SMALL LETTER G WITH BREVE
    table[0xBC] = 0x0135; // LATIN SMALL LETTER J WITH CIRCUMFLEX
    table[0xBD] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xBE] = UNDEF;
    table[0xBF] = 0x017C; // LATIN SMALL LETTER Z WITH DOT ABOVE
    table[0xC0] = 0x00C0; // LATIN CAPITAL LETTER A WITH GRAVE
    table[0xC1] = 0x00C1; // LATIN CAPITAL LETTER A WITH ACUTE
    table[0xC2] = 0x00C2; // LATIN CAPITAL LETTER A WITH CIRCUMFLEX
    table[0xC3] = UNDEF;
    table[0xC4] = 0x00C4; // LATIN CAPITAL LETTER A WITH DIAERESIS
    table[0xC5] = 0x010A; // LATIN CAPITAL LETTER C WITH DOT ABOVE
    table[0xC6] = 0x0108; // LATIN CAPITAL LETTER C WITH CIRCUMFLEX
    table[0xC7] = 0x00C7; // LATIN CAPITAL LETTER C WITH CEDILLA
    table[0xC8] = 0x00C8; // LATIN CAPITAL LETTER E WITH GRAVE
    table[0xC9] = 0x00C9; // LATIN CAPITAL LETTER E WITH ACUTE
    table[0xCA] = 0x00CA; // LATIN CAPITAL LETTER E WITH CIRCUMFLEX
    table[0xCB] = 0x00CB; // LATIN CAPITAL LETTER E WITH DIAERESIS
    table[0xCC] = 0x00CC; // LATIN CAPITAL LETTER I WITH GRAVE
    table[0xCD] = 0x00CD; // LATIN CAPITAL LETTER I WITH ACUTE
    table[0xCE] = 0x00CE; // LATIN CAPITAL LETTER I WITH CIRCUMFLEX
    table[0xCF] = 0x00CF; // LATIN CAPITAL LETTER I WITH DIAERESIS
    table[0xD0] = UNDEF;
    table[0xD1] = 0x00D1; // LATIN CAPITAL LETTER N WITH TILDE
    table[0xD2] = 0x00D2; // LATIN CAPITAL LETTER O WITH GRAVE
    table[0xD3] = 0x00D3; // LATIN CAPITAL LETTER O WITH ACUTE
    table[0xD4] = 0x00D4; // LATIN CAPITAL LETTER O WITH CIRCUMFLEX
    table[0xD5] = 0x0120; // LATIN CAPITAL LETTER G WITH DOT ABOVE
    table[0xD6] = 0x00D6; // LATIN CAPITAL LETTER O WITH DIAERESIS
    table[0xD7] = 0x00D7; // MULTIPLICATION SIGN
    table[0xD8] = 0x011C; // LATIN CAPITAL LETTER G WITH CIRCUMFLEX
    table[0xD9] = 0x00D9; // LATIN CAPITAL LETTER U WITH GRAVE
    table[0xDA] = 0x00DA; // LATIN CAPITAL LETTER U WITH ACUTE
    table[0xDB] = 0x00DB; // LATIN CAPITAL LETTER U WITH CIRCUMFLEX
    table[0xDC] = 0x00DC; // LATIN CAPITAL LETTER U WITH DIAERESIS
    table[0xDD] = 0x016C; // LATIN CAPITAL LETTER U WITH BREVE
    table[0xDE] = 0x015C; // LATIN CAPITAL LETTER S WITH CIRCUMFLEX
    table[0xDF] = 0x00DF; // LATIN SMALL LETTER SHARP S
    table[0xE0] = 0x00E0; // LATIN SMALL LETTER A WITH GRAVE
    table[0xE1] = 0x00E1; // LATIN SMALL LETTER A WITH ACUTE
    table[0xE2] = 0x00E2; // LATIN SMALL LETTER A WITH CIRCUMFLEX
    table[0xE3] = UNDEF;
    table[0xE4] = 0x00E4; // LATIN SMALL LETTER A WITH DIAERESIS
    table[0xE5] = 0x010B; // LATIN SMALL LETTER C WITH DOT ABOVE
    table[0xE6] = 0x0109; // LATIN SMALL LETTER C WITH CIRCUMFLEX
    table[0xE7] = 0x00E7; // LATIN SMALL LETTER C WITH CEDILLA
    table[0xE8] = 0x00E8; // LATIN SMALL LETTER E WITH GRAVE
    table[0xE9] = 0x00E9; // LATIN SMALL LETTER E WITH ACUTE
    table[0xEA] = 0x00EA; // LATIN SMALL LETTER E WITH CIRCUMFLEX
    table[0xEB] = 0x00EB; // LATIN SMALL LETTER E WITH DIAERESIS
    table[0xEC] = 0x00EC; // LATIN SMALL LETTER I WITH GRAVE
    table[0xED] = 0x00ED; // LATIN SMALL LETTER I WITH ACUTE
    table[0xEE] = 0x00EE; // LATIN SMALL LETTER I WITH CIRCUMFLEX
    table[0xEF] = 0x00EF; // LATIN SMALL LETTER I WITH DIAERESIS
    table[0xF0] = UNDEF;
    table[0xF1] = 0x00F1; // LATIN SMALL LETTER N WITH TILDE
    table[0xF2] = 0x00F2; // LATIN SMALL LETTER O WITH GRAVE
    table[0xF3] = 0x00F3; // LATIN SMALL LETTER O WITH ACUTE
    table[0xF4] = 0x00F4; // LATIN SMALL LETTER O WITH CIRCUMFLEX
    table[0xF5] = 0x0121; // LATIN SMALL LETTER G WITH DOT ABOVE
    table[0xF6] = 0x00F6; // LATIN SMALL LETTER O WITH DIAERESIS
    table[0xF7] = 0x00F7; // DIVISION SIGN
    table[0xF8] = 0x011D; // LATIN SMALL LETTER G WITH CIRCUMFLEX
    table[0xF9] = 0x00F9; // LATIN SMALL LETTER U WITH GRAVE
    table[0xFA] = 0x00FA; // LATIN SMALL LETTER U WITH ACUTE
    table[0xFB] = 0x00FB; // LATIN SMALL LETTER U WITH CIRCUMFLEX
    table[0xFC] = 0x00FC; // LATIN SMALL LETTER U WITH DIAERESIS
    table[0xFD] = 0x016D; // LATIN SMALL LETTER U WITH BREVE
    table[0xFE] = 0x015D; // LATIN SMALL LETTER S WITH CIRCUMFLEX
    table[0xFF] = 0x02D9; // DOT ABOVE
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "iso8859_3 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
