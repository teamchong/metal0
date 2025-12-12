//! CPython source: Lib/encodings/utf_16.py
//!
//! UTF-16 encoding with BOM detection on decode and BOM prefix on encode.
//!
//! Mirrors: CPython Lib/encodings/utf_16.py

const std = @import("std");
const charmap = @import("charmap.zig");
const utf_16_le = @import("utf_16_le.zig");
const utf_16_be = @import("utf_16_be.zig");

pub const name = "utf-16";
pub const aliases = [_][]const u8{ "utf_16", "UTF-16", "U16" };

pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

/// BOM constants
pub const BOM_LE = "\xff\xfe";
pub const BOM_BE = "\xfe\xff";

/// Decode UTF-16 bytes to UTF-8 (auto-detects endianness from BOM)
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    if (input.len < 2) {
        // No BOM possible, assume LE (native for most systems)
        return utf_16_le.decode(allocator, input, errors);
    }

    // Check for BOM
    if (input[0] == 0xFF and input[1] == 0xFE) {
        // Little endian BOM
        return utf_16_le.decode(allocator, input[2..], errors);
    } else if (input[0] == 0xFE and input[1] == 0xFF) {
        // Big endian BOM
        return utf_16_be.decode(allocator, input[2..], errors);
    }

    // No BOM - assume native (LE on most systems)
    return utf_16_le.decode(allocator, input, errors);
}

/// Encode UTF-8 string to UTF-16 bytes (with LE BOM prefix)
pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
    const inner_result = try utf_16_le.encode(allocator, input, errors);

    // Prepend BOM
    var output: std.ArrayList(u8) = .{};
    errdefer output.deinit(allocator);

    try output.appendSlice(allocator, BOM_LE);
    try output.appendSlice(allocator, inner_result.output);
    allocator.free(inner_result.output);

    return .{
        .output = try output.toOwnedSlice(allocator),
        .chars_consumed = inner_result.chars_consumed,
    };
}

test "utf16 decode with le bom" {
    const result = try decode(std.testing.allocator, "\xff\xfeH\x00i\x00", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi", result.output);
}

test "utf16 decode with be bom" {
    const result = try decode(std.testing.allocator, "\xfe\xff\x00H\x00i", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi", result.output);
}

test "utf16 encode adds bom" {
    const result = try encode(std.testing.allocator, "Hi", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xff\xfeH\x00i\x00", result.output);
}
