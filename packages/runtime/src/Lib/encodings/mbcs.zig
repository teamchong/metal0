//! Python 'mbcs' Codec
//!
//! Windows Multi-Byte Character Set encoding.
//! This is a platform-specific encoding that uses the system's ANSI code page.
//! On non-Windows platforms, it typically falls back to cp1252 (Windows Latin-1).
//!
//! Mirrors: CPython Lib/encodings/mbcs.py

const std = @import("std");
const cp1252 = @import("cp1252.zig");

pub const name = "mbcs";
pub const aliases = [_][]const u8{ "ansi", "dbcs" };

pub const DecodeResult = struct {
    output: []u8,
    bytes_consumed: usize,
};

pub const EncodeResult = struct {
    output: []u8,
    chars_consumed: usize,
};

pub const ErrorMode = enum {
    strict,
    replace,
    ignore,
    xmlcharrefreplace,
    backslashreplace,
};

/// Decode MBCS to UTF-8
/// On non-Windows, falls back to CP1252
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // Use CP1252 as default ANSI/MBCS codepage on non-Windows
    return cp1252.decode(allocator, input, mode);
}

/// Encode UTF-8 to MBCS
/// On non-Windows, falls back to CP1252
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    // Use CP1252 as default ANSI/MBCS codepage on non-Windows
    return cp1252.encode(allocator, input, mode);
}

test "mbcs decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "mbcs encode" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "mbcs decode extended" {
    // 0x80 in CP1252 is Euro sign
    const result = try decode(std.testing.allocator, &[_]u8{0x80}, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xE2\x82\xAC", result.output); // UTF-8 Euro
}
