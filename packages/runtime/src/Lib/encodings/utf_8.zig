//! Python 'utf-8' Codec
//!
//! UTF-8 is the default encoding in Python 3 and the native string encoding in Zig.
//! This codec mostly passes through data, validating UTF-8 sequences.
//!
//! Mirrors: CPython Lib/encodings/utf_8.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "utf-8";
pub const aliases = [_][]const u8{ "utf8", "utf_8", "U8", "UTF", "cp65001" };

/// Re-export types
pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

/// Decode UTF-8 bytes to UTF-8 string (validates and copies)
/// This validates the input is proper UTF-8 and handles errors
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var i: usize = 0;
    while (i < input.len) {
        const byte = input[i];

        // Determine sequence length
        const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch {
            // Invalid start byte
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .ignore => {
                    i += 1;
                    continue;
                },
                .replace => {
                    try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8);
                    i += 1;
                    continue;
                },
                .surrogateescape => {
                    // Encode invalid byte as surrogate U+DC80-U+DCFF
                    const surrogate: u21 = 0xDC00 + @as(u21, byte);
                    var buf: [3]u8 = undefined;
                    const len = std.unicode.utf8Encode(surrogate, &buf) catch 0;
                    try output.appendSlice(allocator, buf[0..len]);
                    i += 1;
                    continue;
                },
                else => {
                    try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8);
                    i += 1;
                    continue;
                },
            }
        };

        // Check we have enough bytes
        if (i + seq_len > input.len) {
            // Truncated sequence
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .ignore => break,
                .replace => {
                    try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8);
                    break;
                },
                else => break,
            }
        }

        // Validate the sequence
        const slice = input[i..][0..seq_len];
        _ = std.unicode.utf8Decode(slice) catch {
            // Invalid sequence
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .ignore => {
                    i += 1;
                    continue;
                },
                .replace => {
                    try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8);
                    i += 1;
                    continue;
                },
                else => {
                    i += 1;
                    continue;
                },
            }
        };

        // Valid sequence - copy it
        try output.appendSlice(allocator, slice);
        i += seq_len;
    }

    return .{
        .output = try output.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 string to UTF-8 bytes (validates and copies)
/// For UTF-8, encoding is essentially a copy with validation
pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
    // For UTF-8 -> UTF-8, we just validate and copy
    // The decode function already handles all the validation
    const result = try decode(allocator, input, errors);
    return .{
        .output = result.output,
        .chars_consumed = result.bytes_consumed, // For UTF-8, bytes = chars conceptually
    };
}

/// Decode with BOM handling (UTF-8-SIG)
pub fn decodeWithBom(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    // Check for UTF-8 BOM (EF BB BF)
    const start: usize = if (input.len >= 3 and input[0] == 0xEF and input[1] == 0xBB and input[2] == 0xBF)
        3
    else
        0;

    return decode(allocator, input[start..], errors);
}

// Tests
test "utf8 decode valid" {
    const result = try decode(std.testing.allocator, "Hello, 世界!", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello, 世界!", result.output);
}

test "utf8 decode invalid strict" {
    // Invalid UTF-8 sequence (0x80 is not a valid start byte)
    const result = decode(std.testing.allocator, "Hello\x80World", .strict);
    try std.testing.expectError(error.UnicodeDecodeError, result);
}

test "utf8 decode invalid replace" {
    const result = try decode(std.testing.allocator, "Hi\x80!", .replace);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi\xef\xbf\xbd!", result.output);
}

test "utf8 decode with bom" {
    const result = try decodeWithBom(std.testing.allocator, "\xef\xbb\xbfHello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "utf8 encode valid" {
    const result = try encode(std.testing.allocator, "Hello, 世界!", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello, 世界!", result.output);
}
