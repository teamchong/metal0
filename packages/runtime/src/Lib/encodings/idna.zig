//! CPython source: Lib/encodings/idna.py
//!
//! Implements IDNA (Internationalized Domain Names in Applications) encoding.
//! Converts Unicode domain names to/from ASCII-compatible encoding using Punycode.
//!
//! Mirrors: CPython Lib/encodings/idna.py

const std = @import("std");
const punycode = @import("punycode.zig");

pub const name = "idna";
pub const aliases = [_][]const u8{};

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

const ACE_PREFIX = "xn--";

/// Decode IDNA domain to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var labels = std.mem.splitScalar(u8, input, '.');
    var first = true;

    while (labels.next()) |label| {
        if (!first) {
            try result.append('.');
        }
        first = false;

        // Check for ACE prefix
        if (std.mem.startsWith(u8, label, ACE_PREFIX)) {
            // Decode punycode
            const puny_result = try punycode.decode(allocator, label[ACE_PREFIX.len..], mode);
            defer allocator.free(puny_result.output);
            try result.appendSlice(puny_result.output);
        } else {
            // Already ASCII
            try result.appendSlice(label);
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 domain to IDNA
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Split by dots (including Unicode dots)
    var labels = std.ArrayList([]const u8).init(allocator);
    defer labels.deinit();

    var start: usize = 0;
    var i: usize = 0;
    while (i < input.len) {
        const byte = input[i];
        // Check for ASCII dot
        if (byte == '.') {
            try labels.append(input[start..i]);
            start = i + 1;
            i += 1;
            continue;
        }
        // Check for Unicode dots (U+3002, U+FF0E, U+FF61)
        if (i + 2 < input.len) {
            const b1 = input[i];
            const b2 = input[i + 1];
            const b3 = input[i + 2];
            // U+3002 IDEOGRAPHIC FULL STOP (E3 80 82)
            if (b1 == 0xE3 and b2 == 0x80 and b3 == 0x82) {
                try labels.append(input[start..i]);
                start = i + 3;
                i += 3;
                continue;
            }
            // U+FF0E FULLWIDTH FULL STOP (EF BC 8E)
            if (b1 == 0xEF and b2 == 0xBC and b3 == 0x8E) {
                try labels.append(input[start..i]);
                start = i + 3;
                i += 3;
                continue;
            }
            // U+FF61 HALFWIDTH IDEOGRAPHIC FULL STOP (EF BD A1)
            if (b1 == 0xEF and b2 == 0xBD and b3 == 0xA1) {
                try labels.append(input[start..i]);
                start = i + 3;
                i += 3;
                continue;
            }
        }
        i += 1;
    }
    if (start <= input.len) {
        try labels.append(input[start..]);
    }

    var first = true;
    for (labels.items) |label| {
        if (!first) {
            try result.append('.');
        }
        first = false;

        // Check if label is all ASCII
        var all_ascii = true;
        for (label) |c| {
            if (c >= 0x80) {
                all_ascii = false;
                break;
            }
        }

        if (all_ascii) {
            // Already ASCII - lowercase
            for (label) |c| {
                try result.append(std.ascii.toLower(c));
            }
        } else {
            // Need to encode with punycode
            try result.appendSlice(ACE_PREFIX);
            const puny_result = try punycode.encode(allocator, label, mode);
            defer allocator.free(puny_result.output);
            try result.appendSlice(puny_result.output);
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(),
        .chars_consumed = input.len,
    };
}

test "idna encode ascii" {
    const result = try encode(std.testing.allocator, "example.com", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("example.com", result.output);
}

test "idna encode unicode" {
    const result = try encode(std.testing.allocator, "münchen.de", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("xn--mnchen-3ya.de", result.output);
}

test "idna decode ascii" {
    const result = try decode(std.testing.allocator, "example.com", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("example.com", result.output);
}

test "idna decode punycode" {
    const result = try decode(std.testing.allocator, "xn--mnchen-3ya.de", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("münchen.de", result.output);
}

test "idna roundtrip" {
    const original = "日本語.jp";
    const encoded = try encode(std.testing.allocator, original, .strict);
    defer std.testing.allocator.free(encoded.output);

    const decoded = try decode(std.testing.allocator, encoded.output, .strict);
    defer std.testing.allocator.free(decoded.output);

    try std.testing.expectEqualStrings(original, decoded.output);
}
