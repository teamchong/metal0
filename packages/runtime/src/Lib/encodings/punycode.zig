//! Python 'punycode' Codec
//!
//! Implements Punycode encoding (RFC 3492) for internationalized domain names.
//! Encodes Unicode strings into ASCII-compatible encoding.
//!
//! Mirrors: CPython Lib/encodings/punycode.py

const std = @import("std");

pub const name = "punycode";
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

// Punycode parameters
const BASE: u32 = 36;
const TMIN: u32 = 1;
const TMAX: u32 = 26;
const SKEW: u32 = 38;
const DAMP: u32 = 700;
const INITIAL_BIAS: u32 = 72;
const INITIAL_N: u32 = 128;
const DELIMITER: u8 = '-';

fn adapt(delta_input: u32, num_points: u32, first_time: bool) u32 {
    var delta = if (first_time) delta_input / DAMP else delta_input / 2;
    delta += delta / num_points;

    var k: u32 = 0;
    while (delta > ((BASE - TMIN) * TMAX) / 2) {
        delta /= BASE - TMIN;
        k += BASE;
    }

    return k + (((BASE - TMIN + 1) * delta) / (delta + SKEW));
}

fn encodeDigit(d: u32) u8 {
    if (d < 26) {
        return @intCast('a' + d);
    } else {
        return @intCast('0' + (d - 26));
    }
}

fn decodeDigit(c: u8) ?u32 {
    if (c >= 'a' and c <= 'z') return c - 'a';
    if (c >= 'A' and c <= 'Z') return c - 'A';
    if (c >= '0' and c <= '9') return 26 + (c - '0');
    return null;
}

/// Decode Punycode to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    _ = mode;
    var result = std.ArrayList(u21).init(allocator);
    defer result.deinit();

    // Find the last delimiter
    var basic_end: usize = 0;
    for (input, 0..) |c, i| {
        if (c == DELIMITER) basic_end = i;
    }

    // Copy basic ASCII characters
    for (input[0..basic_end]) |c| {
        if (c >= 0x80) return error.InvalidPunycode;
        try result.append(c);
    }

    var n: u32 = INITIAL_N;
    var bias: u32 = INITIAL_BIAS;
    var i: u32 = 0;

    var input_idx: usize = if (basic_end > 0) basic_end + 1 else 0;

    while (input_idx < input.len) {
        const old_i = i;
        var w: u32 = 1;
        var k: u32 = BASE;

        while (true) {
            if (input_idx >= input.len) return error.InvalidPunycode;

            const digit = decodeDigit(input[input_idx]) orelse return error.InvalidPunycode;
            input_idx += 1;

            if (digit > (std.math.maxInt(u32) - i) / w) return error.Overflow;
            i += digit * w;

            const t: u32 = if (k <= bias) TMIN else if (k >= bias + TMAX) TMAX else k - bias;

            if (digit < t) break;

            if (w > std.math.maxInt(u32) / (BASE - t)) return error.Overflow;
            w *= BASE - t;
            k += BASE;
        }

        const len: u32 = @intCast(result.items.len + 1);
        bias = adapt(i - old_i, len, old_i == 0);

        if (i / len > std.math.maxInt(u32) - n) return error.Overflow;
        n += i / len;
        i = i % len;

        // Insert codepoint at position i
        try result.insert(@intCast(i), @intCast(n));
        i += 1;
    }

    // Convert to UTF-8
    var utf8_result = std.ArrayList(u8).init(allocator);
    errdefer utf8_result.deinit();

    for (result.items) |cp| {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch return error.InvalidCodepoint;
        try utf8_result.appendSlice(buf[0..len]);
    }

    return DecodeResult{
        .output = try utf8_result.toOwnedSlice(),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to Punycode
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = mode;
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Collect codepoints
    var codepoints = std.ArrayList(u21).init(allocator);
    defer codepoints.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        try codepoints.append(cp);
    }

    // Output basic (ASCII) characters first
    var basic_count: u32 = 0;
    for (codepoints.items) |cp| {
        if (cp < 0x80) {
            try result.append(@intCast(cp));
            basic_count += 1;
        }
    }

    // Add delimiter if there were basic characters
    if (basic_count > 0) {
        try result.append(DELIMITER);
    }

    var n: u32 = INITIAL_N;
    var delta: u32 = 0;
    var bias: u32 = INITIAL_BIAS;
    var handled: u32 = basic_count;
    const total: u32 = @intCast(codepoints.items.len);

    while (handled < total) {
        // Find minimum codepoint >= n
        var m: u32 = std.math.maxInt(u32);
        for (codepoints.items) |cp| {
            if (cp >= n and cp < m) {
                m = cp;
            }
        }

        if (m - n > (std.math.maxInt(u32) - delta) / (handled + 1)) {
            return error.Overflow;
        }
        delta += (m - n) * (handled + 1);
        n = m;

        for (codepoints.items) |cp| {
            if (cp < n) {
                delta += 1;
                if (delta == 0) return error.Overflow;
            } else if (cp == n) {
                var q = delta;
                var k: u32 = BASE;

                while (true) {
                    const t: u32 = if (k <= bias) TMIN else if (k >= bias + TMAX) TMAX else k - bias;

                    if (q < t) break;

                    try result.append(encodeDigit(t + ((q - t) % (BASE - t))));
                    q = (q - t) / (BASE - t);
                    k += BASE;
                }

                try result.append(encodeDigit(q));
                bias = adapt(delta, handled + 1, handled == basic_count);
                delta = 0;
                handled += 1;
            }
        }

        delta += 1;
        n += 1;
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(),
        .chars_consumed = input.len,
    };
}

test "punycode encode ascii" {
    const result = try encode(std.testing.allocator, "hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("hello-", result.output);
}

test "punycode encode unicode" {
    // "münchen" -> "mnchen-3ya"
    const result = try encode(std.testing.allocator, "münchen", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("mnchen-3ya", result.output);
}

test "punycode decode ascii" {
    const result = try decode(std.testing.allocator, "hello-", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("hello", result.output);
}

test "punycode decode unicode" {
    const result = try decode(std.testing.allocator, "mnchen-3ya", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("münchen", result.output);
}

test "punycode roundtrip" {
    const original = "日本語";
    const encoded = try encode(std.testing.allocator, original, .strict);
    defer std.testing.allocator.free(encoded.output);

    const decoded = try decode(std.testing.allocator, encoded.output, .strict);
    defer std.testing.allocator.free(decoded.output);

    try std.testing.expectEqualStrings(original, decoded.output);
}
