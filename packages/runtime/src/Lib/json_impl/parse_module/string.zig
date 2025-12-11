/// Parse JSON strings with SIMD-accelerated scanning
const std = @import("std");
const JsonValue = @import("../value.zig").JsonValue;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const json = @import("json");
const primitives = json.primitives;
const simd = json.simd;

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
            // Slow path: Need to unescape (use shared optimized primitives)
            const unescaped = primitives.unescapeString(data[start..i], allocator) catch return JsonError.InvalidEscape;
            return ParseResult(JsonValue).init(
                .{ .string = unescaped },
                i + 1 - pos,
            );
        }
    }

    return JsonError.UnexpectedEndOfInput;
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
