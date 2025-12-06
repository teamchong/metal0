//! Python 'base64' Codec
//!
//! Base64 codec - converts bytes to/from base64 representation.
//!
//! Mirrors: CPython Lib/encodings/base64_codec.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "base64";
pub const aliases = [_][]const u8{ "base64_codec", "base-64" };

pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

const base64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Build decode table at comptime
fn buildDecodeTable() [256]?u8 {
    var table: [256]?u8 = .{null} ** 256;
    for (base64_alphabet, 0..) |c, i| {
        table[c] = @intCast(i);
    }
    return table;
}

const decode_table = buildDecodeTable();

/// Decode base64 string to bytes
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var buffer: u32 = 0;
    var bits: u5 = 0;
    var padding: u8 = 0;

    for (input) |c| {
        // Skip whitespace
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') continue;
        // Handle padding
        if (c == '=') {
            padding += 1;
            continue;
        }

        const val = decode_table[c];
        if (val == null) {
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .ignore => continue,
                .replace => continue,
                else => continue,
            }
        }

        buffer = (buffer << 6) | val.?;
        bits += 6;

        if (bits >= 8) {
            bits -= 8;
            try output.append(allocator, @truncate(buffer >> bits));
        }
    }

    return .{
        .output = try output.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode bytes to base64 string
pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
    _ = errors;
    const out_len = ((input.len + 2) / 3) * 4;
    var output = try allocator.alloc(u8, out_len);

    var i: usize = 0;
    var o: usize = 0;

    while (i + 2 < input.len) {
        const n: u24 = (@as(u24, input[i]) << 16) | (@as(u24, input[i + 1]) << 8) | input[i + 2];
        output[o] = base64_alphabet[(n >> 18) & 0x3F];
        output[o + 1] = base64_alphabet[(n >> 12) & 0x3F];
        output[o + 2] = base64_alphabet[(n >> 6) & 0x3F];
        output[o + 3] = base64_alphabet[n & 0x3F];
        i += 3;
        o += 4;
    }

    // Handle remaining bytes
    if (i < input.len) {
        var n: u24 = @as(u24, input[i]) << 16;
        if (i + 1 < input.len) {
            n |= @as(u24, input[i + 1]) << 8;
        }
        output[o] = base64_alphabet[(n >> 18) & 0x3F];
        output[o + 1] = base64_alphabet[(n >> 12) & 0x3F];
        if (i + 1 < input.len) {
            output[o + 2] = base64_alphabet[(n >> 6) & 0x3F];
        } else {
            output[o + 2] = '=';
        }
        output[o + 3] = '=';
    }

    return .{
        .output = output,
        .chars_consumed = input.len,
    };
}

test "base64 encode" {
    const result = try encode(std.testing.allocator, "Hi", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("SGk=", result.output);
}

test "base64 decode" {
    const result = try decode(std.testing.allocator, "SGk=", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi", result.output);
}

test "base64 roundtrip" {
    const original = "Hello, World!";
    const encoded = try encode(std.testing.allocator, original, .strict);
    defer std.testing.allocator.free(encoded.output);
    const decoded = try decode(std.testing.allocator, encoded.output, .strict);
    defer std.testing.allocator.free(decoded.output);
    try std.testing.expectEqualStrings(original, decoded.output);
}
