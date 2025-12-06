//! Python 'rot-13' Codec
//!
//! ROT13 is a simple letter substitution cipher that replaces letters
//! with the letter 13 positions later in the alphabet.
//!
//! Mirrors: CPython Lib/encodings/rot_13.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "rot-13";
pub const aliases = [_][]const u8{ "rot_13", "rot13" };

pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

/// Apply ROT13 transformation to a byte
fn rot13(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') {
        return ((c - 'A' + 13) % 26) + 'A';
    } else if (c >= 'a' and c <= 'z') {
        return ((c - 'a' + 13) % 26) + 'a';
    }
    return c;
}

/// Decode ROT13 (same as encode - it's symmetric)
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    _ = errors;
    const output = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        output[i] = rot13(c);
    }
    return .{
        .output = output,
        .bytes_consumed = input.len,
    };
}

/// Encode to ROT13 (same as decode - it's symmetric)
pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
    _ = errors;
    const output = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        output[i] = rot13(c);
    }
    return .{
        .output = output,
        .chars_consumed = input.len,
    };
}

test "rot13 encode" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Uryyb", result.output);
}

test "rot13 decode" {
    const result = try decode(std.testing.allocator, "Uryyb", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "rot13 roundtrip" {
    const encoded = try encode(std.testing.allocator, "Test123", .strict);
    defer std.testing.allocator.free(encoded.output);
    const decoded = try decode(std.testing.allocator, encoded.output, .strict);
    defer std.testing.allocator.free(decoded.output);
    try std.testing.expectEqualStrings("Test123", decoded.output);
}
