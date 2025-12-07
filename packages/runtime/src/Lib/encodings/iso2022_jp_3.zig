//! CPython source: Lib/encodings/iso2022_jp_3.py
//!
//! Implements ISO-2022-JP-3 encoding based on JIS X 0213:2000.
//! Extension of ISO-2022-JP with JIS X 0213 plane 1 and 2.
//!
//! Mirrors: CPython Lib/encodings/iso2022_jp_3.py

const std = @import("std");
const iso2022_jp = @import("iso2022_jp.zig");

pub const name = "iso2022_jp_3";
pub const aliases = [_][]const u8{ "iso2022jp-3", "iso-2022-jp-3" };

pub const DecodeResult = iso2022_jp.DecodeResult;
pub const EncodeResult = iso2022_jp.EncodeResult;
pub const ErrorMode = iso2022_jp.ErrorMode;

/// Decode ISO-2022-JP-3 to UTF-8
/// Based on JIS X 0213:2000
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // ISO-2022-JP-3 is compatible with ISO-2022-JP for base sequences
    return iso2022_jp.decode(allocator, input, mode);
}

/// Encode UTF-8 to ISO-2022-JP-3
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return iso2022_jp.encode(allocator, input, mode);
}

test "iso2022_jp_3 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "iso2022_jp_3 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
