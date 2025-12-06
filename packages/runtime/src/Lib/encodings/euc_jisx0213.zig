//! Python 'euc_jisx0213' Codec (EUC-JISX0213)
//!
//! Implements EUC-JISX0213 encoding based on JIS X 0213:2000.
//! Extension of EUC-JP with additional characters.
//!
//! Note: Full implementation requires additional mapping entries.
//! This provides the codec framework delegating to euc_jp.
//!
//! Mirrors: CPython Lib/encodings/euc_jisx0213.py

const std = @import("std");
const euc_jp = @import("euc_jp.zig");

pub const name = "euc_jisx0213";
pub const aliases = [_][]const u8{ "eucjisx0213", "eucx0213" };

pub const DecodeResult = euc_jp.DecodeResult;
pub const EncodeResult = euc_jp.EncodeResult;
pub const ErrorMode = euc_jp.ErrorMode;

/// Decode EUC-JISX0213 to UTF-8
/// Based on JIS X 0213:2000, extends EUC-JP
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // EUC-JISX0213 is compatible with EUC-JP for most characters
    return euc_jp.decode(allocator, input, mode);
}

/// Encode UTF-8 to EUC-JISX0213
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return euc_jp.encode(allocator, input, mode);
}

test "euc_jisx0213 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "euc_jisx0213 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
