//! Python 'cp874' Codec (Windows Thai)
//!
//! Windows Thai codepage
//!
//! Mirrors: CPython Lib/encodings/cp874.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp874";
pub const aliases = [_][]const u8{ "windows-874" };

const UNDEF = charmap.UNDEFINED;

/// CP874 decode table
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0x7F same as ASCII
    for (0..0x80) |i| table[i] = @intCast(i);
    // 0x80-0x9F
    table[0x80] = 0x20AC; // EURO SIGN
    table[0x81] = UNDEF;
    table[0x82] = UNDEF;
    table[0x83] = UNDEF;
    table[0x84] = UNDEF;
    table[0x85] = 0x2026; // HORIZONTAL ELLIPSIS
    table[0x86] = UNDEF;
    table[0x87] = UNDEF;
    table[0x88] = UNDEF;
    table[0x89] = UNDEF;
    table[0x8A] = UNDEF;
    table[0x8B] = UNDEF;
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
    table[0x99] = UNDEF;
    table[0x9A] = UNDEF;
    table[0x9B] = UNDEF;
    table[0x9C] = UNDEF;
    table[0x9D] = UNDEF;
    table[0x9E] = UNDEF;
    table[0x9F] = UNDEF;
    // 0xA0-0xBF: Thai characters
    table[0xA0] = 0x00A0; // NO-BREAK SPACE
    table[0xA1] = 0x0E01; // THAI CHARACTER KO KAI
    table[0xA2] = 0x0E02; // THAI CHARACTER KHO KHAI
    table[0xA3] = 0x0E03; // THAI CHARACTER KHO KHUAT
    table[0xA4] = 0x0E04; // THAI CHARACTER KHO KHWAI
    table[0xA5] = 0x0E05; // THAI CHARACTER KHO KHON
    table[0xA6] = 0x0E06; // THAI CHARACTER KHO RAKHANG
    table[0xA7] = 0x0E07; // THAI CHARACTER NGO NGU
    table[0xA8] = 0x0E08; // THAI CHARACTER CHO CHAN
    table[0xA9] = 0x0E09; // THAI CHARACTER CHO CHING
    table[0xAA] = 0x0E0A; // THAI CHARACTER CHO CHANG
    table[0xAB] = 0x0E0B; // THAI CHARACTER SO SO
    table[0xAC] = 0x0E0C; // THAI CHARACTER CHO CHOE
    table[0xAD] = 0x0E0D; // THAI CHARACTER YO YING
    table[0xAE] = 0x0E0E; // THAI CHARACTER DO CHADA
    table[0xAF] = 0x0E0F; // THAI CHARACTER TO PATAK
    table[0xB0] = 0x0E10; // THAI CHARACTER THO THAN
    table[0xB1] = 0x0E11; // THAI CHARACTER THO NANGMONTHO
    table[0xB2] = 0x0E12; // THAI CHARACTER THO PHUTHAO
    table[0xB3] = 0x0E13; // THAI CHARACTER NO NEN
    table[0xB4] = 0x0E14; // THAI CHARACTER DO DEK
    table[0xB5] = 0x0E15; // THAI CHARACTER TO TAO
    table[0xB6] = 0x0E16; // THAI CHARACTER THO THUNG
    table[0xB7] = 0x0E17; // THAI CHARACTER THO THAHAN
    table[0xB8] = 0x0E18; // THAI CHARACTER THO THONG
    table[0xB9] = 0x0E19; // THAI CHARACTER NO NU
    table[0xBA] = 0x0E1A; // THAI CHARACTER BO BAIMAI
    table[0xBB] = 0x0E1B; // THAI CHARACTER PO PLA
    table[0xBC] = 0x0E1C; // THAI CHARACTER PHO PHUNG
    table[0xBD] = 0x0E1D; // THAI CHARACTER FO FA
    table[0xBE] = 0x0E1E; // THAI CHARACTER PHO PHAN
    table[0xBF] = 0x0E1F; // THAI CHARACTER FO FAN
    // 0xC0-0xDF
    table[0xC0] = 0x0E20; // THAI CHARACTER PHO SAMPHAO
    table[0xC1] = 0x0E21; // THAI CHARACTER MO MA
    table[0xC2] = 0x0E22; // THAI CHARACTER YO YAK
    table[0xC3] = 0x0E23; // THAI CHARACTER RO RUA
    table[0xC4] = 0x0E24; // THAI CHARACTER RU
    table[0xC5] = 0x0E25; // THAI CHARACTER LO LING
    table[0xC6] = 0x0E26; // THAI CHARACTER LU
    table[0xC7] = 0x0E27; // THAI CHARACTER WO WAEN
    table[0xC8] = 0x0E28; // THAI CHARACTER SO SALA
    table[0xC9] = 0x0E29; // THAI CHARACTER SO RUSI
    table[0xCA] = 0x0E2A; // THAI CHARACTER SO SUA
    table[0xCB] = 0x0E2B; // THAI CHARACTER HO HIP
    table[0xCC] = 0x0E2C; // THAI CHARACTER LO CHULA
    table[0xCD] = 0x0E2D; // THAI CHARACTER O ANG
    table[0xCE] = 0x0E2E; // THAI CHARACTER HO NOKHUK
    table[0xCF] = 0x0E2F; // THAI CHARACTER PAIYANNOI
    table[0xD0] = 0x0E30; // THAI CHARACTER SARA A
    table[0xD1] = 0x0E31; // THAI CHARACTER MAI HAN-AKAT
    table[0xD2] = 0x0E32; // THAI CHARACTER SARA AA
    table[0xD3] = 0x0E33; // THAI CHARACTER SARA AM
    table[0xD4] = 0x0E34; // THAI CHARACTER SARA I
    table[0xD5] = 0x0E35; // THAI CHARACTER SARA II
    table[0xD6] = 0x0E36; // THAI CHARACTER SARA UE
    table[0xD7] = 0x0E37; // THAI CHARACTER SARA UEE
    table[0xD8] = 0x0E38; // THAI CHARACTER SARA U
    table[0xD9] = 0x0E39; // THAI CHARACTER SARA UU
    table[0xDA] = 0x0E3A; // THAI CHARACTER PHINTHU
    table[0xDB] = UNDEF;
    table[0xDC] = UNDEF;
    table[0xDD] = UNDEF;
    table[0xDE] = UNDEF;
    table[0xDF] = 0x0E3F; // THAI CURRENCY SYMBOL BAHT
    // 0xE0-0xFF
    table[0xE0] = 0x0E40; // THAI CHARACTER SARA E
    table[0xE1] = 0x0E41; // THAI CHARACTER SARA AE
    table[0xE2] = 0x0E42; // THAI CHARACTER SARA O
    table[0xE3] = 0x0E43; // THAI CHARACTER SARA AI MAIMUAN
    table[0xE4] = 0x0E44; // THAI CHARACTER SARA AI MAIMALAI
    table[0xE5] = 0x0E45; // THAI CHARACTER LAKKHANGYAO
    table[0xE6] = 0x0E46; // THAI CHARACTER MAIYAMOK
    table[0xE7] = 0x0E47; // THAI CHARACTER MAITAIKHU
    table[0xE8] = 0x0E48; // THAI CHARACTER MAI EK
    table[0xE9] = 0x0E49; // THAI CHARACTER MAI THO
    table[0xEA] = 0x0E4A; // THAI CHARACTER MAI TRI
    table[0xEB] = 0x0E4B; // THAI CHARACTER MAI CHATTAWA
    table[0xEC] = 0x0E4C; // THAI CHARACTER THANTHAKHAT
    table[0xED] = 0x0E4D; // THAI CHARACTER NIKHAHIT
    table[0xEE] = 0x0E4E; // THAI CHARACTER YAMAKKAN
    table[0xEF] = 0x0E4F; // THAI CHARACTER FONGMAN
    table[0xF0] = 0x0E50; // THAI DIGIT ZERO
    table[0xF1] = 0x0E51; // THAI DIGIT ONE
    table[0xF2] = 0x0E52; // THAI DIGIT TWO
    table[0xF3] = 0x0E53; // THAI DIGIT THREE
    table[0xF4] = 0x0E54; // THAI DIGIT FOUR
    table[0xF5] = 0x0E55; // THAI DIGIT FIVE
    table[0xF6] = 0x0E56; // THAI DIGIT SIX
    table[0xF7] = 0x0E57; // THAI DIGIT SEVEN
    table[0xF8] = 0x0E58; // THAI DIGIT EIGHT
    table[0xF9] = 0x0E59; // THAI DIGIT NINE
    table[0xFA] = 0x0E5A; // THAI CHARACTER ANGKHANKHU
    table[0xFB] = 0x0E5B; // THAI CHARACTER KHOMUT
    table[0xFC] = UNDEF;
    table[0xFD] = UNDEF;
    table[0xFE] = UNDEF;
    table[0xFF] = UNDEF;
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "cp874 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
