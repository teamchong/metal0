//! CPython source: Lib/encodings/raw_unicode_escape.py
//!
//! Implements Python's raw unicode escape encoding which handles:
//! - \uXXXX for BMP characters
//! - \UXXXXXXXX for non-BMP characters
//! Unlike unicode_escape, this does NOT process other escape sequences.
//!
//! Mirrors: CPython Lib/encodings/raw_unicode_escape.py

const std = @import("std");

pub const name = "raw-unicode-escape";
pub const aliases = [_][]const u8{ "raw_unicode_escape", "rawunicodeescape" };

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

/// Decode raw unicode escape sequences to UTF-8
/// Handles \uXXXX and \UXXXXXXXX sequences only
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (i + 1 < input.len and input[i] == '\\') {
            if (input[i + 1] == 'u' and i + 5 < input.len) {
                // \uXXXX - 4 hex digits
                const hex = input[i + 2 .. i + 6];
                if (parseHex4(hex)) |codepoint| {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch {
                        if (mode == .strict) return error.InvalidCodepoint;
                        try result.append(0xFFFD & 0xFF); // replacement char
                        i += 6;
                        continue;
                    };
                    try result.appendSlice(buf[0..len]);
                    i += 6;
                    continue;
                }
            } else if (input[i + 1] == 'U' and i + 9 < input.len) {
                // \UXXXXXXXX - 8 hex digits
                const hex = input[i + 2 .. i + 10];
                if (parseHex8(hex)) |codepoint| {
                    if (codepoint <= 0x10FFFF) {
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch {
                            if (mode == .strict) return error.InvalidCodepoint;
                            try result.appendSlice("\xEF\xBF\xBD"); // U+FFFD
                            i += 10;
                            continue;
                        };
                        try result.appendSlice(buf[0..len]);
                        i += 10;
                        continue;
                    }
                }
            }
        }
        // Not an escape sequence, copy as-is
        try result.append(input[i]);
        i += 1;
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to raw unicode escape format
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = mode;
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII - output directly
            try result.append(@intCast(cp));
        } else if (cp <= 0xFFFF) {
            // BMP - use \uXXXX
            try result.appendSlice("\\u");
            var buf: [4]u8 = undefined;
            _ = std.fmt.bufPrint(&buf, "{x:0>4}", .{cp}) catch unreachable;
            try result.appendSlice(&buf);
        } else {
            // Non-BMP - use \UXXXXXXXX
            try result.appendSlice("\\U");
            var buf: [8]u8 = undefined;
            _ = std.fmt.bufPrint(&buf, "{x:0>8}", .{cp}) catch unreachable;
            try result.appendSlice(&buf);
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(),
        .chars_consumed = input.len,
    };
}

fn parseHex4(hex: []const u8) ?u16 {
    if (hex.len != 4) return null;
    var result: u16 = 0;
    for (hex) |c| {
        const digit: u16 = switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => return null,
        };
        result = result * 16 + digit;
    }
    return result;
}

fn parseHex8(hex: []const u8) ?u32 {
    if (hex.len != 8) return null;
    var result: u32 = 0;
    for (hex) |c| {
        const digit: u32 = switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => return null,
        };
        result = result * 16 + digit;
    }
    return result;
}

test "raw_unicode_escape decode basic" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "raw_unicode_escape decode \\u escape" {
    const result = try decode(std.testing.allocator, "\\u0041\\u0042", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("AB", result.output);
}

test "raw_unicode_escape decode \\U escape" {
    const result = try decode(std.testing.allocator, "\\U0001F600", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xF0\x9F\x98\x80", result.output); // U+1F600 grinning face
}

test "raw_unicode_escape encode" {
    const result = try encode(std.testing.allocator, "A\xC3\xA9", .strict); // "Aé"
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("A\\u00e9", result.output);
}
