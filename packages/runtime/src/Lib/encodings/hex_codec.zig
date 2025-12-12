//! CPython source: Lib/encodings/hex_codec.py
//!
//! Hex codec - converts bytes to/from hexadecimal representation.
//!
//! Mirrors: CPython Lib/encodings/hex_codec.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "hex";
pub const aliases = [_][]const u8{ "hex_codec" };

pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

const hex_chars = "0123456789abcdef";

fn hexToInt(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

/// Decode hex string to bytes
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    var output: std.ArrayList(u8) = .{};
    errdefer output.deinit(allocator);

    var i: usize = 0;
    while (i + 1 < input.len) {
        // Skip whitespace
        while (i < input.len and (input[i] == ' ' or input[i] == '\t' or input[i] == '\n' or input[i] == '\r')) {
            i += 1;
        }
        if (i + 1 >= input.len) break;

        const high = hexToInt(input[i]);
        const low = hexToInt(input[i + 1]);

        if (high == null or low == null) {
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .ignore => {
                    i += 1;
                    continue;
                },
                .replace => {
                    try output.append(allocator, '?');
                    i += 2;
                    continue;
                },
                else => {
                    i += 2;
                    continue;
                },
            }
        }

        try output.append(allocator, (high.? << 4) | low.?);
        i += 2;
    }

    return .{
        .output = try output.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode bytes to hex string
pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
    _ = errors;
    const output = try allocator.alloc(u8, input.len * 2);
    for (input, 0..) |byte, i| {
        output[i * 2] = hex_chars[byte >> 4];
        output[i * 2 + 1] = hex_chars[byte & 0xF];
    }
    return .{
        .output = output,
        .chars_consumed = input.len,
    };
}

test "hex encode" {
    const result = try encode(std.testing.allocator, "Hi", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("4869", result.output);
}

test "hex decode" {
    const result = try decode(std.testing.allocator, "4869", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi", result.output);
}

test "hex decode uppercase" {
    const result = try decode(std.testing.allocator, "4869", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi", result.output);
}
