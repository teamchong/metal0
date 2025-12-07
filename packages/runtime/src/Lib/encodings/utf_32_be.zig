//! CPython source: Lib/encodings/utf_32_be.py
//!
//! UTF-32 Big Endian encoding. No BOM is added when encoding.
//!
//! Mirrors: CPython Lib/encodings/utf_32_be.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "utf-32-be";
pub const aliases = [_][]const u8{ "utf_32_be", "UTF-32BE" };

pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

/// Decode UTF-32-BE bytes to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var i: usize = 0;
    while (i + 3 < input.len) {
        const codepoint: u32 = (@as(u32, input[i]) << 24) |
            (@as(u32, input[i + 1]) << 16) |
            (@as(u32, input[i + 2]) << 8) |
            @as(u32, input[i + 3]);
        i += 4;

        if (codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF)) {
            switch (errors) {
                .strict => return error.UnicodeDecodeError,
                .replace => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
                .ignore => {},
                else => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
            }
            continue;
        }

        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch {
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

    if (i < input.len) {
        switch (errors) {
            .strict => return error.UnicodeDecodeError,
            .replace => try output.appendSlice(allocator, charmap.REPLACEMENT_CHAR_UTF8),
            .ignore => {},
            else => {},
        }
    }

    return .{
        .output = try output.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 string to UTF-32-BE bytes (no BOM)
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
                    try output.appendSlice(allocator, &[_]u8{ 0, 0, 0, '?' });
                    i += 1;
                    chars_consumed += 1;
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
                    try output.appendSlice(allocator, &[_]u8{ 0, 0, 0, '?' });
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

        const cp: u32 = codepoint;
        try output.appendSlice(allocator, &[_]u8{
            @truncate(cp >> 24),
            @truncate(cp >> 16),
            @truncate(cp >> 8),
            @truncate(cp),
        });
    }

    return .{
        .output = try output.toOwnedSlice(allocator),
        .chars_consumed = chars_consumed,
    };
}

test "utf32be decode" {
    const result = try decode(std.testing.allocator, "\x00\x00\x00A\x00\x00\x00B", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("AB", result.output);
}

test "utf32be encode" {
    const result = try encode(std.testing.allocator, "AB", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\x00\x00\x00A\x00\x00\x00B", result.output);
}
