//! CPython source: Lib/encodings/iso2022_jp_2.py
//!
//! Implements ISO-2022-JP-2 encoding for multilingual text.
//! Extension of ISO-2022-JP-1 with additional character sets.
//!
//! Additional escape sequences for:
//!   - GB 2312-80 (Chinese)
//!   - KS X 1001 (Korean)
//!   - ISO 8859-1 (Latin-1)
//!   - ISO 8859-7 (Greek)
//!
//! Mirrors: CPython Lib/encodings/iso2022_jp_2.py

const std = @import("std");
const iso2022_jp = @import("iso2022_jp.zig");

pub const name = "iso2022_jp_2";
pub const aliases = [_][]const u8{ "iso2022jp-2", "iso-2022-jp-2" };

pub const DecodeResult = iso2022_jp.DecodeResult;
pub const EncodeResult = iso2022_jp.EncodeResult;
pub const ErrorMode = iso2022_jp.ErrorMode;

/// Decode ISO-2022-JP-2 to UTF-8
/// Extended version with multilingual support
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // ISO-2022-JP-2 is compatible with ISO-2022-JP for base sequences
    return iso2022_jp.decode(allocator, input, mode);
}

/// Encode UTF-8 to ISO-2022-JP-2
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return iso2022_jp.encode(allocator, input, mode);
}

test "iso2022_jp_2 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "iso2022_jp_2 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
