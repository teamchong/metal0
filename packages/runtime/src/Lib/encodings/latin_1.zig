//! CPython source: Lib/encodings/latin_1.py
//!
//! Latin-1 is the simplest possible encoding: bytes 0x00-0xFF map directly
//! to Unicode codepoints U+0000-U+00FF. This is a bijective mapping.
//!
//! Aliases: latin_1, iso-8859-1, iso8859-1, 8859, cp819, latin, L1
//!
//! Mirrors: CPython Lib/encodings/latin_1.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "latin-1";
pub const aliases = [_][]const u8{
    "latin_1",
    "iso-8859-1",
    "iso8859-1",
    "8859",
    "cp819",
    "latin",
    "L1",
    "iso_8859_1",
};

/// Re-export types
pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

/// Latin-1 Codec using the charmap infrastructure
pub const Codec = charmap.Latin1;

/// Decode Latin-1 bytes to UTF-8
/// Every byte 0x00-0xFF maps to U+0000-U+00FF
pub const decode = Codec.decode;

/// Encode UTF-8 to Latin-1 bytes
/// Only codepoints U+0000-U+00FF can be encoded
pub const encode = Codec.encode;

// Tests
test "latin1 decode all bytes" {
    // Latin-1 should decode all 256 byte values without error
    var input: [256]u8 = undefined;
    for (0..256) |i| {
        input[i] = @intCast(i);
    }

    const result = try decode(std.testing.allocator, &input, .strict);
    defer std.testing.allocator.free(result.output);

    // Output should be longer due to UTF-8 encoding of bytes >= 0x80
    try std.testing.expect(result.output.len > 256);
}

test "latin1 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello, World!", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello, World!", result.output);
}

test "latin1 decode high bytes" {
    // 0xA0 = non-breaking space, 0xE9 = é
    const result = try decode(std.testing.allocator, "\xa0\xe9", .strict);
    defer std.testing.allocator.free(result.output);
    // UTF-8: 0xC2 0xA0 for U+00A0, 0xC3 0xA9 for U+00E9
    try std.testing.expectEqualStrings("\xc2\xa0\xc3\xa9", result.output);
}

test "latin1 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "latin1 encode high codepoints" {
    // U+00E9 (é) encoded as UTF-8: 0xC3 0xA9
    const result = try encode(std.testing.allocator, "\xc3\xa9", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xe9", result.output);
}

test "latin1 encode out of range" {
    // U+0100 (Ā) is not in Latin-1 range (U+0000-U+00FF)
    const result = encode(std.testing.allocator, "\xc4\x80", .strict);
    try std.testing.expectError(error.UnicodeEncodeError, result);
}

test "latin1 encode out of range replace" {
    // U+0100 (Ā) with replace error handler
    const result = try encode(std.testing.allocator, "\xc4\x80", .replace);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("?", result.output);
}
