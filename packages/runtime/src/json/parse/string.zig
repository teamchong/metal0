/// Parse JSON strings with SIMD-accelerated scanning
const std = @import("std");
const JsonValue = @import("../value.zig").JsonValue;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const simd = @import("../simd/dispatch.zig");

/// Parse JSON string with SIMD-accelerated scanning
pub fn parseString(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(JsonValue) {
    if (pos >= data.len or data[pos] != '"') return JsonError.UnexpectedToken;

    const start = pos + 1; // Skip opening quote

    // Use SIMD to quickly check for escapes
    const has_escapes = simd.hasEscapes(data[start..]);

    // Use SIMD to find closing quote
    if (simd.findClosingQuote(data[start..], 0)) |rel_pos| {
        const i = start + rel_pos;

        if (!has_escapes) {
            // Fast path: No escapes, just copy
            const str = try allocator.dupe(u8, data[start..i]);
            return ParseResult(JsonValue).init(
                .{ .string = str },
                i + 1 - pos,
            );
        } else {
            // Slow path: Need to unescape
            const unescaped = try unescapeString(data[start..i], allocator);
            return ParseResult(JsonValue).init(
                .{ .string = unescaped },
                i + 1 - pos,
            );
        }
    }

    return JsonError.UnexpectedEndOfInput;
}

/// Unescape a JSON string with escape sequences
fn unescapeString(escaped: []const u8, allocator: std.mem.Allocator) JsonError![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < escaped.len) : (i += 1) {
        if (escaped[i] == '\\') {
            i += 1;
            if (i >= escaped.len) return JsonError.InvalidEscape;

            const c = escaped[i];
            switch (c) {
                '"' => try result.append(allocator, '"'),
                '\\' => try result.append(allocator, '\\'),
                '/' => try result.append(allocator, '/'),
                'b' => try result.append(allocator, '\x08'),
                'f' => try result.append(allocator, '\x0C'),
                'n' => try result.append(allocator, '\n'),
                'r' => try result.append(allocator, '\r'),
                't' => try result.append(allocator, '\t'),
                'u' => {
                    // Unicode escape: \uXXXX
                    if (i + 4 >= escaped.len) return JsonError.InvalidUnicode;
                    const hex = escaped[i + 1 .. i + 5];
                    const codepoint = std.fmt.parseInt(u16, hex, 16) catch return JsonError.InvalidUnicode;

                    // Convert codepoint to UTF-8
                    var utf8_buf: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(@as(u21, codepoint), &utf8_buf) catch return JsonError.InvalidUnicode;
                    try result.appendSlice(allocator, utf8_buf[0..utf8_len]);

                    i += 4; // Skip XXXX
                },
                else => return JsonError.InvalidEscape,
            }
        } else {
            try result.append(allocator, escaped[i]);
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Get SIMD implementation info (for debugging/testing)
pub fn getSimdInfo() []const u8 {
    return simd.getSimdInfo();
}

test "parse simple string" {
    const allocator = std.testing.allocator;
    const result = try parseString("\"hello\"", 0, allocator);
    defer {
        var val = result.value;
        val.deinit(allocator);
    }

    try std.testing.expect(result.value == .string);
    try std.testing.expectEqualStrings("hello", result.value.string);
    try std.testing.expectEqual(@as(usize, 7), result.consumed);
}

test "parse string with escapes" {
    const allocator = std.testing.allocator;
    const result = try parseString("\"hello\\nworld\"", 0, allocator);
    defer {
        var val = result.value;
        val.deinit(allocator);
    }

    try std.testing.expect(result.value == .string);
    try std.testing.expectEqualStrings("hello\nworld", result.value.string);
}

test "parse string with unicode" {
    const allocator = std.testing.allocator;
    const result = try parseString("\"\\u0048\\u0065\\u006C\\u006C\\u006F\"", 0, allocator);
    defer {
        var val = result.value;
        val.deinit(allocator);
    }

    try std.testing.expect(result.value == .string);
    try std.testing.expectEqualStrings("Hello", result.value.string);
}
