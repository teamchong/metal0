//! CPython source: Lib/encodings/cp1252.py
//!
//! Windows-1252 is a single-byte encoding used historically by Windows.
//! It's a superset of ISO-8859-1 (Latin-1) with additional characters in the 0x80-0x9F range.
//!
//! Mirrors: CPython Lib/encodings/cp1252.py
//! Generated from: MAPPINGS/VENDORS/MICSFT/WINDOWS/CP1252.TXT

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "cp1252";
pub const aliases = [_][]const u8{ "windows-1252", "1252" };

/// CP1252 decode table: maps bytes 0x00-0xFF to Unicode codepoints
/// 0x80-0x9F contains special Windows characters (unlike Latin-1)
/// UNDEFINED (0xFFFE) marks invalid byte positions (0x81, 0x8D, 0x8F, 0x90, 0x9D)
pub const decode_table: [256]u21 = .{
    // 0x00-0x7F: ASCII (same as all encodings)
    0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, // 00-07
    0x0008, 0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x000E, 0x000F, // 08-0F
    0x0010, 0x0011, 0x0012, 0x0013, 0x0014, 0x0015, 0x0016, 0x0017, // 10-17
    0x0018, 0x0019, 0x001A, 0x001B, 0x001C, 0x001D, 0x001E, 0x001F, // 18-1F
    0x0020, 0x0021, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027, // 20-27 (space, !, ", #, $, %, &, ')
    0x0028, 0x0029, 0x002A, 0x002B, 0x002C, 0x002D, 0x002E, 0x002F, // 28-2F ((, ), *, +, comma, -, ., /)
    0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, // 30-37 (0-7)
    0x0038, 0x0039, 0x003A, 0x003B, 0x003C, 0x003D, 0x003E, 0x003F, // 38-3F (8, 9, :, ;, <, =, >, ?)
    0x0040, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047, // 40-47 (@, A-G)
    0x0048, 0x0049, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F, // 48-4F (H-O)
    0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, // 50-57 (P-W)
    0x0058, 0x0059, 0x005A, 0x005B, 0x005C, 0x005D, 0x005E, 0x005F, // 58-5F (X, Y, Z, [, \, ], ^, _)
    0x0060, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067, // 60-67 (`, a-g)
    0x0068, 0x0069, 0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F, // 68-6F (h-o)
    0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076, 0x0077, // 70-77 (p-w)
    0x0078, 0x0079, 0x007A, 0x007B, 0x007C, 0x007D, 0x007E, 0x007F, // 78-7F (x, y, z, {, |, }, ~, DEL)

    // 0x80-0x9F: Windows-specific characters (different from Latin-1!)
    0x20AC, // 0x80 -> EURO SIGN
    charmap.UNDEFINED, // 0x81 -> UNDEFINED
    0x201A, // 0x82 -> SINGLE LOW-9 QUOTATION MARK
    0x0192, // 0x83 -> LATIN SMALL LETTER F WITH HOOK
    0x201E, // 0x84 -> DOUBLE LOW-9 QUOTATION MARK
    0x2026, // 0x85 -> HORIZONTAL ELLIPSIS
    0x2020, // 0x86 -> DAGGER
    0x2021, // 0x87 -> DOUBLE DAGGER
    0x02C6, // 0x88 -> MODIFIER LETTER CIRCUMFLEX ACCENT
    0x2030, // 0x89 -> PER MILLE SIGN
    0x0160, // 0x8A -> LATIN CAPITAL LETTER S WITH CARON
    0x2039, // 0x8B -> SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    0x0152, // 0x8C -> LATIN CAPITAL LIGATURE OE
    charmap.UNDEFINED, // 0x8D -> UNDEFINED
    0x017D, // 0x8E -> LATIN CAPITAL LETTER Z WITH CARON
    charmap.UNDEFINED, // 0x8F -> UNDEFINED
    charmap.UNDEFINED, // 0x90 -> UNDEFINED
    0x2018, // 0x91 -> LEFT SINGLE QUOTATION MARK
    0x2019, // 0x92 -> RIGHT SINGLE QUOTATION MARK
    0x201C, // 0x93 -> LEFT DOUBLE QUOTATION MARK
    0x201D, // 0x94 -> RIGHT DOUBLE QUOTATION MARK
    0x2022, // 0x95 -> BULLET
    0x2013, // 0x96 -> EN DASH
    0x2014, // 0x97 -> EM DASH
    0x02DC, // 0x98 -> SMALL TILDE
    0x2122, // 0x99 -> TRADE MARK SIGN
    0x0161, // 0x9A -> LATIN SMALL LETTER S WITH CARON
    0x203A, // 0x9B -> SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    0x0153, // 0x9C -> LATIN SMALL LIGATURE OE
    charmap.UNDEFINED, // 0x9D -> UNDEFINED
    0x017E, // 0x9E -> LATIN SMALL LETTER Z WITH CARON
    0x0178, // 0x9F -> LATIN CAPITAL LETTER Y WITH DIAERESIS

    // 0xA0-0xFF: Same as Latin-1 (ISO-8859-1)
    0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7, // A0-A7
    0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, // A8-AF
    0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, // B0-B7
    0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF, // B8-BF
    0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C6, 0x00C7, // C0-C7
    0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF, // C8-CF
    0x00D0, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00D7, // D0-D7
    0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00DF, // D8-DF
    0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, 0x00E6, 0x00E7, // E0-E7
    0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF, // E8-EF
    0x00F0, 0x00F1, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F7, // F0-F7
    0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x00FD, 0x00FE, 0x00FF, // F8-FF
};

/// CP1252 Codec using the charmap infrastructure
pub const Codec = charmap.CharmapCodec(&decode_table, "cp1252");

/// Decode CP1252 bytes to UTF-8
pub const decode = Codec.decode;

/// Encode UTF-8 to CP1252 bytes
pub const encode = Codec.encode;

/// Re-export types
pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

// Tests
test "cp1252 decode euro sign" {
    const result = try decode(std.testing.allocator, "\x80", .strict);
    defer std.testing.allocator.free(result.output);
    // Euro sign U+20AC encodes as UTF-8: E2 82 AC
    try std.testing.expectEqualStrings("\xe2\x82\xac", result.output);
}

test "cp1252 decode smart quotes" {
    const result = try decode(std.testing.allocator, "\x93Hello\x94", .strict);
    defer std.testing.allocator.free(result.output);
    // U+201C (") and U+201D (")
    try std.testing.expectEqualStrings("\xe2\x80\x9cHello\xe2\x80\x9d", result.output);
}

test "cp1252 decode undefined byte strict" {
    const result = decode(std.testing.allocator, "\x81", .strict);
    try std.testing.expectError(error.UnicodeDecodeError, result);
}

test "cp1252 decode undefined byte replace" {
    const result = try decode(std.testing.allocator, "A\x81B", .replace);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("A\xef\xbf\xbdB", result.output);
}

test "cp1252 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "cp1252 encode euro sign" {
    // Euro sign U+20AC should encode to 0x80
    const result = try encode(std.testing.allocator, "\xe2\x82\xac", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\x80", result.output);
}
