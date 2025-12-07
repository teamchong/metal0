//! CPython source: Lib/encodings/quopri_codec.py
//!
//! Implements Python's quoted-printable encoding for email.
//! Encodes non-printable characters as =XX hex sequences.
//!
//! Mirrors: CPython Lib/encodings/quopri_codec.py

const std = @import("std");

pub const name = "quopri";
pub const aliases = [_][]const u8{ "quopri_codec", "quoted_printable", "quotedprintable" };

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

/// Decode quoted-printable data
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '=') {
            // Soft line break
            if (i + 1 < input.len and input[i + 1] == '\n') {
                i += 2;
                continue;
            }
            if (i + 2 < input.len and input[i + 1] == '\r' and input[i + 2] == '\n') {
                i += 3;
                continue;
            }
            // Hex encoded byte
            if (i + 2 < input.len) {
                if (parseHexByte(input[i + 1], input[i + 2])) |byte| {
                    try result.append(byte);
                    i += 3;
                    continue;
                }
            }
            // Invalid escape
            if (mode == .strict) {
                return error.InvalidQuotedPrintable;
            }
            try result.append('=');
            i += 1;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(),
        .bytes_consumed = input.len,
    };
}

/// Encode data to quoted-printable format
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = mode;
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var line_len: usize = 0;

    for (input) |c| {
        // Check if we need a soft line break (max 76 chars per line)
        if (line_len >= 73) {
            try result.appendSlice("=\r\n");
            line_len = 0;
        }

        if (c == '\r' or c == '\n') {
            // Preserve line endings
            try result.append(c);
            if (c == '\n') line_len = 0;
        } else if (c == '=' or c < 32 or c > 126) {
            // Encode special characters and non-printables
            try result.append('=');
            try result.append(hexDigit(c >> 4));
            try result.append(hexDigit(c & 0x0F));
            line_len += 3;
        } else {
            // Printable ASCII
            try result.append(c);
            line_len += 1;
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(),
        .chars_consumed = input.len,
    };
}

fn parseHexByte(h1: u8, h2: u8) ?u8 {
    const d1 = hexValue(h1) orelse return null;
    const d2 = hexValue(h2) orelse return null;
    return (d1 << 4) | d2;
}

fn hexValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => c - 'A' + 10,
        'a'...'f' => c - 'a' + 10,
        else => null,
    };
}

fn hexDigit(val: u8) u8 {
    const v = val & 0x0F;
    return if (v < 10) '0' + v else 'A' + (v - 10);
}

test "quopri decode simple" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "quopri decode hex escape" {
    const result = try decode(std.testing.allocator, "=3D", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("=", result.output);
}

test "quopri decode soft line break" {
    const result = try decode(std.testing.allocator, "Hello=\nWorld", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("HelloWorld", result.output);
}

test "quopri encode" {
    const result = try encode(std.testing.allocator, "Hello=World", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello=3DWorld", result.output);
}

test "quopri roundtrip" {
    const original = "Test with = and \x00 bytes";
    const encoded = try encode(std.testing.allocator, original, .strict);
    defer std.testing.allocator.free(encoded.output);

    const decoded = try decode(std.testing.allocator, encoded.output, .strict);
    defer std.testing.allocator.free(decoded.output);

    try std.testing.expectEqualStrings(original, decoded.output);
}
