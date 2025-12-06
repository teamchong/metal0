//! Python 'utf-16-le' Codec (Little Endian)
//!
//! UTF-16 Little Endian encoding. No BOM is added when encoding.
//!
//! Mirrors: CPython Lib/encodings/utf_16_le.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "utf-16-le";
pub const aliases = [_][]const u8{ "utf_16_le", "UTF-16LE" };

pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

/// Decode UTF-16-LE bytes to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var i: usize = 0;
    while (i + 1 < input.len) {
        const code_unit = @as(u16, input[i]) | (@as(u16, input[i + 1]) << 8);
        i += 2;

        var codepoint: u21 = undefined;

        // Check for surrogate pair
        if (code_unit >= 0xD800 and code_unit <= 0xDBFF) {
            // High surrogate - need low surrogate
            if (i + 1 >= input.len) {
                switch (errors) {
                    .strict => return error.UnicodeDecodeError,
                    .replace => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
                    .ignore => {},
                    else => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
                }
                break;
            }
            const low = @as(u16, input[i]) | (@as(u16, input[i + 1]) << 8);
            i += 2;

            if (low < 0xDC00 or low > 0xDFFF) {
                switch (errors) {
                    .strict => return error.UnicodeDecodeError,
                    .replace => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
                    .ignore => {},
                    else => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
                }
                continue;
            }

            codepoint = 0x10000 + ((@as(u21, code_unit) - 0xD800) << 10) + (@as(u21, low) - 0xDC00);
        } else if (code_unit >= 0xDC00 and code_unit <= 0xDFFF) {
            // Lone low surrogate
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .replace => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
                .ignore => {},
                else => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
            }
            continue;
        } else {
            codepoint = code_unit;
        }

        // Encode as UTF-8
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buf) catch {
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .replace => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
                .ignore => {},
                else => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
            }
            continue;
        };
        try output.appendSlice(allocator, buf[0..len]);
    }

    // Handle odd byte at end
    if (i < input.len) {
        switch (errors) {
            .strict => return error.UnicodeDecodeError,
            .replace => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
            .ignore => {},
            else => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
        }
    }

    return .{
        .output = try output.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 string to UTF-16-LE bytes
pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    var chars_consumed: usize = 0;

    var i: usize = 0;
    while (i < input.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(input[i]) catch {
            switch (errors) {
                .strict => return error.UnicodeEncodeError,
                .replace => {
                    try output.appendSlice(allocator, &[_]u8{ '?', 0 });
                    i += 1;
                    chars_consumed += 1;
                    continue;
                },
                .ignore => {
                    i += 1;
                    continue;
                },
                else => {
                    i += 1;
                    continue;
                },
            }
        };

        if (i + seq_len > input.len) break;

        const codepoint = std.unicode.utf8Decode(input[i..][0..seq_len]) catch {
            switch (errors) {
                .strict => return error.UnicodeEncodeError,
                .replace => {
                    try output.appendSlice(allocator, &[_]u8{ '?', 0 });
                    i += seq_len;
                    chars_consumed += 1;
                    continue;
                },
                else => {
                    i += seq_len;
                    continue;
                },
            }
        };

        i += seq_len;
        chars_consumed += 1;

        if (codepoint < 0x10000) {
            // BMP character - single code unit
            const cu: u16 = @intCast(codepoint);
            try output.appendSlice(allocator, &[_]u8{ @truncate(cu), @truncate(cu >> 8) });
        } else {
            // Supplementary - surrogate pair
            const adjusted = codepoint - 0x10000;
            const high: u16 = @intCast((adjusted >> 10) + 0xD800);
            const low: u16 = @intCast((adjusted & 0x3FF) + 0xDC00);
            try output.appendSlice(allocator, &[_]u8{ @truncate(high), @truncate(high >> 8) });
            try output.appendSlice(allocator, &[_]u8{ @truncate(low), @truncate(low >> 8) });
        }
    }

    return .{
        .output = try output.toOwnedSlice(allocator),
        .chars_consumed = chars_consumed,
    };
}

test "utf16le decode ascii" {
    const result = try decode(std.testing.allocator, "H\x00i\x00", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi", result.output);
}

test "utf16le encode ascii" {
    const result = try encode(std.testing.allocator, "Hi", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("H\x00i\x00", result.output);
}
