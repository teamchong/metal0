//! Python 'euc_jis_2004' Codec (EUC-JIS-2004)
//!
//! Implements EUC-JIS-2004 encoding based on JIS X 0213:2004.
//! Extension of EUC-JP with additional characters.
//!
//! Note: Full implementation requires additional mapping entries.
//! This provides the codec framework delegating to euc_jp.
//!
//! Mirrors: CPython Lib/encodings/euc_jis_2004.py

const std = @import("std");
const euc_jp = @import("euc_jp.zig");

pub const name = "euc_jis_2004";
pub const aliases = [_][]const u8{ "jisx0213", "eucjis2004" };

pub const DecodeResult = euc_jp.DecodeResult;
pub const EncodeResult = euc_jp.EncodeResult;
pub const ErrorMode = euc_jp.ErrorMode;

/// Decode EUC-JIS-2004 to UTF-8
/// Based on JIS X 0213:2004, extends EUC-JP
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // EUC-JIS-2004 is compatible with EUC-JP for most characters
    return euc_jp.decode(allocator, input, mode);
}

/// Encode UTF-8 to EUC-JIS-2004
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return euc_jp.encode(allocator, input, mode);
}

test "euc_jis_2004 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "euc_jis_2004 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
