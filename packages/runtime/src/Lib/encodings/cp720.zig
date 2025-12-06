//! Python 'cp720' Codec (DOS Arabic)
//!
//! DOS Arabic codepage (transparent ASMO)
//!
//! Mirrors: CPython Lib/encodings/cp720.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp720";
pub const aliases = [_][]const u8{};

const UNDEF = charmap.UNDEFINED;

/// CP720 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F
    table[0x80] = UNDEF;
    table[0x81] = UNDEF;
    table[0x82] = 0x00E9; // LATIN SMALL LETTER E WITH ACUTE
    table[0x83] = 0x00E2; // LATIN SMALL LETTER A WITH CIRCUMFLEX
    table[0x84] = UNDEF;
    table[0x85] = 0x00E0; // LATIN SMALL LETTER A WITH GRAVE
    table[0x86] = UNDEF;
    table[0x87] = 0x00E7; // LATIN SMALL LETTER C WITH CEDILLA
    table[0x88] = 0x00EA; // LATIN SMALL LETTER E WITH CIRCUMFLEX
    table[0x89] = 0x00EB; // LATIN SMALL LETTER E WITH DIAERESIS
    table[0x8A] = 0x00E8; // LATIN SMALL LETTER E WITH GRAVE
    table[0x8B] = 0x00EF; // LATIN SMALL LETTER I WITH DIAERESIS
    table[0x8C] = 0x00EE; // LATIN SMALL LETTER I WITH CIRCUMFLEX
    table[0x8D] = UNDEF;
    table[0x8E] = UNDEF;
    table[0x8F] = UNDEF;
    table[0x90] = UNDEF;
    table[0x91] = 0x0651; // ARABIC SHADDA
    table[0x92] = 0x0652; // ARABIC SUKUN
    table[0x93] = 0x00F4; // LATIN SMALL LETTER O WITH CIRCUMFLEX
    table[0x94] = 0x00A4; // CURRENCY SIGN
    table[0x95] = 0x0640; // ARABIC TATWEEL
    table[0x96] = 0x00FB; // LATIN SMALL LETTER U WITH CIRCUMFLEX
    table[0x97] = 0x00F9; // LATIN SMALL LETTER U WITH GRAVE
    table[0x98] = 0x0621; // ARABIC LETTER HAMZA
    table[0x99] = 0x0622; // ARABIC LETTER ALEF WITH MADDA ABOVE
    table[0x9A] = 0x0623; // ARABIC LETTER ALEF WITH HAMZA ABOVE
    table[0x9B] = 0x0624; // ARABIC LETTER WAW WITH HAMZA ABOVE
    table[0x9C] = 0x00A3; // POUND SIGN
    table[0x9D] = 0x0625; // ARABIC LETTER ALEF WITH HAMZA BELOW
    table[0x9E] = 0x0626; // ARABIC LETTER YEH WITH HAMZA ABOVE
    table[0x9F] = 0x0627; // ARABIC LETTER ALEF
    // 0xA0-0xAF
    table[0xA0] = 0x0628; // ARABIC LETTER BEH
    table[0xA1] = 0x0629; // ARABIC LETTER TEH MARBUTA
    table[0xA2] = 0x062A; // ARABIC LETTER TEH
    table[0xA3] = 0x062B; // ARABIC LETTER THEH
    table[0xA4] = 0x062C; // ARABIC LETTER JEEM
    table[0xA5] = 0x062D; // ARABIC LETTER HAH
    table[0xA6] = 0x062E; // ARABIC LETTER KHAH
    table[0xA7] = 0x062F; // ARABIC LETTER DAL
    table[0xA8] = 0x0630; // ARABIC LETTER THAL
    table[0xA9] = 0x0631; // ARABIC LETTER REH
    table[0xAA] = 0x0632; // ARABIC LETTER ZAIN
    table[0xAB] = 0x0633; // ARABIC LETTER SEEN
    table[0xAC] = 0x0634; // ARABIC LETTER SHEEN
    table[0xAD] = 0x0635; // ARABIC LETTER SAD
    table[0xAE] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xAF] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    // 0xB0-0xDF: Box drawing and more Arabic
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
    // 0xE0-0xFF: More Arabic
    table[0xE0] = 0x0636; // ARABIC LETTER DAD
    table[0xE1] = 0x0637; // ARABIC LETTER TAH
    table[0xE2] = 0x0638; // ARABIC LETTER ZAH
    table[0xE3] = 0x0639; // ARABIC LETTER AIN
    table[0xE4] = 0x063A; // ARABIC LETTER GHAIN
    table[0xE5] = 0x0641; // ARABIC LETTER FEH
    table[0xE6] = 0x00B5; // MICRO SIGN
    table[0xE7] = 0x0642; // ARABIC LETTER QAF
    table[0xE8] = 0x0643; // ARABIC LETTER KAF
    table[0xE9] = 0x0644; // ARABIC LETTER LAM
    table[0xEA] = 0x0645; // ARABIC LETTER MEEM
    table[0xEB] = 0x0646; // ARABIC LETTER NOON
    table[0xEC] = 0x0647; // ARABIC LETTER HEH
    table[0xED] = 0x0648; // ARABIC LETTER WAW
    table[0xEE] = 0x0649; // ARABIC LETTER ALEF MAKSURA
    table[0xEF] = 0x064A; // ARABIC LETTER YEH
    table[0xF0] = 0x2261; // IDENTICAL TO
    table[0xF1] = 0x064B; // ARABIC FATHATAN
    table[0xF2] = 0x064C; // ARABIC DAMMATAN
    table[0xF3] = 0x064D; // ARABIC KASRATAN
    table[0xF4] = 0x064E; // ARABIC FATHA
    table[0xF5] = 0x064F; // ARABIC DAMMA
    table[0xF6] = 0x0650; // ARABIC KASRA
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

test "cp720 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
