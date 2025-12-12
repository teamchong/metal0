//! CPython source: Lib/encodings/gb18030.py
//!
//! Implements GB18030 encoding for Chinese text.
//! National standard covering all Unicode code points.
//! Uses 1, 2, or 4 byte sequences.
//!
//! Note: Full implementation requires ~30000+ mapping entries.
//! This provides the codec framework with structure.
//!
//! Mirrors: CPython Lib/encodings/gb18030.py

const std = @import("std");
const gbk = @import("gbk.zig");

pub const name = "gb18030";
pub const aliases = [_][]const u8{ "gb18030-2000" };

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

// GB18030 byte classification
fn isFirstByte(b: u8) bool {
    return b >= 0x81 and b <= 0xFE;
}

fn isSecondByte2Byte(b: u8) bool {
    return (b >= 0x40 and b <= 0x7E) or (b >= 0x80 and b <= 0xFE);
}

fn isSecondByte4Byte(b: u8) bool {
    return b >= 0x30 and b <= 0x39;
}

fn isThirdByte(b: u8) bool {
    return b >= 0x81 and b <= 0xFE;
}

fn isFourthByte(b: u8) bool {
    return b >= 0x30 and b <= 0x39;
}

// Convert 4-byte GB18030 to Unicode code point
fn decode4Byte(b1: u8, b2: u8, b3: u8, b4: u8) ?u21 {
    // GB18030 4-byte: linear mapping to Unicode BMP and supplementary planes
    // Formula: ((b1-0x81)*10 + (b2-0x30))*126 + (b3-0x81))*10 + (b4-0x30)
    const n1: u32 = b1 - 0x81;
    const n2: u32 = b2 - 0x30;
    const n3: u32 = b3 - 0x81;
    const n4: u32 = b4 - 0x30;

    const linear = ((n1 * 10 + n2) * 126 + n3) * 10 + n4;

    // Map linear value to Unicode
    // This is simplified - full mapping requires lookup tables
    if (linear <= 0x10FFFF) {
        return @intCast(linear);
    }
    return null;
}

/// Decode GB18030 to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        const b1 = input[i];

        if (b1 < 0x80) {
            // ASCII
            try result.append(allocator, b1);
            i += 1;
        } else if (isFirstByte(b1)) {
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
                i += 1;
                continue;
            }

            const b2 = input[i + 1];

            if (isSecondByte4Byte(b2)) {
                // 4-byte sequence
                if (i + 3 >= input.len) {
                    if (mode == .strict) return error.IncompleteSequence;
                    try result.appendSlice(allocator, "\xEF\xBF\xBD");
                    i += 1;
                    continue;
                }

                const b3 = input[i + 2];
                const b4 = input[i + 3];

                if (!isThirdByte(b3) or !isFourthByte(b4)) {
                    if (mode == .strict) return error.InvalidSequence;
                    try result.appendSlice(allocator, "\xEF\xBF\xBD");
                    i += 1;
                    continue;
                }

                if (decode4Byte(b1, b2, b3, b4)) |cp| {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(cp, &buf) catch {
                        try result.appendSlice(allocator, "\xEF\xBF\xBD");
                        i += 4;
                        continue;
                    };
                    try result.appendSlice(allocator, buf[0..len]);
                } else {
                    if (mode == .strict) return error.InvalidSequence;
                    try result.appendSlice(allocator, "\xEF\xBF\xBD");
                }
                i += 4;
            } else if (isSecondByte2Byte(b2)) {
                // 2-byte sequence - use GBK decoding
                const gbk_mode: gbk.ErrorMode = switch (mode) {
                    .strict => .strict,
                    .replace => .replace,
                    .ignore => .ignore,
                    .xmlcharrefreplace => .xmlcharrefreplace,
                    .backslashreplace => .backslashreplace,
                };
                const gbk_result = try gbk.decode(allocator, input[i .. i + 2], gbk_mode);
                defer allocator.free(gbk_result.output);
                try result.appendSlice(allocator, gbk_result.output);
                i += 2;
            } else {
                if (mode == .strict) return error.InvalidSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
                i += 1;
            }
        } else {
            if (mode == .strict) return error.InvalidByte;
            try result.appendSlice(allocator, "\xEF\xBF\xBD");
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to GB18030
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII
            try result.append(allocator, @intCast(cp));
        } else {
            // For non-ASCII, would need full GBK/GB18030 reverse mapping
            // Use replacement for now
            if (mode == .strict) return error.UnencodableCharacter;
            try result.append(allocator, '?');
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(allocator),
        .chars_consumed = input.len,
    };
}

test "gb18030 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "gb18030 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
