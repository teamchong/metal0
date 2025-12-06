//! Python 'shift_jis_2004' Codec (Shift_JIS-2004)
//!
//! Implements Shift_JIS-2004 encoding based on JIS X 0213:2004.
//! Extension of Shift_JIS with additional characters.
//!
//! Note: Full implementation requires additional mapping entries.
//! This provides the codec framework delegating to shift_jis.
//!
//! Mirrors: CPython Lib/encodings/shift_jis_2004.py

const std = @import("std");
const shift_jis = @import("shift_jis.zig");

pub const name = "shift_jis_2004";
pub const aliases = [_][]const u8{ "shiftjis2004", "sjis_2004", "sjis2004" };

pub const DecodeResult = shift_jis.DecodeResult;
pub const EncodeResult = shift_jis.EncodeResult;
pub const ErrorMode = shift_jis.ErrorMode;

/// Decode Shift_JIS-2004 to UTF-8
/// Based on JIS X 0213:2004, extends Shift_JIS
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // Shift_JIS-2004 is compatible with Shift_JIS for most characters
    return shift_jis.decode(allocator, input, mode);
}

/// Encode UTF-8 to Shift_JIS-2004
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    return shift_jis.encode(allocator, input, mode);
}

test "shift_jis_2004 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "shift_jis_2004 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
