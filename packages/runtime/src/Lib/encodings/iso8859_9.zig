//! CPython source: Lib/encodings/iso8859_9.py
//!
//! Turkish (replaces Icelandic characters with Turkish)
//!
//! Mirrors: CPython Lib/encodings/iso8859_9.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "iso8859-9";
pub const aliases = [_][]const u8{ "iso-8859-9", "latin5", "l5", "iso_8859_9", "turkish" };

/// ISO-8859-9 decode table (mostly same as Latin-1 except Turkish letters)
const decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    // 0x00-0xCF same as Latin-1
    for (0..0xD0) |i| table[i] = @intCast(i);
    // Turkish modifications
    table[0xD0] = 0x011E; // LATIN CAPITAL LETTER G WITH BREVE (was Eth)
    table[0xD1] = 0x00D1; // LATIN CAPITAL LETTER N WITH TILDE
    table[0xD2] = 0x00D2;
    table[0xD3] = 0x00D3;
    table[0xD4] = 0x00D4;
    table[0xD5] = 0x00D5;
    table[0xD6] = 0x00D6;
    table[0xD7] = 0x00D7;
    table[0xD8] = 0x00D8;
    table[0xD9] = 0x00D9;
    table[0xDA] = 0x00DA;
    table[0xDB] = 0x00DB;
    table[0xDC] = 0x00DC;
    table[0xDD] = 0x0130; // LATIN CAPITAL LETTER I WITH DOT ABOVE (was Y acute)
    table[0xDE] = 0x015E; // LATIN CAPITAL LETTER S WITH CEDILLA (was Thorn)
    table[0xDF] = 0x00DF; // LATIN SMALL LETTER SHARP S
    table[0xE0] = 0x00E0;
    table[0xE1] = 0x00E1;
    table[0xE2] = 0x00E2;
    table[0xE3] = 0x00E3;
    table[0xE4] = 0x00E4;
    table[0xE5] = 0x00E5;
    table[0xE6] = 0x00E6;
    table[0xE7] = 0x00E7;
    table[0xE8] = 0x00E8;
    table[0xE9] = 0x00E9;
    table[0xEA] = 0x00EA;
    table[0xEB] = 0x00EB;
    table[0xEC] = 0x00EC;
    table[0xED] = 0x00ED;
    table[0xEE] = 0x00EE;
    table[0xEF] = 0x00EF;
    table[0xF0] = 0x011F; // LATIN SMALL LETTER G WITH BREVE (was eth)
    table[0xF1] = 0x00F1;
    table[0xF2] = 0x00F2;
    table[0xF3] = 0x00F3;
    table[0xF4] = 0x00F4;
    table[0xF5] = 0x00F5;
    table[0xF6] = 0x00F6;
    table[0xF7] = 0x00F7;
    table[0xF8] = 0x00F8;
    table[0xF9] = 0x00F9;
    table[0xFA] = 0x00FA;
    table[0xFB] = 0x00FB;
    table[0xFC] = 0x00FC;
    table[0xFD] = 0x0131; // LATIN SMALL LETTER DOTLESS I (was y acute)
    table[0xFE] = 0x015F; // LATIN SMALL LETTER S WITH CEDILLA (was thorn)
    table[0xFF] = 0x00FF;
    break :blk table;
};

const Codec = charmap.CharmapCodec(&decode_table, name);
pub const decode = Codec.decode;
pub const encode = Codec.encode;

test "iso8859_9 decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
