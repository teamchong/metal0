//! Python 'shift_jisx0213' Codec (Shift_JISX0213)
//!
//! Implements Shift_JISX0213 encoding based on JIS X 0213:2000.
//! Extension of Shift_JIS with additional characters.
//!
//! Note: Full implementation requires additional mapping entries.
//! This provides the codec framework delegating to shift_jis.
//!
//! Mirrors: CPython Lib/encodings/shift_jisx0213.py

const std = @import("std");
const shift_jis = @import("shift_jis.zig");

pub const name = "shift_jisx0213";
pub const aliases = [_][]const u8{ "shiftjisx0213", "sjisx0213", "s_jisx0213" };

pub const DecodeResult = shift_jis.DecodeResult;
pub const EncodeResult = shift_jis.EncodeResult;
pub const ErrorMode = shift_jis.ErrorMode;

/// Decode Shift_JISX0213 to UTF-8
/// Based on JIS X 0213:2000, extends Shift_JIS
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // Shift_JISX0213 is compatible with Shift_JIS for most characters
    return shift_jis.decode(allocator, input, mode);
}

/// Encode UTF-8 to Shift_JISX0213
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return shift_jis.encode(allocator, input, mode);
}

test "shift_jisx0213 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "shift_jisx0213 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
