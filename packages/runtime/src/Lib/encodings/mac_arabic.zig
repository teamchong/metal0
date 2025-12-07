//! CPython source: Lib/encodings/mac_arabic.py
//!
//! Macintosh Arabic encoding
//!
//! Mirrors: CPython Lib/encodings/mac_arabic.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "mac-arabic";
pub const aliases = [_][]const u8{ "mac_arabic", "macarabic" };

const UNDEF = charmap.UNDEFINED;

/// Mac Arabic decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F
    table[0x80] = 0x00C4; // LATIN CAPITAL LETTER A WITH DIAERESIS
    table[0x81] = 0x00A0; // NO-BREAK SPACE
    table[0x82] = 0x00C7; // LATIN CAPITAL LETTER C WITH CEDILLA
    table[0x83] = 0x00C9; // LATIN CAPITAL LETTER E WITH ACUTE
    table[0x84] = 0x00D1; // LATIN CAPITAL LETTER N WITH TILDE
    table[0x85] = 0x00D6; // LATIN CAPITAL LETTER O WITH DIAERESIS
    table[0x86] = 0x00DC; // LATIN CAPITAL LETTER U WITH DIAERESIS
    table[0x87] = 0x00E1; // LATIN SMALL LETTER A WITH ACUTE
    table[0x88] = 0x00E0; // LATIN SMALL LETTER A WITH GRAVE
    table[0x89] = 0x00E2; // LATIN SMALL LETTER A WITH CIRCUMFLEX
    table[0x8A] = 0x00E4; // LATIN SMALL LETTER A WITH DIAERESIS
    table[0x8B] = 0x06BA; // ARABIC LETTER NOON GHUNNA
    table[0x8C] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0x8D] = 0x00E7; // LATIN SMALL LETTER C WITH CEDILLA
    table[0x8E] = 0x00E9; // LATIN SMALL LETTER E WITH ACUTE
    table[0x8F] = 0x00E8; // LATIN SMALL LETTER E WITH GRAVE
    table[0x90] = 0x00EA; // LATIN SMALL LETTER E WITH CIRCUMFLEX
    table[0x91] = 0x00EB; // LATIN SMALL LETTER E WITH DIAERESIS
    table[0x92] = 0x00ED; // LATIN SMALL LETTER I WITH ACUTE
    table[0x93] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0x94] = 0x00EE; // LATIN SMALL LETTER I WITH CIRCUMFLEX
    table[0x95] = 0x00EF; // LATIN SMALL LETTER I WITH DIAERESIS
    table[0x96] = 0x00F1; // LATIN SMALL LETTER N WITH TILDE
    table[0x97] = 0x00F3; // LATIN SMALL LETTER O WITH ACUTE
    table[0x98] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0x99] = 0x00F4; // LATIN SMALL LETTER O WITH CIRCUMFLEX
    table[0x9A] = 0x00F6; // LATIN SMALL LETTER O WITH DIAERESIS
    table[0x9B] = 0x00F7; // DIVISION SIGN
    table[0x9C] = 0x00FA; // LATIN SMALL LETTER U WITH ACUTE
    table[0x9D] = 0x00F9; // LATIN SMALL LETTER U WITH GRAVE
    table[0x9E] = 0x00FB; // LATIN SMALL LETTER U WITH CIRCUMFLEX
    table[0x9F] = 0x00FC; // LATIN SMALL LETTER U WITH DIAERESIS
    // 0xA0-0xCF: Various symbols and Arabic
    table[0xA0] = 0x0020; // SPACE
    table[0xA1] = 0x0021; // EXCLAMATION MARK
    table[0xA2] = 0x0022; // QUOTATION MARK
    table[0xA3] = 0x0023; // NUMBER SIGN
    table[0xA4] = 0x0024; // DOLLAR SIGN
    table[0xA5] = 0x066A; // ARABIC PERCENT SIGN
    table[0xA6] = 0x0026; // AMPERSAND
    table[0xA7] = 0x0027; // APOSTROPHE
    table[0xA8] = 0x0028; // LEFT PARENTHESIS
    table[0xA9] = 0x0029; // RIGHT PARENTHESIS
    table[0xAA] = 0x002A; // ASTERISK
    table[0xAB] = 0x002B; // PLUS SIGN
    table[0xAC] = 0x060C; // ARABIC COMMA
    table[0xAD] = 0x002D; // HYPHEN-MINUS
    table[0xAE] = 0x002E; // FULL STOP
    table[0xAF] = 0x002F; // SOLIDUS
    table[0xB0] = 0x0660; // ARABIC-INDIC DIGIT ZERO
    table[0xB1] = 0x0661; // ARABIC-INDIC DIGIT ONE
    table[0xB2] = 0x0662; // ARABIC-INDIC DIGIT TWO
    table[0xB3] = 0x0663; // ARABIC-INDIC DIGIT THREE
    table[0xB4] = 0x0664; // ARABIC-INDIC DIGIT FOUR
    table[0xB5] = 0x0665; // ARABIC-INDIC DIGIT FIVE
    table[0xB6] = 0x0666; // ARABIC-INDIC DIGIT SIX
    table[0xB7] = 0x0667; // ARABIC-INDIC DIGIT SEVEN
    table[0xB8] = 0x0668; // ARABIC-INDIC DIGIT EIGHT
    table[0xB9] = 0x0669; // ARABIC-INDIC DIGIT NINE
    table[0xBA] = 0x003A; // COLON
    table[0xBB] = 0x061B; // ARABIC SEMICOLON
    table[0xBC] = 0x003C; // LESS-THAN SIGN
    table[0xBD] = 0x003D; // EQUALS SIGN
    table[0xBE] = 0x003E; // GREATER-THAN SIGN
    table[0xBF] = 0x061F; // ARABIC QUESTION MARK
    // 0xC0-0xCF
    table[0xC0] = 0x274A; // EIGHT TEARDROP-SPOKED PROPELLER ASTERISK
    table[0xC1] = 0x0621; // ARABIC LETTER HAMZA
    table[0xC2] = 0x0622; // ARABIC LETTER ALEF WITH MADDA ABOVE
    table[0xC3] = 0x0623; // ARABIC LETTER ALEF WITH HAMZA ABOVE
    table[0xC4] = 0x0624; // ARABIC LETTER WAW WITH HAMZA ABOVE
    table[0xC5] = 0x0625; // ARABIC LETTER ALEF WITH HAMZA BELOW
    table[0xC6] = 0x0626; // ARABIC LETTER YEH WITH HAMZA ABOVE
    table[0xC7] = 0x0627; // ARABIC LETTER ALEF
    table[0xC8] = 0x0628; // ARABIC LETTER BEH
    table[0xC9] = 0x0629; // ARABIC LETTER TEH MARBUTA
    table[0xCA] = 0x062A; // ARABIC LETTER TEH
    table[0xCB] = 0x062B; // ARABIC LETTER THEH
    table[0xCC] = 0x062C; // ARABIC LETTER JEEM
    table[0xCD] = 0x062D; // ARABIC LETTER HAH
    table[0xCE] = 0x062E; // ARABIC LETTER KHAH
    table[0xCF] = 0x062F; // ARABIC LETTER DAL
    // 0xD0-0xDF
    table[0xD0] = 0x0630; // ARABIC LETTER THAL
    table[0xD1] = 0x0631; // ARABIC LETTER REH
    table[0xD2] = 0x0632; // ARABIC LETTER ZAIN
    table[0xD3] = 0x0633; // ARABIC LETTER SEEN
    table[0xD4] = 0x0634; // ARABIC LETTER SHEEN
    table[0xD5] = 0x0635; // ARABIC LETTER SAD
    table[0xD6] = 0x0636; // ARABIC LETTER DAD
    table[0xD7] = 0x0637; // ARABIC LETTER TAH
    table[0xD8] = 0x0638; // ARABIC LETTER ZAH
    table[0xD9] = 0x0639; // ARABIC LETTER AIN
    table[0xDA] = 0x063A; // ARABIC LETTER GHAIN
    table[0xDB] = 0x005B; // LEFT SQUARE BRACKET
    table[0xDC] = 0x005C; // REVERSE SOLIDUS
    table[0xDD] = 0x005D; // RIGHT SQUARE BRACKET
    table[0xDE] = 0x005E; // CIRCUMFLEX ACCENT
    table[0xDF] = 0x005F; // LOW LINE
    // 0xE0-0xFF
    table[0xE0] = 0x0640; // ARABIC TATWEEL
    table[0xE1] = 0x0641; // ARABIC LETTER FEH
    table[0xE2] = 0x0642; // ARABIC LETTER QAF
    table[0xE3] = 0x0643; // ARABIC LETTER KAF
    table[0xE4] = 0x0644; // ARABIC LETTER LAM
    table[0xE5] = 0x0645; // ARABIC LETTER MEEM
    table[0xE6] = 0x0646; // ARABIC LETTER NOON
    table[0xE7] = 0x0647; // ARABIC LETTER HEH
    table[0xE8] = 0x0648; // ARABIC LETTER WAW
    table[0xE9] = 0x0649; // ARABIC LETTER ALEF MAKSURA
    table[0xEA] = 0x064A; // ARABIC LETTER YEH
    table[0xEB] = 0x064B; // ARABIC FATHATAN
    table[0xEC] = 0x064C; // ARABIC DAMMATAN
    table[0xED] = 0x064D; // ARABIC KASRATAN
    table[0xEE] = 0x064E; // ARABIC FATHA
    table[0xEF] = 0x064F; // ARABIC DAMMA
    table[0xF0] = 0x0650; // ARABIC KASRA
    table[0xF1] = 0x0651; // ARABIC SHADDA
    table[0xF2] = 0x0652; // ARABIC SUKUN
    table[0xF3] = 0x067E; // ARABIC LETTER PEH
    table[0xF4] = 0x0679; // ARABIC LETTER TTEH
    table[0xF5] = 0x0686; // ARABIC LETTER TCHEH
    table[0xF6] = 0x06D5; // ARABIC LETTER AE
    table[0xF7] = 0x06A4; // ARABIC LETTER VEH
    table[0xF8] = 0x06AF; // ARABIC LETTER GAF
    table[0xF9] = 0x0688; // ARABIC LETTER DDAL
    table[0xFA] = 0x0691; // ARABIC LETTER RREH
    table[0xFB] = 0x007B; // LEFT CURLY BRACKET
    table[0xFC] = 0x007C; // VERTICAL LINE
    table[0xFD] = 0x007D; // RIGHT CURLY BRACKET
    table[0xFE] = 0x0698; // ARABIC LETTER JEH
    table[0xFF] = 0x06D2; // ARABIC LETTER YEH BARREE
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "mac_arabic decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
