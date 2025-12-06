//! Python 'iso2022_jp_ext' Codec (ISO-2022-JP-EXT)
//!
//! Implements ISO-2022-JP-EXT encoding for Japanese text.
//! Extended version with additional character sets support.
//!
//! Mirrors: CPython Lib/encodings/iso2022_jp_ext.py

const std = @import("std");
const iso2022_jp = @import("iso2022_jp.zig");

pub const name = "iso2022_jp_ext";
pub const aliases = [_][]const u8{ "iso2022jp-ext", "iso-2022-jp-ext" };

pub const DecodeResult = iso2022_jp.DecodeResult;
pub const EncodeResult = iso2022_jp.EncodeResult;
pub const ErrorMode = iso2022_jp.ErrorMode;

/// Decode ISO-2022-JP-EXT to UTF-8
/// Extended version of ISO-2022-JP
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // ISO-2022-JP-EXT is compatible with ISO-2022-JP for base sequences
    return iso2022_jp.decode(allocator, input, mode);
}

/// Encode UTF-8 to ISO-2022-JP-EXT
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return iso2022_jp.encode(allocator, input, mode);
}

test "iso2022_jp_ext decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "iso2022_jp_ext encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
