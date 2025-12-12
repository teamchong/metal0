//! CPython source: Lib/encodings/unicode_escape.py
//!
//! Implements Python's unicode escape encoding which handles:
//! - \xXX for single byte escapes
//! - \uXXXX for BMP characters
//! - \UXXXXXXXX for non-BMP characters
//! - Standard escape sequences: \n, \r, \t, \\, \', \"
//!
//! Mirrors: CPython Lib/encodings/unicode_escape.py

const std = @import("std");

pub const name = "unicode-escape";
pub const aliases = [_][]const u8{ "unicode_escape", "unicodeescape" };

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

/// Decode unicode escape sequences to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (i + 1 < input.len and input[i] == '\\') {
            const next = input[i + 1];
            switch (next) {
                '\\' => {
                    try result.append(allocator, '\\');
                    i += 2;
                },
                '\'' => {
                    try result.append(allocator, '\'');
                    i += 2;
                },
                '"' => {
                    try result.append(allocator, '"');
                    i += 2;
                },
                'n' => {
                    try result.append(allocator, '\n');
                    i += 2;
                },
                'r' => {
                    try result.append(allocator, '\r');
                    i += 2;
                },
                't' => {
                    try result.append(allocator, '\t');
                    i += 2;
                },
                'a' => {
                    try result.append(allocator, 0x07); // bell
                    i += 2;
                },
                'b' => {
                    try result.append(allocator, 0x08); // backspace
                    i += 2;
                },
                'f' => {
                    try result.append(allocator, 0x0C); // form feed
                    i += 2;
                },
                'v' => {
                    try result.append(allocator, 0x0B); // vertical tab
                    i += 2;
                },
                '0' => {
                    try result.append(allocator, 0x00); // null
                    i += 2;
                },
                'x' => {
                    // \xXX - 2 hex digits
                    if (i + 3 < input.len) {
                        if (parseHex2(input[i + 2 .. i + 4])) |byte| {
                            try result.append(allocator, byte);
                            i += 4;
                            continue;
                        }
                    }
                    if (mode == .strict) return error.InvalidEscape;
                    try result.append(allocator, '\\');
                    try result.append(allocator, 'x');
                    i += 2;
                },
                'u' => {
                    // \uXXXX - 4 hex digits
                    if (i + 5 < input.len) {
                        if (parseHex4(input[i + 2 .. i + 6])) |codepoint| {
                            var buf: [4]u8 = undefined;
                            const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch {
                                if (mode == .strict) return error.InvalidCodepoint;
                                try result.appendSlice(allocator, "\xEF\xBF\xBD"); // U+FFFD
                                i += 6;
                                continue;
                            };
                            try result.appendSlice(allocator, buf[0..len]);
                            i += 6;
                            continue;
                        }
                    }
                    if (mode == .strict) return error.InvalidEscape;
                    try result.append(allocator, '\\');
                    try result.append(allocator, 'u');
                    i += 2;
                },
                'U' => {
                    // \UXXXXXXXX - 8 hex digits
                    if (i + 9 < input.len) {
                        if (parseHex8(input[i + 2 .. i + 10])) |codepoint| {
                            if (codepoint <= 0x10FFFF) {
                                var buf: [4]u8 = undefined;
                                const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch {
                                    if (mode == .strict) return error.InvalidCodepoint;
                                    try result.appendSlice(allocator, "\xEF\xBF\xBD"); // U+FFFD
                                    i += 10;
                                    continue;
                                };
                                try result.appendSlice(allocator, buf[0..len]);
                                i += 10;
                                continue;
                            }
                        }
                    }
                    if (mode == .strict) return error.InvalidEscape;
                    try result.append(allocator, '\\');
                    try result.append(allocator, 'U');
                    i += 2;
                },
                'N' => {
                    // \N{name} - Unicode name (not implemented, pass through)
                    try result.append(allocator, '\\');
                    try result.append(allocator, 'N');
                    i += 2;
                },
                else => {
                    // Unknown escape - pass through
                    try result.append(allocator, '\\');
                    try result.append(allocator, next);
                    i += 2;
                },
            }
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to unicode escape format
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = mode;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        switch (cp) {
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            0x07 => try result.appendSlice(allocator, "\\a"),
            0x08 => try result.appendSlice(allocator, "\\b"),
            0x0C => try result.appendSlice(allocator, "\\f"),
            0x0B => try result.appendSlice(allocator, "\\v"),
            0x00 => try result.appendSlice(allocator, "\\0"),
            0x20...0x5B, 0x5D...0x7E => {
                // Printable ASCII (excluding backslash at 0x5C)
                try result.append(allocator, @intCast(cp));
            },
            else => {
                if (cp < 0x100) {
                    // \xXX
                    try result.appendSlice(allocator, "\\x");
                    var buf: [2]u8 = undefined;
                    _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{cp}) catch unreachable;
                    try result.appendSlice(allocator, &buf);
                } else if (cp <= 0xFFFF) {
                    // \uXXXX
                    try result.appendSlice(allocator, "\\u");
                    var buf: [4]u8 = undefined;
                    _ = std.fmt.bufPrint(&buf, "{x:0>4}", .{cp}) catch unreachable;
                    try result.appendSlice(allocator, &buf);
                } else {
                    // \UXXXXXXXX
                    try result.appendSlice(allocator, "\\U");
                    var buf: [8]u8 = undefined;
                    _ = std.fmt.bufPrint(&buf, "{x:0>8}", .{cp}) catch unreachable;
                    try result.appendSlice(allocator, &buf);
                }
            },
        }
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(allocator),
        .chars_consumed = input.len,
    };
}

fn parseHex2(hex: []const u8) ?u8 {
    if (hex.len != 2) return null;
    var result: u8 = 0;
    for (hex) |c| {
        const digit: u8 = switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => return null,
        };
        result = result * 16 + digit;
    }
    return result;
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

test "unicode_escape decode basic" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "unicode_escape decode escapes" {
    const result = try decode(std.testing.allocator, "\\n\\t\\\\", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\n\t\\", result.output);
}

test "unicode_escape decode \\x escape" {
    const result = try decode(std.testing.allocator, "\\x41\\x42", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("AB", result.output);
}

test "unicode_escape decode \\u escape" {
    const result = try decode(std.testing.allocator, "\\u0041\\u0042", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("AB", result.output);
}

test "unicode_escape encode" {
    const result = try encode(std.testing.allocator, "A\n\t", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("A\\n\\t", result.output);
}
