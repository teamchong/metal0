//! Python 'oem' Codec
//!
//! Windows OEM (Original Equipment Manufacturer) code page encoding.
//! This is a platform-specific encoding that uses the system's OEM code page.
//! On non-Windows platforms, it typically falls back to cp437.
//!
//! Mirrors: CPython Lib/encodings/oem.py

const std = @import("std");
const cp437 = @import("cp437.zig");

pub const name = "oem";
pub const aliases = [_][]const u8{};

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

/// Decode OEM to UTF-8
/// On non-Windows, falls back to CP437
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    // Use CP437 as default OEM codepage
    return cp437.decode(allocator, input, mode);
}

/// Encode UTF-8 to OEM
/// On non-Windows, falls back to CP437
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    // Use CP437 as default OEM codepage
    return cp437.encode(allocator, input, mode);
}

test "oem decode" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "oem encode" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
