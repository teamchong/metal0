//! CPython source: Lib/encodings/ascii.py
//!
//! ASCII is a 7-bit encoding where bytes 0x00-0x7F map directly to Unicode codepoints.
//! Bytes >= 0x80 are invalid in ASCII.
//!
//! Mirrors: CPython Lib/encodings/ascii.py

const std = @import("std");

pub const name = "ascii";
pub const aliases = [_][]const u8{ "646", "us-ascii" };

/// Decode ASCII bytes to UTF-8 string
/// ASCII is a subset of UTF-8, so valid ASCII bytes are already valid UTF-8
pub fn decode(input: []const u8, errors: ErrorHandler) !DecodeResult {
    var output = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer output.deinit();
    var bytes_consumed: usize = 0;

    for (input, 0..) |byte, i| {
        if (byte < 0x80) {
            // Valid ASCII - copy directly (ASCII is subset of UTF-8)
            try output.append(byte);
            bytes_consumed = i + 1;
        } else {
            // Invalid ASCII byte (>= 0x80)
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .ignore => {
                    // Skip the byte
                    bytes_consumed = i + 1;
                },
                .replace => {
                    // Replace with U+FFFD (replacement character) encoded as UTF-8
                    try output.appendSlice("\xEF\xBF\xBD");
                    bytes_consumed = i + 1;
                },
                .backslashreplace => {
                    // Replace with \xNN escape
                    var buf: [4]u8 = undefined;
                    const len = std.fmt.bufPrint(&buf, "\\x{x:0>2}", .{byte}) catch unreachable;
                    try output.appendSlice(len);
                    bytes_consumed = i + 1;
                },
            }
        }
    }

    return .{
        .output = try output.toOwnedSlice(),
        .bytes_consumed = bytes_consumed,
    };
}

/// Encode UTF-8 string to ASCII bytes
/// Only codepoints 0x00-0x7F can be encoded; others raise an error
pub fn encode(input: []const u8, errors: ErrorHandler) !EncodeResult {
    var output = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer output.deinit();
    var chars_consumed: usize = 0;

    var i: usize = 0;
    while (i < input.len) {
        const byte = input[i];

        if (byte < 0x80) {
            // Single-byte UTF-8 (ASCII) - copy directly
            try output.append(byte);
            chars_consumed += 1;
            i += 1;
        } else {
            // Multi-byte UTF-8 sequence - not encodable in ASCII
            const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;
            const codepoint = std.unicode.utf8Decode(input[i..@min(i + seq_len, input.len)]) catch 0xFFFD;

            switch (errors) {
                .strict => return error.UnicodeEncodeError,
                .ignore => {
                    // Skip the character
                    chars_consumed += 1;
                    i += seq_len;
                },
                .replace => {
                    // Replace with '?'
                    try output.append('?');
                    chars_consumed += 1;
                    i += seq_len;
                },
                .backslashreplace => {
                    // Replace with \uXXXX or \UXXXXXXXX escape
                    var buf: [12]u8 = undefined;
                    const len = if (codepoint <= 0xFFFF)
                        std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{codepoint}) catch unreachable
                    else
                        std.fmt.bufPrint(&buf, "\\U{x:0>8}", .{codepoint}) catch unreachable;
                    try output.appendSlice(len);
                    chars_consumed += 1;
                    i += seq_len;
                },
            }
        }
    }

    return .{
        .output = try output.toOwnedSlice(),
        .chars_consumed = chars_consumed,
    };
}

/// Error handling modes (matching Python's codec error handlers)
pub const ErrorHandler = enum {
    strict, // Raise exception on error
    ignore, // Ignore invalid bytes/characters
    replace, // Replace with replacement character
    backslashreplace, // Replace with backslash escape sequence
};

pub const DecodeResult = struct {
    output: []u8,
    bytes_consumed: usize,
};

pub const EncodeResult = struct {
    output: []u8,
    chars_consumed: usize,
};

/// CodecInfo for registration
pub const CodecInfo = struct {
    name: []const u8 = "ascii",
    encode_fn: *const fn ([]const u8, ErrorHandler) anyerror!EncodeResult = encode,
    decode_fn: *const fn ([]const u8, ErrorHandler) anyerror!DecodeResult = decode,
};

pub fn getregentry() CodecInfo {
    return .{};
}

// Tests
test "ascii decode valid" {
    const result = try decode("Hello, World!", .strict);
    defer std.heap.page_allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello, World!", result.output);
}

test "ascii decode invalid strict" {
    const result = decode("\x80\x81", .strict);
    try std.testing.expectError(error.UnicodeDecodeError, result);
}

test "ascii decode invalid replace" {
    const result = try decode("Hi\x80!", .replace);
    defer std.heap.page_allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi\xEF\xBF\xBD!", result.output);
}

test "ascii encode valid" {
    const result = try encode("Hello", .strict);
    defer std.heap.page_allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "ascii encode invalid strict" {
    const result = encode("Héllo", .strict);
    try std.testing.expectError(error.UnicodeEncodeError, result);
}
