//! CPython source: Lib/encodings/uu_codec.py
//!
//! Implements Python's uuencode/uudecode encoding.
//! Used for encoding binary data in ASCII text format.
//!
//! Mirrors: CPython Lib/encodings/uu_codec.py

const std = @import("std");

pub const name = "uu";
pub const aliases = [_][]const u8{"uu_codec"};

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

/// Decode uuencoded data to binary
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    _ = mode;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var lines = std.mem.splitScalar(u8, input, '\n');
    var in_body = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trimRight(u8, line, " \r");

        // Skip empty lines
        if (trimmed.len == 0) continue;

        // Handle begin line
        if (std.mem.startsWith(u8, trimmed, "begin ")) {
            in_body = true;
            continue;
        }

        // Handle end line
        if (std.mem.eql(u8, trimmed, "end")) {
            break;
        }

        // Skip if not in body
        if (!in_body) continue;

        // Decode data line
        if (trimmed.len == 0) continue;

        // First char indicates line length
        const line_len = if (trimmed[0] >= 32) trimmed[0] - 32 else continue;
        if (line_len == 0) continue; // End of data marker

        const data = trimmed[1..];
        var i: usize = 0;
        var decoded: usize = 0;

        while (decoded < line_len and i + 3 < data.len) {
            // Decode 4 uuencoded chars to 3 bytes
            const c0 = decodeChar(data[i]);
            const c1 = decodeChar(data[i + 1]);
            const c2 = decodeChar(data[i + 2]);
            const c3 = decodeChar(data[i + 3]);

            if (decoded < line_len) {
                try result.append(allocator, @truncate((c0 << 2) | (c1 >> 4)));
                decoded += 1;
            }
            if (decoded < line_len) {
                try result.append(allocator, @truncate((c1 << 4) | (c2 >> 2)));
                decoded += 1;
            }
            if (decoded < line_len) {
                try result.append(allocator, @truncate((c2 << 6) | c3));
                decoded += 1;
            }

            i += 4;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode binary data to uuencode format
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = mode;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    // Add begin line
    try result.appendSlice(allocator, "begin 644 data\n");

    var offset: usize = 0;
    while (offset < input.len) {
        const remaining = input.len - offset;
        const line_len: u8 = @intCast(@min(remaining, 45));

        // Length character
        try result.append(allocator, line_len + 32);

        // Encode up to 45 bytes per line
        var i: usize = 0;
        while (i < line_len) {
            const b0: u8 = input[offset + i];
            const b1: u8 = if (i + 1 < line_len) input[offset + i + 1] else 0;
            const b2: u8 = if (i + 2 < line_len) input[offset + i + 2] else 0;

            try result.append(allocator, encodeChar(b0 >> 2));
            try result.append(allocator, encodeChar(((b0 & 0x03) << 4) | (b1 >> 4)));
            try result.append(allocator, encodeChar(((b1 & 0x0F) << 2) | (b2 >> 6)));
            try result.append(allocator, encodeChar(b2 & 0x3F));

            i += 3;
        }

        try result.append(allocator, '\n');
        offset += line_len;
    }

    // End marker (backtick = empty line)
    try result.appendSlice(allocator, "`\nend\n");

    return EncodeResult{
        .output = try result.toOwnedSlice(allocator),
        .chars_consumed = input.len,
    };
}

fn decodeChar(c: u8) u8 {
    if (c == '`' or c == ' ') return 0;
    return if (c >= 32) c - 32 else 0;
}

fn encodeChar(val: u8) u8 {
    const v = val & 0x3F;
    return if (v == 0) '`' else v + 32;
}

test "uu_codec encode" {
    const result = try encode(std.testing.allocator, "Cat", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expect(std.mem.startsWith(u8, result.output, "begin 644 data\n"));
    try std.testing.expect(std.mem.endsWith(u8, result.output, "\nend\n"));
}

test "uu_codec decode" {
    const encoded = "begin 644 data\n#0V%T\n`\nend\n";
    const result = try decode(std.testing.allocator, encoded, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Cat", result.output);
}

test "uu_codec roundtrip" {
    const original = "Hello, World!";
    const encoded = try encode(std.testing.allocator, original, .strict);
    defer std.testing.allocator.free(encoded.output);

    const decoded = try decode(std.testing.allocator, encoded.output, .strict);
    defer std.testing.allocator.free(decoded.output);

    try std.testing.expectEqualStrings(original, decoded.output);
}
