//! CPython source: Lib/encodings/cp932.py
//!
//! Microsoft's extension of Shift_JIS for Japanese.
//! Adds NEC special characters and IBM extensions.
//!
//! Note: Full implementation requires ~7000+ mapping entries.
//! This provides the codec framework delegating to shift_jis.
//!
//! Mirrors: CPython Lib/encodings/cp932.py

const std = @import("std");
const shift_jis = @import("shift_jis.zig");

pub const name = "cp932";
pub const aliases = [_][]const u8{ "932", "ms932", "mskanji", "ms-kanji" };

pub const DecodeResult = shift_jis.DecodeResult;
pub const EncodeResult = shift_jis.EncodeResult;
pub const ErrorMode = shift_jis.ErrorMode;

/// Decode CP932 to UTF-8
/// CP932 is largely compatible with Shift_JIS, delegate to it
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // CP932 extends Shift_JIS with additional characters
    // For now, delegate to Shift_JIS implementation
    return shift_jis.decode(allocator, input, mode);
}

/// Encode UTF-8 to CP932
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return shift_jis.encode(allocator, input, mode);
}

test "cp932 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "cp932 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
