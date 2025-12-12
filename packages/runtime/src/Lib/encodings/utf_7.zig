//! CPython source: Lib/encodings/utf_7.py
//!
//! Implements UTF-7 encoding (RFC 2152) - a 7-bit safe Unicode encoding.
//! Uses modified Base64 for non-ASCII characters.
//!
//! Mirrors: CPython Lib/encodings/utf_7.py

const std = @import("std");

pub const name = "utf-7";
pub const aliases = [_][]const u8{ "utf7", "utf_7" };

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

// UTF-7 direct characters (can be used without encoding)
fn isDirectChar(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9' => true,
        '\'', '(', ')', ',', '-', '.', '/', ':', '?' => true,
        ' ', '\t', '\r', '\n' => true,
        else => false,
    };
}

// Modified Base64 alphabet for UTF-7
const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64Decode(c: u8) ?u6 {
    return switch (c) {
        'A'...'Z' => @intCast(c - 'A'),
        'a'...'z' => @intCast(c - 'a' + 26),
        '0'...'9' => @intCast(c - '0' + 52),
        '+' => 62,
        '/' => 63,
        else => null,
    };
}

/// Decode UTF-7 to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    _ = mode;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '+') {
            if (i + 1 < input.len and input[i + 1] == '-') {
                // +- encodes literal +
                try result.append(allocator, '+');
                i += 2;
                continue;
            }

            // Start of Base64 encoded sequence
            i += 1;
            var bits: u32 = 0;
            var bit_count: u5 = 0;

            while (i < input.len) {
                const c = input[i];
                if (c == '-') {
                    i += 1;
                    break;
                }

                const val = base64Decode(c) orelse break;
                i += 1;

                bits = (bits << 6) | val;
                bit_count += 6;

                // Extract 16-bit Unicode values
                while (bit_count >= 16) {
                    bit_count -= 16;
                    const codepoint: u16 = @intCast((bits >> bit_count) & 0xFFFF);

                    // Convert to UTF-8
                    if (codepoint < 0x80) {
                        try result.append(allocator, @intCast(codepoint));
                    } else if (codepoint < 0x800) {
                        try result.append(allocator, @intCast(0xC0 | (codepoint >> 6)));
                        try result.append(allocator, @intCast(0x80 | (codepoint & 0x3F)));
                    } else {
                        try result.append(allocator, @intCast(0xE0 | (codepoint >> 12)));
                        try result.append(allocator, @intCast(0x80 | ((codepoint >> 6) & 0x3F)));
                        try result.append(allocator, @intCast(0x80 | (codepoint & 0x3F)));
                    }
                }
            }
        } else {
            // Direct character
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to UTF-7
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = mode;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];

        if (c < 0x80 and isDirectChar(c)) {
            try result.append(allocator, c);
            i += 1;
        } else if (c == '+') {
            try result.appendSlice(allocator, "+-");
            i += 1;
        } else {
            // Need to encode as Base64
            try result.append(allocator, '+');

            var bits: u32 = 0;
            var bit_count: u5 = 0;

            while (i < input.len) {
                // Decode UTF-8 to get codepoint
                const byte0 = input[i];
                var codepoint: u21 = undefined;
                var bytes_used: usize = 1;

                if (byte0 < 0x80) {
                    if (isDirectChar(byte0)) break;
                    codepoint = byte0;
                } else if (byte0 < 0xE0) {
                    if (i + 1 >= input.len) break;
                    codepoint = (@as(u21, byte0 & 0x1F) << 6) | (input[i + 1] & 0x3F);
                    bytes_used = 2;
                } else if (byte0 < 0xF0) {
                    if (i + 2 >= input.len) break;
                    codepoint = (@as(u21, byte0 & 0x0F) << 12) |
                        (@as(u21, input[i + 1] & 0x3F) << 6) |
                        (input[i + 2] & 0x3F);
                    bytes_used = 3;
                } else {
                    if (i + 3 >= input.len) break;
                    codepoint = (@as(u21, byte0 & 0x07) << 18) |
                        (@as(u21, input[i + 1] & 0x3F) << 12) |
                        (@as(u21, input[i + 2] & 0x3F) << 6) |
                        (input[i + 3] & 0x3F);
                    bytes_used = 4;
                }

                i += bytes_used;

                // For BMP characters, encode as 16-bit
                if (codepoint <= 0xFFFF) {
                    bits = (bits << 16) | @as(u32, @intCast(codepoint));
                    bit_count += 16;
                } else {
                    // Surrogate pair for non-BMP
                    const adjusted = codepoint - 0x10000;
                    const high: u16 = @intCast(0xD800 + (adjusted >> 10));
                    const low: u16 = @intCast(0xDC00 + (adjusted & 0x3FF));
                    bits = (bits << 16) | high;
                    bit_count += 16;

                    // Output accumulated bits if needed
                    while (bit_count >= 6) {
                        bit_count -= 6;
                        try result.append(allocator, base64_chars[@intCast((bits >> bit_count) & 0x3F)]);
                    }

                    bits = (bits << 16) | low;
                    bit_count += 16;
                }

                // Output complete 6-bit groups
                while (bit_count >= 6) {
                    bit_count -= 6;
                    try result.append(allocator, base64_chars[@intCast((bits >> bit_count) & 0x3F)]);
                }
            }

            // Output remaining bits with padding
            if (bit_count > 0) {
                bits <<= @intCast(6 - bit_count);
                try result.append(allocator, base64_chars[@intCast(bits & 0x3F)]);
            }

            try result.append(allocator, '-');
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(allocator),
        .chars_consumed = input.len,
    };
}

test "utf7 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "utf7 decode plus" {
    const result = try decode(std.testing.allocator, "A+-B", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("A+B", result.output);
}

test "utf7 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "utf7 encode plus" {
    const result = try encode(std.testing.allocator, "A+B", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("A+-B", result.output);
}
