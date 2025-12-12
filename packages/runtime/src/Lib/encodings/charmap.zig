//! CPython source: Lib/encodings/charmap.py
//!
//! Provides the base infrastructure for single-byte character encodings
//! like cp1252, latin-1, iso-8859-*, etc.
//!
//! Each encoding provides a 256-entry decode table mapping bytes to Unicode codepoints,
//! and an encode table mapping Unicode codepoints back to bytes.
//!
//! Mirrors: CPython Lib/encodings/charmap.py

const std = @import("std");

/// Error handling modes (matching Python's codec error handlers)
pub const ErrorHandler = enum {
    strict, // Raise exception on error
    ignore, // Ignore invalid bytes/characters
    replace, // Replace with replacement character
    backslashreplace, // Replace with backslash escape sequence
    xmlcharrefreplace, // Replace with XML character reference
    surrogatepass, // Allow surrogates to pass through
    surrogateescape, // Encode errors as surrogates (for round-trip)
};

pub const DecodeResult = struct {
    output: []u8,
    bytes_consumed: usize,
};

pub const EncodeResult = struct {
    output: []u8,
    chars_consumed: usize,
};

/// Undefined codepoint marker (maps to U+FFFE which is a non-character)
pub const UNDEFINED: u21 = 0xFFFE;

/// Replacement character (U+FFFD) as UTF-8
pub const REPLACEMENT_CHAR_UTF8 = "\xEF\xBF\xBD";

/// Generate a charmap codec from a 256-entry decode table
/// The decode table maps each byte (0-255) to a Unicode codepoint
pub fn CharmapCodec(comptime decode_table: *const [256]u21, comptime codec_name: []const u8) type {
    return struct {
        const Self = @This();

        pub const name = codec_name;

        /// Decode bytes to UTF-8 string using the charmap
        pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
            var output: std.ArrayList(u8) = .{};
            errdefer output.deinit(allocator);

            for (input) |byte| {
                const codepoint = decode_table[byte];

                if (codepoint == UNDEFINED) {
                    // Undefined byte in this encoding
                    switch (errors) {
                        .strict => return error.UnicodeDecodeError,
                        .ignore => {},
                        .replace => try output.appendSlice(allocator, REPLACEMENT_CHAR_UTF8),
                        .backslashreplace => {
                            var buf: [4]u8 = undefined;
                            const len = std.fmt.bufPrint(&buf, "\\x{x:0>2}", .{byte}) catch unreachable;
                            try output.appendSlice(allocator, len);
                        },
                        .surrogateescape => {
                            // Encode as surrogate U+DC80-U+DCFF
                            const surrogate: u21 = 0xDC00 + @as(u21, byte);
                            var buf: [3]u8 = undefined;
                            const len = std.unicode.utf8Encode(surrogate, &buf) catch 0;
                            try output.appendSlice(allocator, buf[0..len]);
                        },
                        else => try output.appendSlice(allocator, REPLACEMENT_CHAR_UTF8),
                    }
                } else {
                    // Valid codepoint - encode as UTF-8
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(codepoint, &buf) catch 0;
                    try output.appendSlice(allocator, buf[0..len]);
                }
            }

            return .{
                .output = try output.toOwnedSlice(allocator),
                .bytes_consumed = input.len,
            };
        }

        /// Build reverse mapping (codepoint -> byte) at comptime
        fn buildEncodingTable() [65536]?u8 {
            var table: [65536]?u8 = .{null} ** 65536;
            for (decode_table, 0..) |codepoint, byte| {
                if (codepoint != UNDEFINED and codepoint < 65536) {
                    table[codepoint] = @intCast(byte);
                }
            }
            return table;
        }

        const encoding_table = buildEncodingTable();

        /// Encode UTF-8 string to bytes using the charmap
        pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
            var output: std.ArrayList(u8) = .{};
            errdefer output.deinit(allocator);
            var chars_consumed: usize = 0;

            var i: usize = 0;
            while (i < input.len) {
                const seq_len = std.unicode.utf8ByteSequenceLength(input[i]) catch 1;
                if (i + seq_len > input.len) break;

                const codepoint = std.unicode.utf8Decode(input[i..][0..seq_len]) catch 0xFFFD;
                chars_consumed += 1;
                i += seq_len;

                // Look up in encoding table
                if (codepoint < 65536) {
                    if (encoding_table[@intCast(codepoint)]) |byte| {
                        try output.append(allocator, byte);
                        continue;
                    }
                }

                // Codepoint not encodable in this charset
                switch (errors) {
                    .strict => return error.UnicodeEncodeError,
                    .ignore => {},
                    .replace => try output.append(allocator, '?'),
                    .backslashreplace => {
                        var buf: [12]u8 = undefined;
                        const len = if (codepoint <= 0xFF)
                            std.fmt.bufPrint(&buf, "\\x{x:0>2}", .{codepoint}) catch unreachable
                        else if (codepoint <= 0xFFFF)
                            std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{codepoint}) catch unreachable
                        else
                            std.fmt.bufPrint(&buf, "\\U{x:0>8}", .{codepoint}) catch unreachable;
                        try output.appendSlice(allocator, len);
                    },
                    .xmlcharrefreplace => {
                        var buf: [16]u8 = undefined;
                        const len = std.fmt.bufPrint(&buf, "&#{d};", .{codepoint}) catch unreachable;
                        try output.appendSlice(allocator, len);
                    },
                    .surrogateescape => {
                        // Handle surrogates U+DC80-U+DCFF -> original byte
                        if (codepoint >= 0xDC80 and codepoint <= 0xDCFF) {
                            try output.append(allocator, @intCast(codepoint - 0xDC00));
                        } else {
                            return error.UnicodeEncodeError;
                        }
                    },
                    else => try output.append(allocator, '?'),
                }
            }

            return .{
                .output = try output.toOwnedSlice(allocator),
                .chars_consumed = chars_consumed,
            };
        }
    };
}

/// Latin-1 / ISO-8859-1 decode table (identity mapping for 0-255)
pub const latin1_decode_table: [256]u21 = blk: {
    var table: [256]u21 = undefined;
    for (0..256) |i| {
        table[i] = @intCast(i);
    }
    break :blk table;
};

/// Create Latin-1 codec
pub const Latin1 = CharmapCodec(&latin1_decode_table, "latin-1");

// Test
test "charmap latin1 decode" {
    const result = try Latin1.decode(std.testing.allocator, "Hello\xa0World", .strict);
    defer std.testing.allocator.free(result.output);
    // \xa0 is non-breaking space, encodes as UTF-8: 0xC2 0xA0
    try std.testing.expectEqualStrings("Hello\xc2\xa0World", result.output);
}

test "charmap latin1 encode" {
    const result = try Latin1.encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
