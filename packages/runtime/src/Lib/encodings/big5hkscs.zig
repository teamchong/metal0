//! CPython source: Lib/encodings/big5hkscs.py
//!
//! Implements Big5-HKSCS encoding for Traditional Chinese in Hong Kong.
//! Extension of Big5 with additional characters for Cantonese.
//!
//! Note: Full implementation requires ~4000+ additional mapping entries.
//! This provides the codec framework delegating to big5.
//!
//! Mirrors: CPython Lib/encodings/big5hkscs.py

const std = @import("std");
const big5 = @import("big5.zig");

pub const name = "big5hkscs";
pub const aliases = [_][]const u8{ "big5-hkscs", "hkscs" };

pub const DecodeResult = big5.DecodeResult;
pub const EncodeResult = big5.EncodeResult;
pub const ErrorMode = big5.ErrorMode;

// HKSCS extends Big5 with additional ranges
fn isLeadByte(b: u8) bool {
    return (b >= 0x81 and b <= 0xFE);
}

fn isTrailByte(b: u8) bool {
    return (b >= 0x40 and b <= 0x7E) or (b >= 0xA1 and b <= 0xFE);
}

/// Decode Big5-HKSCS to UTF-8
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
        } else if (isLeadByte(b1)) {
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
                i += 1;
                continue;
            }

            const b2 = input[i + 1];
            if (!isTrailByte(b2)) {
                if (mode == .strict) return error.InvalidSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
                i += 1;
                continue;
            }

            // Try Big5 decoding first
            const big5_result = try big5.decode(allocator, input[i .. i + 2], .replace);
            defer allocator.free(big5_result.output);

            // Check if it decoded to replacement char (unmapped)
            if (std.mem.eql(u8, big5_result.output, "\xEF\xBF\xBD")) {
                // HKSCS extension area - would need full mapping
                if (mode == .strict) return error.InvalidSequence;
                try result.appendSlice(allocator, "\xEF\xBF\xBD");
            } else {
                try result.appendSlice(allocator, big5_result.output);
            }
            i += 2;
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

/// Encode UTF-8 to Big5-HKSCS
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    // Big5-HKSCS encoding is compatible with Big5 for most characters
    return big5.encode(allocator, input, mode);
}

test "big5hkscs decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "big5hkscs encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
