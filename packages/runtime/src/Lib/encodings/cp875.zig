//! CPython source: Lib/encodings/cp875.py
//!
//! IBM EBCDIC Greek encoding
//!
//! Mirrors: CPython Lib/encodings/cp875.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp875";
pub const aliases = [_][]const u8{ "ibm875", "875", "csibm875" };

/// CP875 decode table - EBCDIC Greek to Unicode
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // EBCDIC encoding - control characters
    table[0x00] = 0x0000; // NULL
    table[0x01] = 0x0001; // START OF HEADING
    table[0x02] = 0x0002; // START OF TEXT
    table[0x03] = 0x0003; // END OF TEXT
    table[0x04] = 0x009C; // CONTROL
    table[0x05] = 0x0009; // HORIZONTAL TABULATION
    table[0x06] = 0x0086; // CONTROL
    table[0x07] = 0x007F; // DELETE
    table[0x08] = 0x0097; // CONTROL
    table[0x09] = 0x008D; // CONTROL
    table[0x0A] = 0x008E; // CONTROL
    table[0x0B] = 0x000B; // VERTICAL TABULATION
    table[0x0C] = 0x000C; // FORM FEED
    table[0x0D] = 0x000D; // CARRIAGE RETURN
    table[0x0E] = 0x000E; // SHIFT OUT
    table[0x0F] = 0x000F; // SHIFT IN
    table[0x10] = 0x0010; // DATA LINK ESCAPE
    table[0x11] = 0x0011; // DEVICE CONTROL ONE
    table[0x12] = 0x0012; // DEVICE CONTROL TWO
    table[0x13] = 0x0013; // DEVICE CONTROL THREE
    table[0x14] = 0x009D; // CONTROL
    table[0x15] = 0x0085; // CONTROL
    table[0x16] = 0x0008; // BACKSPACE
    table[0x17] = 0x0087; // CONTROL
    table[0x18] = 0x0018; // CANCEL
    table[0x19] = 0x0019; // END OF MEDIUM
    table[0x1A] = 0x0092; // CONTROL
    table[0x1B] = 0x008F; // CONTROL
    table[0x1C] = 0x001C; // FILE SEPARATOR
    table[0x1D] = 0x001D; // GROUP SEPARATOR
    table[0x1E] = 0x001E; // RECORD SEPARATOR
    table[0x1F] = 0x001F; // UNIT SEPARATOR
    table[0x20] = 0x0080; // CONTROL
    table[0x21] = 0x0081; // CONTROL
    table[0x22] = 0x0082; // CONTROL
    table[0x23] = 0x0083; // CONTROL
    table[0x24] = 0x0084; // CONTROL
    table[0x25] = 0x000A; // LINE FEED
    table[0x26] = 0x0017; // END OF TRANSMISSION BLOCK
    table[0x27] = 0x001B; // ESCAPE
    table[0x28] = 0x0088; // CONTROL
    table[0x29] = 0x0089; // CONTROL
    table[0x2A] = 0x008A; // CONTROL
    table[0x2B] = 0x008B; // CONTROL
    table[0x2C] = 0x008C; // CONTROL
    table[0x2D] = 0x0005; // ENQUIRY
    table[0x2E] = 0x0006; // ACKNOWLEDGE
    table[0x2F] = 0x0007; // BELL
    table[0x30] = 0x0090; // CONTROL
    table[0x31] = 0x0091; // CONTROL
    table[0x32] = 0x0016; // SYNCHRONOUS IDLE
    table[0x33] = 0x0093; // CONTROL
    table[0x34] = 0x0094; // CONTROL
    table[0x35] = 0x0095; // CONTROL
    table[0x36] = 0x0096; // CONTROL
    table[0x37] = 0x0004; // END OF TRANSMISSION
    table[0x38] = 0x0098; // CONTROL
    table[0x39] = 0x0099; // CONTROL
    table[0x3A] = 0x009A; // CONTROL
    table[0x3B] = 0x009B; // CONTROL
    table[0x3C] = 0x0014; // DEVICE CONTROL FOUR
    table[0x3D] = 0x0015; // NEGATIVE ACKNOWLEDGE
    table[0x3E] = 0x009E; // CONTROL
    table[0x3F] = 0x001A; // SUBSTITUTE
    // 0x40-0x4F: Space and Greek capitals
    table[0x40] = 0x0020; // SPACE
    table[0x41] = 0x0391; // GREEK CAPITAL LETTER ALPHA
    table[0x42] = 0x0392; // GREEK CAPITAL LETTER BETA
    table[0x43] = 0x0393; // GREEK CAPITAL LETTER GAMMA
    table[0x44] = 0x0394; // GREEK CAPITAL LETTER DELTA
    table[0x45] = 0x0395; // GREEK CAPITAL LETTER EPSILON
    table[0x46] = 0x0396; // GREEK CAPITAL LETTER ZETA
    table[0x47] = 0x0397; // GREEK CAPITAL LETTER ETA
    table[0x48] = 0x0398; // GREEK CAPITAL LETTER THETA
    table[0x49] = 0x0399; // GREEK CAPITAL LETTER IOTA
    table[0x4A] = 0x005B; // LEFT SQUARE BRACKET
    table[0x4B] = 0x002E; // FULL STOP
    table[0x4C] = 0x003C; // LESS-THAN SIGN
    table[0x4D] = 0x0028; // LEFT PARENTHESIS
    table[0x4E] = 0x002B; // PLUS SIGN
    table[0x4F] = 0x0021; // EXCLAMATION MARK
    // 0x50-0x5F: Ampersand and Greek capitals continued
    table[0x50] = 0x0026; // AMPERSAND
    table[0x51] = 0x039A; // GREEK CAPITAL LETTER KAPPA
    table[0x52] = 0x039B; // GREEK CAPITAL LETTER LAMDA
    table[0x53] = 0x039C; // GREEK CAPITAL LETTER MU
    table[0x54] = 0x039D; // GREEK CAPITAL LETTER NU
    table[0x55] = 0x039E; // GREEK CAPITAL LETTER XI
    table[0x56] = 0x039F; // GREEK CAPITAL LETTER OMICRON
    table[0x57] = 0x03A0; // GREEK CAPITAL LETTER PI
    table[0x58] = 0x03A1; // GREEK CAPITAL LETTER RHO
    table[0x59] = 0x03A3; // GREEK CAPITAL LETTER SIGMA
    table[0x5A] = 0x005D; // RIGHT SQUARE BRACKET
    table[0x5B] = 0x0024; // DOLLAR SIGN
    table[0x5C] = 0x002A; // ASTERISK
    table[0x5D] = 0x0029; // RIGHT PARENTHESIS
    table[0x5E] = 0x003B; // SEMICOLON
    table[0x5F] = 0x005E; // CIRCUMFLEX ACCENT
    // 0x60-0x6F: Hyphen and Greek capitals continued
    table[0x60] = 0x002D; // HYPHEN-MINUS
    table[0x61] = 0x002F; // SOLIDUS
    table[0x62] = 0x03A4; // GREEK CAPITAL LETTER TAU
    table[0x63] = 0x03A5; // GREEK CAPITAL LETTER UPSILON
    table[0x64] = 0x03A6; // GREEK CAPITAL LETTER PHI
    table[0x65] = 0x03A7; // GREEK CAPITAL LETTER CHI
    table[0x66] = 0x03A8; // GREEK CAPITAL LETTER PSI
    table[0x67] = 0x03A9; // GREEK CAPITAL LETTER OMEGA
    table[0x68] = 0x03AA; // GREEK CAPITAL LETTER IOTA WITH DIALYTIKA
    table[0x69] = 0x03AB; // GREEK CAPITAL LETTER UPSILON WITH DIALYTIKA
    table[0x6A] = 0x007C; // VERTICAL LINE
    table[0x6B] = 0x002C; // COMMA
    table[0x6C] = 0x0025; // PERCENT SIGN
    table[0x6D] = 0x005F; // LOW LINE
    table[0x6E] = 0x003E; // GREATER-THAN SIGN
    table[0x6F] = 0x003F; // QUESTION MARK
    // 0x70-0x7F: Diacritic and accent marks
    table[0x70] = 0x00A8; // DIAERESIS
    table[0x71] = 0x0386; // GREEK CAPITAL LETTER ALPHA WITH TONOS
    table[0x72] = 0x0388; // GREEK CAPITAL LETTER EPSILON WITH TONOS
    table[0x73] = 0x0389; // GREEK CAPITAL LETTER ETA WITH TONOS
    table[0x74] = 0x00A0; // NO-BREAK SPACE
    table[0x75] = 0x038A; // GREEK CAPITAL LETTER IOTA WITH TONOS
    table[0x76] = 0x038C; // GREEK CAPITAL LETTER OMICRON WITH TONOS
    table[0x77] = 0x038E; // GREEK CAPITAL LETTER UPSILON WITH TONOS
    table[0x78] = 0x038F; // GREEK CAPITAL LETTER OMEGA WITH TONOS
    table[0x79] = 0x0060; // GRAVE ACCENT
    table[0x7A] = 0x003A; // COLON
    table[0x7B] = 0x0023; // NUMBER SIGN
    table[0x7C] = 0x0040; // COMMERCIAL AT
    table[0x7D] = 0x0027; // APOSTROPHE
    table[0x7E] = 0x003D; // EQUALS SIGN
    table[0x7F] = 0x0022; // QUOTATION MARK
    // 0x80-0x8F: Dialytika tonos and Latin small letters + Greek small
    table[0x80] = 0x0385; // GREEK DIALYTIKA TONOS
    table[0x81] = 0x0061; // LATIN SMALL LETTER A
    table[0x82] = 0x0062; // LATIN SMALL LETTER B
    table[0x83] = 0x0063; // LATIN SMALL LETTER C
    table[0x84] = 0x0064; // LATIN SMALL LETTER D
    table[0x85] = 0x0065; // LATIN SMALL LETTER E
    table[0x86] = 0x0066; // LATIN SMALL LETTER F
    table[0x87] = 0x0067; // LATIN SMALL LETTER G
    table[0x88] = 0x0068; // LATIN SMALL LETTER H
    table[0x89] = 0x0069; // LATIN SMALL LETTER I
    table[0x8A] = 0x03B1; // GREEK SMALL LETTER ALPHA
    table[0x8B] = 0x03B2; // GREEK SMALL LETTER BETA
    table[0x8C] = 0x03B3; // GREEK SMALL LETTER GAMMA
    table[0x8D] = 0x03B4; // GREEK SMALL LETTER DELTA
    table[0x8E] = 0x03B5; // GREEK SMALL LETTER EPSILON
    table[0x8F] = 0x03B6; // GREEK SMALL LETTER ZETA
    // 0x90-0x9F: Degree sign, Latin small letters, Greek small letters
    table[0x90] = 0x00B0; // DEGREE SIGN
    table[0x91] = 0x006A; // LATIN SMALL LETTER J
    table[0x92] = 0x006B; // LATIN SMALL LETTER K
    table[0x93] = 0x006C; // LATIN SMALL LETTER L
    table[0x94] = 0x006D; // LATIN SMALL LETTER M
    table[0x95] = 0x006E; // LATIN SMALL LETTER N
    table[0x96] = 0x006F; // LATIN SMALL LETTER O
    table[0x97] = 0x0070; // LATIN SMALL LETTER P
    table[0x98] = 0x0071; // LATIN SMALL LETTER Q
    table[0x99] = 0x0072; // LATIN SMALL LETTER R
    table[0x9A] = 0x03B7; // GREEK SMALL LETTER ETA
    table[0x9B] = 0x03B8; // GREEK SMALL LETTER THETA
    table[0x9C] = 0x03B9; // GREEK SMALL LETTER IOTA
    table[0x9D] = 0x03BA; // GREEK SMALL LETTER KAPPA
    table[0x9E] = 0x03BB; // GREEK SMALL LETTER LAMDA
    table[0x9F] = 0x03BC; // GREEK SMALL LETTER MU
    // 0xA0-0xAF: Acute accent, tilde, Latin small letters, Greek small letters
    table[0xA0] = 0x00B4; // ACUTE ACCENT
    table[0xA1] = 0x007E; // TILDE
    table[0xA2] = 0x0073; // LATIN SMALL LETTER S
    table[0xA3] = 0x0074; // LATIN SMALL LETTER T
    table[0xA4] = 0x0075; // LATIN SMALL LETTER U
    table[0xA5] = 0x0076; // LATIN SMALL LETTER V
    table[0xA6] = 0x0077; // LATIN SMALL LETTER W
    table[0xA7] = 0x0078; // LATIN SMALL LETTER X
    table[0xA8] = 0x0079; // LATIN SMALL LETTER Y
    table[0xA9] = 0x007A; // LATIN SMALL LETTER Z
    table[0xAA] = 0x03BD; // GREEK SMALL LETTER NU
    table[0xAB] = 0x03BE; // GREEK SMALL LETTER XI
    table[0xAC] = 0x03BF; // GREEK SMALL LETTER OMICRON
    table[0xAD] = 0x03C0; // GREEK SMALL LETTER PI
    table[0xAE] = 0x03C1; // GREEK SMALL LETTER RHO
    table[0xAF] = 0x03C3; // GREEK SMALL LETTER SIGMA
    // 0xB0-0xBF: Pound sign, Greek small letters with accents
    table[0xB0] = 0x00A3; // POUND SIGN
    table[0xB1] = 0x03AC; // GREEK SMALL LETTER ALPHA WITH TONOS
    table[0xB2] = 0x03AD; // GREEK SMALL LETTER EPSILON WITH TONOS
    table[0xB3] = 0x03AE; // GREEK SMALL LETTER ETA WITH TONOS
    table[0xB4] = 0x03CA; // GREEK SMALL LETTER IOTA WITH DIALYTIKA
    table[0xB5] = 0x03AF; // GREEK SMALL LETTER IOTA WITH TONOS
    table[0xB6] = 0x03CC; // GREEK SMALL LETTER OMICRON WITH TONOS
    table[0xB7] = 0x03CD; // GREEK SMALL LETTER UPSILON WITH TONOS
    table[0xB8] = 0x03CB; // GREEK SMALL LETTER UPSILON WITH DIALYTIKA
    table[0xB9] = 0x03CE; // GREEK SMALL LETTER OMEGA WITH TONOS
    table[0xBA] = 0x03C2; // GREEK SMALL LETTER FINAL SIGMA
    table[0xBB] = 0x03C4; // GREEK SMALL LETTER TAU
    table[0xBC] = 0x03C5; // GREEK SMALL LETTER UPSILON
    table[0xBD] = 0x03C6; // GREEK SMALL LETTER PHI
    table[0xBE] = 0x03C7; // GREEK SMALL LETTER CHI
    table[0xBF] = 0x03C8; // GREEK SMALL LETTER PSI
    // 0xC0-0xCF: Left curly bracket, Latin capitals A-I, Greek small letters
    table[0xC0] = 0x007B; // LEFT CURLY BRACKET
    table[0xC1] = 0x0041; // LATIN CAPITAL LETTER A
    table[0xC2] = 0x0042; // LATIN CAPITAL LETTER B
    table[0xC3] = 0x0043; // LATIN CAPITAL LETTER C
    table[0xC4] = 0x0044; // LATIN CAPITAL LETTER D
    table[0xC5] = 0x0045; // LATIN CAPITAL LETTER E
    table[0xC6] = 0x0046; // LATIN CAPITAL LETTER F
    table[0xC7] = 0x0047; // LATIN CAPITAL LETTER G
    table[0xC8] = 0x0048; // LATIN CAPITAL LETTER H
    table[0xC9] = 0x0049; // LATIN CAPITAL LETTER I
    table[0xCA] = 0x00AD; // SOFT HYPHEN
    table[0xCB] = 0x03C9; // GREEK SMALL LETTER OMEGA
    table[0xCC] = 0x0390; // GREEK SMALL LETTER IOTA WITH DIALYTIKA AND TONOS
    table[0xCD] = 0x03B0; // GREEK SMALL LETTER UPSILON WITH DIALYTIKA AND TONOS
    table[0xCE] = 0x2018; // LEFT SINGLE QUOTATION MARK
    table[0xCF] = 0x2015; // HORIZONTAL BAR
    // 0xD0-0xDF: Right curly bracket, Latin capitals J-R, symbols
    table[0xD0] = 0x007D; // RIGHT CURLY BRACKET
    table[0xD1] = 0x004A; // LATIN CAPITAL LETTER J
    table[0xD2] = 0x004B; // LATIN CAPITAL LETTER K
    table[0xD3] = 0x004C; // LATIN CAPITAL LETTER L
    table[0xD4] = 0x004D; // LATIN CAPITAL LETTER M
    table[0xD5] = 0x004E; // LATIN CAPITAL LETTER N
    table[0xD6] = 0x004F; // LATIN CAPITAL LETTER O
    table[0xD7] = 0x0050; // LATIN CAPITAL LETTER P
    table[0xD8] = 0x0051; // LATIN CAPITAL LETTER Q
    table[0xD9] = 0x0052; // LATIN CAPITAL LETTER R
    table[0xDA] = 0x00B1; // PLUS-MINUS SIGN
    table[0xDB] = 0x00BD; // VULGAR FRACTION ONE HALF
    table[0xDC] = 0x001A; // SUBSTITUTE
    table[0xDD] = 0x0387; // GREEK ANO TELEIA
    table[0xDE] = 0x2019; // RIGHT SINGLE QUOTATION MARK
    table[0xDF] = 0x00A6; // BROKEN BAR
    // 0xE0-0xEF: Backslash, Latin capitals S-Z, symbols
    table[0xE0] = 0x005C; // REVERSE SOLIDUS
    table[0xE1] = 0x001A; // SUBSTITUTE
    table[0xE2] = 0x0053; // LATIN CAPITAL LETTER S
    table[0xE3] = 0x0054; // LATIN CAPITAL LETTER T
    table[0xE4] = 0x0055; // LATIN CAPITAL LETTER U
    table[0xE5] = 0x0056; // LATIN CAPITAL LETTER V
    table[0xE6] = 0x0057; // LATIN CAPITAL LETTER W
    table[0xE7] = 0x0058; // LATIN CAPITAL LETTER X
    table[0xE8] = 0x0059; // LATIN CAPITAL LETTER Y
    table[0xE9] = 0x005A; // LATIN CAPITAL LETTER Z
    table[0xEA] = 0x00B2; // SUPERSCRIPT TWO
    table[0xEB] = 0x00A7; // SECTION SIGN
    table[0xEC] = 0x001A; // SUBSTITUTE
    table[0xED] = 0x001A; // SUBSTITUTE
    table[0xEE] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xEF] = 0x00AC; // NOT SIGN
    // 0xF0-0xFF: Digits and symbols
    table[0xF0] = 0x0030; // DIGIT ZERO
    table[0xF1] = 0x0031; // DIGIT ONE
    table[0xF2] = 0x0032; // DIGIT TWO
    table[0xF3] = 0x0033; // DIGIT THREE
    table[0xF4] = 0x0034; // DIGIT FOUR
    table[0xF5] = 0x0035; // DIGIT FIVE
    table[0xF6] = 0x0036; // DIGIT SIX
    table[0xF7] = 0x0037; // DIGIT SEVEN
    table[0xF8] = 0x0038; // DIGIT EIGHT
    table[0xF9] = 0x0039; // DIGIT NINE
    table[0xFA] = 0x00B3; // SUPERSCRIPT THREE
    table[0xFB] = 0x00A9; // COPYRIGHT SIGN
    table[0xFC] = 0x001A; // SUBSTITUTE
    table[0xFD] = 0x001A; // SUBSTITUTE
    table[0xFE] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xFF] = 0x009F; // CONTROL
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "cp875 decode" {
    // EBCDIC 'A' is 0xC1, decodes to 0x0041 (Latin 'A')
    const result = try decode(std.testing.allocator, &[_]u8{0xC1}, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("A", result.output);
}

test "cp875 decode greek alpha" {
    // 0x41 decodes to Greek capital letter Alpha (0x0391)
    const result = try decode(std.testing.allocator, &[_]u8{0x41}, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xCE\x91", result.output); // UTF-8 for U+0391
}
