//! CPython source: Lib/encodings/iso8859_6.py
//!
//! Arabic alphabet
//!
//! Mirrors: CPython Lib/encodings/iso8859_6.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "iso8859-6";
pub const aliases = [_][]const u8{ "iso-8859-6", "arabic", "asmo-708", "iso_8859_6" };

const UNDEF = charmap.UNDEFINED;

/// ISO-8859-6 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x9F same as Latin-1
    for (0..0xA0) |i| table[i] = @intCast(i);
    // 0xA0-0xFF
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = UNDEF;
    table[0xA2] = UNDEF;
    table[0xA3] = UNDEF;
    table[0xA4] = 0x00A4; // CURRENCY SIGN
    table[0xA5] = UNDEF;
    table[0xA6] = UNDEF;
    table[0xA7] = UNDEF;
    table[0xA8] = UNDEF;
    table[0xA9] = UNDEF;
    table[0xAA] = UNDEF;
    table[0xAB] = UNDEF;
    table[0xAC] = 0x060C; // ARABIC COMMA
    table[0xAD] = 0x00AD; // SOFT HYPHEN
    table[0xAE] = UNDEF;
    table[0xAF] = UNDEF;
    table[0xB0] = UNDEF;
    table[0xB1] = UNDEF;
    table[0xB2] = UNDEF;
    table[0xB3] = UNDEF;
    table[0xB4] = UNDEF;
    table[0xB5] = UNDEF;
    table[0xB6] = UNDEF;
    table[0xB7] = UNDEF;
    table[0xB8] = UNDEF;
    table[0xB9] = UNDEF;
    table[0xBA] = UNDEF;
    table[0xBB] = 0x061B; // ARABIC SEMICOLON
    table[0xBC] = UNDEF;
    table[0xBD] = UNDEF;
    table[0xBE] = UNDEF;
    table[0xBF] = 0x061F; // ARABIC QUESTION MARK
    table[0xC0] = UNDEF;
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
    table[0xDB] = UNDEF;
    table[0xDC] = UNDEF;
    table[0xDD] = UNDEF;
    table[0xDE] = UNDEF;
    table[0xDF] = UNDEF;
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
    table[0xF3] = UNDEF;
    table[0xF4] = UNDEF;
    table[0xF5] = UNDEF;
    table[0xF6] = UNDEF;
    table[0xF7] = UNDEF;
    table[0xF8] = UNDEF;
    table[0xF9] = UNDEF;
    table[0xFA] = UNDEF;
    table[0xFB] = UNDEF;
    table[0xFC] = UNDEF;
    table[0xFD] = UNDEF;
    table[0xFE] = UNDEF;
    table[0xFF] = UNDEF;
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "iso8859_6 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
