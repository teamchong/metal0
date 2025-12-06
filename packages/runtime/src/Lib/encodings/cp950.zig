//! Python 'cp950' Codec (Windows Code Page 950)
//!
//! Microsoft's extension of Big5 for Traditional Chinese.
//! Used primarily in Taiwan and Hong Kong Windows systems.
//!
//! Note: Full implementation requires ~13000+ mapping entries.
//! This provides the codec framework delegating to big5.
//!
//! Mirrors: CPython Lib/encodings/cp950.py

const std = @import("std");
const big5 = @import("big5.zig");

pub const name = "cp950";
pub const aliases = [_][]const u8{ "950", "ms950" };

pub const DecodeResult = big5.DecodeResult;
pub const EncodeResult = big5.EncodeResult;
pub const ErrorMode = big5.ErrorMode;

/// Decode CP950 to UTF-8
/// CP950 is largely compatible with Big5, delegate to it
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // CP950 extends Big5 with additional characters
    // For now, delegate to Big5 implementation
    return big5.decode(allocator, input, mode);
}

/// Encode UTF-8 to CP950
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return big5.encode(allocator, input, mode);
}

test "cp950 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "cp950 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
