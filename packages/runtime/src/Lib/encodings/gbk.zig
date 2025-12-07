//! CPython source: Lib/encodings/gbk.py
//!
//! Implements GBK encoding for Simplified Chinese text.
//! GBK is an extension of GB2312 with additional characters.
//!
//! Note: Full implementation requires ~21000+ mapping entries.
//! This provides the codec framework with common characters.
//!
//! Mirrors: CPython Lib/encodings/gbk.py

const std = @import("std");
const gb2312 = @import("gb2312.zig");

pub const name = "gbk";
pub const aliases = [_][]const u8{ "936", "cp936", "ms936" };

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

// GBK extends GB2312 with additional lead/trail byte ranges
fn isLeadByte(b: u8) bool {
    return b >= 0x81 and b <= 0xFE;
}

fn isTrailByte(b: u8) bool {
    return (b >= 0x40 and b <= 0x7E) or (b >= 0x80 and b <= 0xFE);
}

/// Decode GBK to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        const b1 = input[i];

        if (b1 < 0x80) {
            // ASCII
            try result.append(b1);
            i += 1;
        } else if (isLeadByte(b1)) {
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice("\xEF\xBF\xBD");
                i += 1;
                continue;
            }

            const b2 = input[i + 1];
            if (!isTrailByte(b2)) {
                if (mode == .strict) return error.InvalidSequence;
                try result.appendSlice("\xEF\xBF\xBD");
                i += 1;
                continue;
            }

            // Try GB2312 mapping first (for compatible range)
            if (b1 >= 0xA1 and b1 <= 0xF7 and b2 >= 0xA1 and b2 <= 0xFE) {
                // In GB2312 range, delegate to GB2312
                const gb_result = try gb2312.decode(allocator, input[i .. i + 2], mode);
                defer allocator.free(gb_result.output);
                try result.appendSlice(gb_result.output);
                i += 2;
                continue;
            }

            // GBK-specific extensions would go here
            // For now, output replacement character
            if (mode == .strict) return error.InvalidSequence;
            try result.appendSlice("\xEF\xBF\xBD");
            i += 2;
        } else {
            if (mode == .strict) return error.InvalidByte;
            try result.appendSlice("\xEF\xBF\xBD");
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to GBK
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    // GBK is a superset of GB2312, so use GB2312 encode
    return gb2312.encode(allocator, input, mode);
}

test "gbk decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "gbk encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
