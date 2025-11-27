/// Parse JSON strings with SIMD-accelerated scanning
const std = @import("std");
const JsonValue = @import("../value.zig").JsonValue;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const simd = @import("json_simd");

/// Comptime hex digit lookup table (like Rust serde_json)
const HEX_TABLE: [256]u8 = blk: {
    var table: [256]u8 = [_]u8{255} ** 256;
    for ('0'..'9' + 1) |c| table[c] = @intCast(c - '0');
    for ('a'..'f' + 1) |c| table[c] = @intCast(c - 'a' + 10);
    for ('A'..'F' + 1) |c| table[c] = @intCast(c - 'A' + 10);
    break :blk table;
};

/// Comptime escape character lookup table
const ESCAPE_CHARS: [256]u8 = blk: {
    var table: [256]u8 = [_]u8{0} ** 256;
    table['"'] = '"';
    table['\\'] = '\\';
    table['/'] = '/';
    table['b'] = '\x08';
    table['f'] = '\x0C';
    table['n'] = '\n';
    table['r'] = '\r';
    table['t'] = '\t';
    table['u'] = 'u'; // Special marker for unicode
    break :blk table;
};

/// Parse 4 hex digits to u16 using lookup table (no branching)
inline fn parseHex4(hex: *const [4]u8) ?u16 {
    const a = HEX_TABLE[hex[0]];
    const b = HEX_TABLE[hex[1]];
    const c = HEX_TABLE[hex[2]];
    const d = HEX_TABLE[hex[3]];
    if ((a | b | c | d) > 15) return null;
    return (@as(u16, a) << 12) | (@as(u16, b) << 8) | (@as(u16, c) << 4) | @as(u16, d);
}

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

/// Unescape a JSON string with escape sequences (optimized with bulk copy)
fn unescapeString(escaped: []const u8, allocator: std.mem.Allocator) JsonError![]const u8 {
    // Pre-allocate: result is at most same length as input
    var result = try allocator.alloc(u8, escaped.len);
    errdefer allocator.free(result);

    var write_pos: usize = 0;
    var read_pos: usize = 0;

    while (read_pos < escaped.len) {
        // Find next backslash
        const chunk_start = read_pos;
        while (read_pos < escaped.len and escaped[read_pos] != '\\') : (read_pos += 1) {}

        // Bulk copy non-escaped chunk
        const chunk_len = read_pos - chunk_start;
        if (chunk_len > 0) {
            @memcpy(result[write_pos..][0..chunk_len], escaped[chunk_start..][0..chunk_len]);
            write_pos += chunk_len;
        }

        // Handle escape sequence
        if (read_pos < escaped.len and escaped[read_pos] == '\\') {
            read_pos += 1;
            if (read_pos >= escaped.len) {
                allocator.free(result);
                return JsonError.InvalidEscape;
            }

            const c = escaped[read_pos];
            const replacement = ESCAPE_CHARS[c];

            if (replacement == 'u') {
                if (read_pos + 4 >= escaped.len) {
                    allocator.free(result);
                    return JsonError.InvalidUnicode;
                }
                const hex = escaped[read_pos + 1 ..][0..4];
                const codepoint = parseHex4(hex) orelse {
                    allocator.free(result);
                    return JsonError.InvalidUnicode;
                };

                var utf8_buf: [4]u8 = undefined;
                const utf8_len = std.unicode.utf8Encode(@as(u21, codepoint), &utf8_buf) catch {
                    allocator.free(result);
                    return JsonError.InvalidUnicode;
                };
                @memcpy(result[write_pos..][0..utf8_len], utf8_buf[0..utf8_len]);
                write_pos += utf8_len;
                read_pos += 5;
            } else if (replacement != 0) {
                result[write_pos] = replacement;
                write_pos += 1;
                read_pos += 1;
            } else {
                allocator.free(result);
                return JsonError.InvalidEscape;
            }
        }
    }

    // Shrink to actual size
    if (write_pos < result.len) {
        result = allocator.realloc(result, write_pos) catch result[0..write_pos];
    }
    return result[0..write_pos];
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
