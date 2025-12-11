//! CPython source: Lib/encodings/iso2022_kr.py
//!
//! Implements ISO-2022-KR encoding for Korean text.
//! 7-bit encoding using escape sequences to switch character sets.
//!
//! Escape sequences:
//!   ESC $ ) C  - KS X 1001 (Korean)
//!   SI (0x0F)  - Shift In (ASCII)
//!   SO (0x0E)  - Shift Out (Korean)
//!
//! Mirrors: CPython Lib/encodings/iso2022_kr.py

const std = @import("std");
const euc_kr = @import("euc_kr.zig");

pub const name = "iso2022_kr";
pub const aliases = [_][]const u8{ "csiso2022kr", "iso2022kr", "iso-2022-kr" };

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

const ESC = 0x1B;
const SI = 0x0F; // Shift In - return to ASCII
const SO = 0x0E; // Shift Out - switch to KS X 1001

/// Decode ISO-2022-KR to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var in_korean = false;
    var i: usize = 0;

    // Skip designator sequence if present: ESC $ ) C
    if (input.len >= 4 and input[0] == ESC and input[1] == '$' and input[2] == ')' and input[3] == 'C') {
        i = 4;
    }

    while (i < input.len) {
        const b = input[i];

        if (b == SI) {
            // Shift In - return to ASCII
            in_korean = false;
            i += 1;
        } else if (b == SO) {
            // Shift Out - switch to Korean
            in_korean = true;
            i += 1;
        } else if (b == ESC) {
            // Skip escape sequence
            if (i + 3 < input.len and input[i + 1] == '$' and input[i + 2] == ')' and input[i + 3] == 'C') {
                i += 4;
            } else {
                if (mode == .strict) return error.InvalidSequence;
                try result.appendSlice("\xEF\xBF\xBD");
                i += 1;
            }
        } else if (in_korean) {
            // KS X 1001 double-byte
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                try result.appendSlice("\xEF\xBF\xBD");
                i += 1;
                continue;
            }

            const b1 = input[i];
            const b2 = input[i + 1];

            // Convert to EUC-KR by adding 0x80
            const euc_bytes = [_]u8{ b1 | 0x80, b2 | 0x80 };
            const euc_mode: euc_kr.ErrorMode = switch (mode) {
                .strict => .strict,
                .replace => .replace,
                .ignore => .ignore,
                .xmlcharrefreplace => .xmlcharrefreplace,
                .backslashreplace => .backslashreplace,
            };
            const euc_result = try euc_kr.decode(allocator, &euc_bytes, euc_mode);
            defer allocator.free(euc_result.output);
            try result.appendSlice(euc_result.output);
            i += 2;
        } else {
            // ASCII mode
            if (b < 0x80) {
                try result.append(b);
            } else {
                if (mode == .strict) return error.InvalidByte;
                try result.appendSlice("\xEF\xBF\xBD");
            }
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to ISO-2022-KR
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Start with designator sequence
    try result.appendSlice(&[_]u8{ ESC, '$', ')', 'C' });

    var in_korean = false;

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // Switch to ASCII if not already
            if (in_korean) {
                try result.append(SI);
                in_korean = false;
            }
            try result.append(@intCast(cp));
        } else {
            // Use CJK mapping tables for KS X 1001 encoding
            const cjk = @import("cjk_mappings.zig");
            if (cjk.encodeKsx1001(cp)) |ks_code| {
                // Switch to Korean if not already
                if (!in_korean) {
                    try result.append(SO);
                    in_korean = true;
                }
                // Output without high bit (ISO-2022 uses 7-bit)
                try result.append(@intCast(ks_code >> 8));
                try result.append(@intCast(ks_code & 0xFF));
            } else {
                // No mapping available
                if (mode == .strict) return error.UnencodableCharacter;
                if (in_korean) {
                    try result.append(SI);
                    in_korean = false;
                }
                try result.append('?');
            }
        }
    }

    // End in ASCII mode
    if (in_korean) {
        try result.append(SI);
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(),
        .chars_consumed = input.len,
    };
}

test "iso2022_kr decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "iso2022_kr encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    // Starts with designator ESC $ ) C then ASCII
    try std.testing.expectEqualStrings("\x1B$)CHello", result.output);
}
