//! Python 'cp949' Codec (Windows Code Page 949)
//!
//! Microsoft's extension of EUC-KR for Korean (Unified Hangul Code).
//! Also known as UHC or Extended Wansung.
//!
//! Note: Full implementation requires ~17000+ mapping entries.
//! This provides the codec framework delegating to euc_kr.
//!
//! Mirrors: CPython Lib/encodings/cp949.py

const std = @import("std");
const euc_kr = @import("euc_kr.zig");

pub const name = "cp949";
pub const aliases = [_][]const u8{ "949", "ms949", "uhc" };

pub const DecodeResult = euc_kr.DecodeResult;
pub const EncodeResult = euc_kr.EncodeResult;
pub const ErrorMode = euc_kr.ErrorMode;

// CP949 extends EUC-KR with additional lead byte range (0x81-0xA0)
fn isLeadByte(b: u8) bool {
    return b >= 0x81 and b <= 0xFE;
}

fn isTrailByte(b: u8) bool {
    return (b >= 0x41 and b <= 0x5A) or // A-Z
        (b >= 0x61 and b <= 0x7A) or // a-z
        (b >= 0x81 and b <= 0xFE); // Extended range
}

/// Decode CP949 to UTF-8
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

            // For EUC-KR compatible range, use EUC-KR decoding
            if (b1 >= 0xA1 and b1 <= 0xFE and b2 >= 0xA1 and b2 <= 0xFE) {
                const euc_result = try euc_kr.decode(allocator, input[i .. i + 2], mode);
                defer allocator.free(euc_result.output);
                try result.appendSlice(euc_result.output);
                i += 2;
                continue;
            }

            // CP949 extension area - would need full mapping table
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

/// Encode UTF-8 to CP949
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    // CP949 encoding is compatible with EUC-KR for most characters
    return euc_kr.encode(allocator, input, mode);
}

test "cp949 decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "cp949 encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}
