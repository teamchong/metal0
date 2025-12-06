//! Python 'utf-32' Codec
//!
//! UTF-32 encoding with BOM detection on decode and BOM prefix on encode.
//!
//! Mirrors: CPython Lib/encodings/utf_32.py

const std = @import("std");
const charmap = @import("charmap.zig");

pub const name = "utf-32";
pub const aliases = [_][]const u8{ "utf_32", "UTF-32", "U32" };

pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

/// BOM constants
pub const BOM_LE = "\xff\xfe\x00\x00";
pub const BOM_BE = "\x00\x00\xfe\xff";

/// Decode UTF-32-LE bytes to UTF-8
fn decodeLe(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var i: usize = 0;
    while (i + 3 < input.len) {
        const codepoint: u32 = @as(u32, input[i]) |
            (@as(u32, input[i + 1]) << 8) |
            (@as(u32, input[i + 2]) << 16) |
            (@as(u32, input[i + 3]) << 24);
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

    // Handle trailing bytes
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

/// Decode UTF-32-BE bytes to UTF-8
fn decodeBe(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
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

/// Decode UTF-32 bytes to UTF-8 (auto-detects endianness from BOM)
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    if (input.len < 4) {
        return decodeLe(allocator, input, errors);
    }

    // Check for BOM
    if (input[0] == 0xFF and input[1] == 0xFE and input[2] == 0x00 and input[3] == 0x00) {
        return decodeLe(allocator, input[4..], errors);
    } else if (input[0] == 0x00 and input[1] == 0x00 and input[2] == 0xFE and input[3] == 0xFF) {
        return decodeBe(allocator, input[4..], errors);
    }

    // No BOM - assume LE
    return decodeLe(allocator, input, errors);
}

/// Encode UTF-8 string to UTF-32-LE bytes (with BOM prefix)
pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    // Add BOM
    try output.appendSlice(allocator, BOM_LE);

    var chars_consumed: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(input[i]) catch {
            switch (errors) {
                .strict => return error.UnicodeEncodeError,
                .replace => {
                    try output.appendSlice(allocator, &[_]u8{ '?', 0, 0, 0 });
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
                    try output.appendSlice(allocator, &[_]u8{ '?', 0, 0, 0 });
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

        // Write as UTF-32-LE
        const cp: u32 = codepoint;
        try output.appendSlice(allocator, &[_]u8{
            @truncate(cp),
            @truncate(cp >> 8),
            @truncate(cp >> 16),
            @truncate(cp >> 24),
        });
    }

    return .{
        .output = try output.toOwnedSlice(allocator),
        .chars_consumed = chars_consumed,
    };
}

test "utf32 decode with le bom" {
    const result = try decode(std.testing.allocator, "\xff\xfe\x00\x00H\x00\x00\x00i\x00\x00\x00", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hi", result.output);
}

test "utf32 encode" {
    const result = try encode(std.testing.allocator, "A", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xff\xfe\x00\x00A\x00\x00\x00", result.output);
}
