//! Python 'mac_cyrillic' Codec (Macintosh Cyrillic)
//!
//! Macintosh Cyrillic encoding
//!
//! Mirrors: CPython Lib/encodings/mac_cyrillic.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "mac-cyrillic";
pub const aliases = [_][]const u8{ "mac_cyrillic", "maccyrillic" };

const UNDEF = charmap.UNDEFINED;

/// Mac Cyrillic decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F: Cyrillic capital letters
    table[0x80] = 0x0410; // CYRILLIC CAPITAL LETTER A
    table[0x81] = 0x0411; // CYRILLIC CAPITAL LETTER BE
    table[0x82] = 0x0412; // CYRILLIC CAPITAL LETTER VE
    table[0x83] = 0x0413; // CYRILLIC CAPITAL LETTER GHE
    table[0x84] = 0x0414; // CYRILLIC CAPITAL LETTER DE
    table[0x85] = 0x0415; // CYRILLIC CAPITAL LETTER IE
    table[0x86] = 0x0416; // CYRILLIC CAPITAL LETTER ZHE
    table[0x87] = 0x0417; // CYRILLIC CAPITAL LETTER ZE
    table[0x88] = 0x0418; // CYRILLIC CAPITAL LETTER I
    table[0x89] = 0x0419; // CYRILLIC CAPITAL LETTER SHORT I
    table[0x8A] = 0x041A; // CYRILLIC CAPITAL LETTER KA
    table[0x8B] = 0x041B; // CYRILLIC CAPITAL LETTER EL
    table[0x8C] = 0x041C; // CYRILLIC CAPITAL LETTER EM
    table[0x8D] = 0x041D; // CYRILLIC CAPITAL LETTER EN
    table[0x8E] = 0x041E; // CYRILLIC CAPITAL LETTER O
    table[0x8F] = 0x041F; // CYRILLIC CAPITAL LETTER PE
    table[0x90] = 0x0420; // CYRILLIC CAPITAL LETTER ER
    table[0x91] = 0x0421; // CYRILLIC CAPITAL LETTER ES
    table[0x92] = 0x0422; // CYRILLIC CAPITAL LETTER TE
    table[0x93] = 0x0423; // CYRILLIC CAPITAL LETTER U
    table[0x94] = 0x0424; // CYRILLIC CAPITAL LETTER EF
    table[0x95] = 0x0425; // CYRILLIC CAPITAL LETTER HA
    table[0x96] = 0x0426; // CYRILLIC CAPITAL LETTER TSE
    table[0x97] = 0x0427; // CYRILLIC CAPITAL LETTER CHE
    table[0x98] = 0x0428; // CYRILLIC CAPITAL LETTER SHA
    table[0x99] = 0x0429; // CYRILLIC CAPITAL LETTER SHCHA
    table[0x9A] = 0x042A; // CYRILLIC CAPITAL LETTER HARD SIGN
    table[0x9B] = 0x042B; // CYRILLIC CAPITAL LETTER YERU
    table[0x9C] = 0x042C; // CYRILLIC CAPITAL LETTER SOFT SIGN
    table[0x9D] = 0x042D; // CYRILLIC CAPITAL LETTER E
    table[0x9E] = 0x042E; // CYRILLIC CAPITAL LETTER YU
    table[0x9F] = 0x042F; // CYRILLIC CAPITAL LETTER YA
    // 0xA0-0xAF
    table[0xA0] = 0x2020; // DAGGER
    table[0xA1] = 0x00B0; // DEGREE SIGN
    table[0xA2] = 0x0490; // CYRILLIC CAPITAL LETTER GHE WITH UPTURN
    table[0xA3] = 0x00A3; // POUND SIGN
    table[0xA4] = 0x00A7; // SECTION SIGN
    table[0xA5] = 0x2022; // BULLET
    table[0xA6] = 0x00B6; // PILCROW SIGN
    table[0xA7] = 0x0406; // CYRILLIC CAPITAL LETTER BYELORUSSIAN-UKRAINIAN I
    table[0xA8] = 0x00AE; // REGISTERED SIGN
    table[0xA9] = 0x00A9; // COPYRIGHT SIGN
    table[0xAA] = 0x2122; // TRADE MARK SIGN
    table[0xAB] = 0x0402; // CYRILLIC CAPITAL LETTER DJE
    table[0xAC] = 0x0452; // CYRILLIC SMALL LETTER DJE
    table[0xAD] = 0x2260; // NOT EQUAL TO
    table[0xAE] = 0x0403; // CYRILLIC CAPITAL LETTER GJE
    table[0xAF] = 0x0453; // CYRILLIC SMALL LETTER GJE
    // 0xB0-0xBF
    table[0xB0] = 0x221E; // INFINITY
    table[0xB1] = 0x00B1; // PLUS-MINUS SIGN
    table[0xB2] = 0x2264; // LESS-THAN OR EQUAL TO
    table[0xB3] = 0x2265; // GREATER-THAN OR EQUAL TO
    table[0xB4] = 0x0456; // CYRILLIC SMALL LETTER BYELORUSSIAN-UKRAINIAN I
    table[0xB5] = 0x00B5; // MICRO SIGN
    table[0xB6] = 0x0491; // CYRILLIC SMALL LETTER GHE WITH UPTURN
    table[0xB7] = 0x0408; // CYRILLIC CAPITAL LETTER JE
    table[0xB8] = 0x0404; // CYRILLIC CAPITAL LETTER UKRAINIAN IE
    table[0xB9] = 0x0454; // CYRILLIC SMALL LETTER UKRAINIAN IE
    table[0xBA] = 0x0407; // CYRILLIC CAPITAL LETTER YI
    table[0xBB] = 0x0457; // CYRILLIC SMALL LETTER YI
    table[0xBC] = 0x0409; // CYRILLIC CAPITAL LETTER LJE
    table[0xBD] = 0x0459; // CYRILLIC SMALL LETTER LJE
    table[0xBE] = 0x040A; // CYRILLIC CAPITAL LETTER NJE
    table[0xBF] = 0x045A; // CYRILLIC SMALL LETTER NJE
    // 0xC0-0xCF
    table[0xC0] = 0x0458; // CYRILLIC SMALL LETTER JE
    table[0xC1] = 0x0405; // CYRILLIC CAPITAL LETTER DZE
    table[0xC2] = 0x00AC; // NOT SIGN
    table[0xC3] = 0x221A; // SQUARE ROOT
    table[0xC4] = 0x0192; // LATIN SMALL LETTER F WITH HOOK
    table[0xC5] = 0x2248; // ALMOST EQUAL TO
    table[0xC6] = 0x2206; // INCREMENT
    table[0xC7] = 0x00AB; // LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xC8] = 0x00BB; // RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    table[0xC9] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0xCA] = 0x00A0; // NO-BREAK SPACE
    table[0xCB] = 0x040B; // CYRILLIC CAPITAL LETTER TSHE
    table[0xCC] = 0x045B; // CYRILLIC SMALL LETTER TSHE
    table[0xCD] = 0x040C; // CYRILLIC CAPITAL LETTER KJE
    table[0xCE] = 0x045C; // CYRILLIC SMALL LETTER KJE
    table[0xCF] = 0x0455; // CYRILLIC SMALL LETTER DZE
    // 0xD0-0xDF
    table[0xD0] = 0x2013; // EN DASH
    table[0xD1] = 0x2014; // EM DASH
    table[0xD2] = 0x201C; // LEFT DOUBLE QUOTATION MARK
    table[0xD3] = 0x201D; // RIGHT DOUBLE QUOTATION MARK
    table[0xD4] = 0x2018; // LEFT SINGLE QUOTATION MARK
    table[0xD5] = 0x2019; // RIGHT SINGLE QUOTATION MARK
    table[0xD6] = 0x00F7; // DIVISION SIGN
    table[0xD7] = 0x201E; // DOUBLE LOW-9 QUOTATION MARK
    table[0xD8] = 0x040E; // CYRILLIC CAPITAL LETTER SHORT U
    table[0xD9] = 0x045E; // CYRILLIC SMALL LETTER SHORT U
    table[0xDA] = 0x040F; // CYRILLIC CAPITAL LETTER DZHE
    table[0xDB] = 0x045F; // CYRILLIC SMALL LETTER DZHE
    table[0xDC] = 0x2116; // NUMERO SIGN
    table[0xDD] = 0x0401; // CYRILLIC CAPITAL LETTER IO
    table[0xDE] = 0x0451; // CYRILLIC SMALL LETTER IO
    table[0xDF] = 0x044F; // CYRILLIC SMALL LETTER YA
    // 0xE0-0xFF: Cyrillic small letters
    table[0xE0] = 0x0430; // CYRILLIC SMALL LETTER A
    table[0xE1] = 0x0431; // CYRILLIC SMALL LETTER BE
    table[0xE2] = 0x0432; // CYRILLIC SMALL LETTER VE
    table[0xE3] = 0x0433; // CYRILLIC SMALL LETTER GHE
    table[0xE4] = 0x0434; // CYRILLIC SMALL LETTER DE
    table[0xE5] = 0x0435; // CYRILLIC SMALL LETTER IE
    table[0xE6] = 0x0436; // CYRILLIC SMALL LETTER ZHE
    table[0xE7] = 0x0437; // CYRILLIC SMALL LETTER ZE
    table[0xE8] = 0x0438; // CYRILLIC SMALL LETTER I
    table[0xE9] = 0x0439; // CYRILLIC SMALL LETTER SHORT I
    table[0xEA] = 0x043A; // CYRILLIC SMALL LETTER KA
    table[0xEB] = 0x043B; // CYRILLIC SMALL LETTER EL
    table[0xEC] = 0x043C; // CYRILLIC SMALL LETTER EM
    table[0xED] = 0x043D; // CYRILLIC SMALL LETTER EN
    table[0xEE] = 0x043E; // CYRILLIC SMALL LETTER O
    table[0xEF] = 0x043F; // CYRILLIC SMALL LETTER PE
    table[0xF0] = 0x0440; // CYRILLIC SMALL LETTER ER
    table[0xF1] = 0x0441; // CYRILLIC SMALL LETTER ES
    table[0xF2] = 0x0442; // CYRILLIC SMALL LETTER TE
    table[0xF3] = 0x0443; // CYRILLIC SMALL LETTER U
    table[0xF4] = 0x0444; // CYRILLIC SMALL LETTER EF
    table[0xF5] = 0x0445; // CYRILLIC SMALL LETTER HA
    table[0xF6] = 0x0446; // CYRILLIC SMALL LETTER TSE
    table[0xF7] = 0x0447; // CYRILLIC SMALL LETTER CHE
    table[0xF8] = 0x0448; // CYRILLIC SMALL LETTER SHA
    table[0xF9] = 0x0449; // CYRILLIC SMALL LETTER SHCHA
    table[0xFA] = 0x044A; // CYRILLIC SMALL LETTER HARD SIGN
    table[0xFB] = 0x044B; // CYRILLIC SMALL LETTER YERU
    table[0xFC] = 0x044C; // CYRILLIC SMALL LETTER SOFT SIGN
    table[0xFD] = 0x044D; // CYRILLIC SMALL LETTER E
    table[0xFE] = 0x044E; // CYRILLIC SMALL LETTER YU
    table[0xFF] = 0x20AC; // EURO SIGN
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "mac_cyrillic decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
