//! JSON Parser - shared library implementation
//! Portable, no SIMD dependencies, optimized for common cases
//!
//! Based on packages/runtime/src/json/parse.zig but without PyObject dependencies.

const std = @import("std");
const Value = @import("value.zig").Value;
const skipWhitespace = @import("value.zig").skipWhitespace;

pub const ParseError = error{
    UnexpectedToken,
    InvalidNumber,
    InvalidString,
    InvalidEscape,
    InvalidUnicode,
    UnterminatedString,
    MaxDepthExceeded,
    OutOfMemory,
    TrailingData,
    TrailingComma,
    DuplicateKey,
    UnexpectedEndOfInput,
    NumberOutOfRange,
};

/// Result of a parse operation
const ParseResult = struct {
    value: Value,
    consumed: usize,

    fn init(val: Value, bytes: usize) ParseResult {
        return .{ .value = val, .consumed = bytes };
    }
};

/// Parse JSON string into Value
pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParseError!Value {
    const i = skipWhitespace(input, 0);
    if (i >= input.len) return ParseError.UnexpectedEndOfInput;

    const result = try parseValue(input, i, allocator);

    // Check for trailing content
    const final_pos = skipWhitespace(input, i + result.consumed);
    if (final_pos < input.len) {
        var val = result.value;
        val.deinit(allocator);
        return ParseError.TrailingData;
    }

    return result.value;
}

/// Parse any JSON value based on first non-whitespace character
fn parseValue(data: []const u8, pos: usize, allocator: std.mem.Allocator) ParseError!ParseResult {
    const i = skipWhitespace(data, pos);
    if (i >= data.len) return ParseError.UnexpectedEndOfInput;

    const c = data[i];
    return switch (c) {
        '{' => try parseObject(data, i, allocator),
        '[' => try parseArray(data, i, allocator),
        '"' => try parseString(data, i, allocator),
        '-', '0'...'9' => try parseNumber(data, i),
        'n', 't', 'f' => try parsePrimitive(data, i),
        else => ParseError.UnexpectedToken,
    };
}

// ============================================================================
// Primitive parsing (null, true, false)
// ============================================================================

fn parsePrimitive(data: []const u8, pos: usize) ParseError!ParseResult {
    if (pos >= data.len) return ParseError.UnexpectedEndOfInput;

    const c = data[pos];
    return switch (c) {
        'n' => try parseNull(data, pos),
        't' => try parseTrue(data, pos),
        'f' => try parseFalse(data, pos),
        else => ParseError.UnexpectedToken,
    };
}

fn parseNull(data: []const u8, pos: usize) ParseError!ParseResult {
    if (pos + 4 > data.len) return ParseError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 4], "null")) {
        return ParseError.UnexpectedToken;
    }
    return ParseResult.init(.null_value, 4);
}

fn parseTrue(data: []const u8, pos: usize) ParseError!ParseResult {
    if (pos + 4 > data.len) return ParseError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 4], "true")) {
        return ParseError.UnexpectedToken;
    }
    return ParseResult.init(.{ .bool_value = true }, 4);
}

fn parseFalse(data: []const u8, pos: usize) ParseError!ParseResult {
    if (pos + 5 > data.len) return ParseError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 5], "false")) {
        return ParseError.UnexpectedToken;
    }
    return ParseResult.init(.{ .bool_value = false }, 5);
}

// ============================================================================
// Number parsing (integers and floats)
// ============================================================================

/// Fast path for positive integers (most common case)
fn parsePositiveInt(data: []const u8, pos: usize) ?struct { value: i64, consumed: usize } {
    var value: i64 = 0;
    var i: usize = 0;

    while (pos + i < data.len) : (i += 1) {
        const c = data[pos + i];
        if (c < '0' or c > '9') break;

        const digit = c - '0';
        // Check for overflow
        if (value > @divTrunc((@as(i64, std.math.maxInt(i64)) - digit), 10)) {
            return null; // Overflow
        }
        value = value * 10 + digit;
    }

    if (i == 0) return null;
    return .{ .value = value, .consumed = i };
}

fn parseNumber(data: []const u8, pos: usize) ParseError!ParseResult {
    if (pos >= data.len) return ParseError.UnexpectedEndOfInput;

    var i = pos;
    var is_negative = false;
    var has_decimal = false;
    var has_exponent = false;

    // Handle negative sign
    if (data[i] == '-') {
        is_negative = true;
        i += 1;
        if (i >= data.len) return ParseError.InvalidNumber;
    }

    // Fast path: simple positive integer
    if (!is_negative) {
        if (parsePositiveInt(data, i)) |result| {
            // Check if number ends here (no decimal or exponent)
            const next_pos = i + result.consumed;
            if (next_pos >= data.len or !isNumberContinuation(data[next_pos])) {
                return ParseResult.init(
                    .{ .number_int = result.value },
                    next_pos - pos,
                );
            }
        }
    }

    // Full number parsing (handles decimals and exponents)
    // Integer part
    if (data[i] == '0') {
        i += 1;
        // Leading zero - must be followed by decimal or end
        if (i < data.len and data[i] >= '0' and data[i] <= '9') {
            return ParseError.InvalidNumber;
        }
    } else {
        // Parse digits
        const digit_start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == digit_start) return ParseError.InvalidNumber;
    }

    // Decimal part
    if (i < data.len and data[i] == '.') {
        has_decimal = true;
        i += 1;
        const decimal_start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == decimal_start) return ParseError.InvalidNumber; // Must have digits after decimal
    }

    // Exponent part
    if (i < data.len and (data[i] == 'e' or data[i] == 'E')) {
        has_exponent = true;
        i += 1;
        if (i >= data.len) return ParseError.InvalidNumber;

        // Optional sign
        if (data[i] == '+' or data[i] == '-') {
            i += 1;
        }

        const exp_start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == exp_start) return ParseError.InvalidNumber; // Must have digits in exponent
    }

    const num_str = data[pos..i];

    // Parse as integer if no decimal or exponent
    if (!has_decimal and !has_exponent) {
        const value = std.fmt.parseInt(i64, num_str, 10) catch return ParseError.NumberOutOfRange;
        return ParseResult.init(.{ .number_int = value }, i - pos);
    }

    // Parse as float
    const value = std.fmt.parseFloat(f64, num_str) catch return ParseError.InvalidNumber;
    return ParseResult.init(.{ .number_float = value }, i - pos);
}

inline fn isNumberContinuation(c: u8) bool {
    return c == '.' or c == 'e' or c == 'E';
}

// ============================================================================
// String parsing (with escape handling)
// ============================================================================

fn parseString(data: []const u8, pos: usize, allocator: std.mem.Allocator) ParseError!ParseResult {
    if (pos >= data.len or data[pos] != '"') return ParseError.UnexpectedToken;

    const start = pos + 1; // Skip opening quote
    var i = start;
    var has_escapes = false;

    // Scan for closing quote and check for escapes
    while (i < data.len) {
        const c = data[i];
        if (c == '"') {
            // Found closing quote
            if (!has_escapes) {
                // Fast path: No escapes, just copy
                const str = allocator.dupe(u8, data[start..i]) catch return ParseError.OutOfMemory;
                return ParseResult.init(
                    .{ .string = str },
                    i + 1 - pos,
                );
            } else {
                // Slow path: Need to unescape
                const unescaped = try unescapeString(data[start..i], allocator);
                return ParseResult.init(
                    .{ .string = unescaped },
                    i + 1 - pos,
                );
            }
        } else if (c == '\\') {
            has_escapes = true;
            i += 1; // Skip escaped character
            if (i >= data.len) return ParseError.UnterminatedString;
        } else if (c < 0x20) {
            // Control characters not allowed in strings
            return ParseError.InvalidString;
        }
        i += 1;
    }

    return ParseError.UnterminatedString;
}

fn unescapeString(escaped: []const u8, allocator: std.mem.Allocator) ParseError![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < escaped.len) : (i += 1) {
        if (escaped[i] == '\\') {
            i += 1;
            if (i >= escaped.len) return ParseError.InvalidEscape;

            const c = escaped[i];
            switch (c) {
                '"' => result.append(allocator, '"') catch return ParseError.OutOfMemory,
                '\\' => result.append(allocator, '\\') catch return ParseError.OutOfMemory,
                '/' => result.append(allocator, '/') catch return ParseError.OutOfMemory,
                'b' => result.append(allocator, '\x08') catch return ParseError.OutOfMemory,
                'f' => result.append(allocator, '\x0C') catch return ParseError.OutOfMemory,
                'n' => result.append(allocator, '\n') catch return ParseError.OutOfMemory,
                'r' => result.append(allocator, '\r') catch return ParseError.OutOfMemory,
                't' => result.append(allocator, '\t') catch return ParseError.OutOfMemory,
                'u' => {
                    // Unicode escape: \uXXXX
                    if (i + 4 >= escaped.len) return ParseError.InvalidUnicode;
                    const hex = escaped[i + 1 .. i + 5];
                    const codepoint = std.fmt.parseInt(u16, hex, 16) catch return ParseError.InvalidUnicode;

                    // Convert codepoint to UTF-8
                    var utf8_buf: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(@as(u21, codepoint), &utf8_buf) catch return ParseError.InvalidUnicode;
                    result.appendSlice(allocator, utf8_buf[0..utf8_len]) catch return ParseError.OutOfMemory;

                    i += 4; // Skip XXXX
                },
                else => return ParseError.InvalidEscape,
            }
        } else {
            result.append(allocator, escaped[i]) catch return ParseError.OutOfMemory;
        }
    }

    return result.toOwnedSlice(allocator) catch return ParseError.OutOfMemory;
}

// ============================================================================
// Array parsing
// ============================================================================

fn parseArray(data: []const u8, pos: usize, allocator: std.mem.Allocator) ParseError!ParseResult {
    if (pos >= data.len or data[pos] != '[') return ParseError.UnexpectedToken;

    var array = std.ArrayList(Value){};
    var cleanup_needed = true;
    defer if (cleanup_needed) {
        for (array.items) |*item| {
            item.deinit(allocator);
        }
        array.deinit(allocator);
    };

    var i = skipWhitespace(data, pos + 1);

    // Check for empty array
    if (i < data.len and data[i] == ']') {
        cleanup_needed = false;
        return ParseResult.init(
            .{ .array = array },
            i + 1 - pos,
        );
    }

    // Parse elements
    while (true) {
        // Parse value
        const value_result = try parseValue(data, i, allocator);
        array.append(allocator, value_result.value) catch {
            var val = value_result.value;
            val.deinit(allocator);
            return ParseError.OutOfMemory;
        };
        i += value_result.consumed;

        // Skip whitespace
        i = skipWhitespace(data, i);
        if (i >= data.len) return ParseError.UnexpectedEndOfInput;

        const c = data[i];
        if (c == ']') {
            // End of array - success, don't cleanup
            cleanup_needed = false;
            return ParseResult.init(
                .{ .array = array },
                i + 1 - pos,
            );
        } else if (c == ',') {
            // More elements
            i = skipWhitespace(data, i + 1);

            // Check for trailing comma
            if (i < data.len and data[i] == ']') {
                return ParseError.TrailingComma;
            }
        } else {
            return ParseError.UnexpectedToken;
        }
    }
}

// ============================================================================
// Object parsing
// ============================================================================

fn parseObject(data: []const u8, pos: usize, allocator: std.mem.Allocator) ParseError!ParseResult {
    if (pos >= data.len or data[pos] != '{') return ParseError.UnexpectedToken;

    var object = std.StringHashMap(Value).init(allocator);
    var cleanup_needed = true;
    defer if (cleanup_needed) {
        var it = object.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        object.deinit();
    };

    var i = skipWhitespace(data, pos + 1);

    // Check for empty object
    if (i < data.len and data[i] == '}') {
        cleanup_needed = false;
        return ParseResult.init(
            .{ .object = object },
            i + 1 - pos,
        );
    }

    // Parse key-value pairs
    while (true) {
        // Parse key (must be string)
        if (i >= data.len or data[i] != '"') return ParseError.UnexpectedToken;

        const key_result = try parseString(data, i, allocator);
        const key = key_result.value.string;
        i += key_result.consumed;

        // Skip whitespace and expect colon
        i = skipWhitespace(data, i);
        if (i >= data.len or data[i] != ':') {
            allocator.free(key);
            return ParseError.UnexpectedToken;
        }
        i = skipWhitespace(data, i + 1);

        // Parse value
        const value_result = parseValue(data, i, allocator) catch |err| {
            allocator.free(key);
            return err;
        };
        i += value_result.consumed;

        // Check for duplicate key
        if (object.contains(key)) {
            allocator.free(key);
            var val = value_result.value;
            val.deinit(allocator);
            return ParseError.DuplicateKey;
        }

        // Insert into object
        object.put(key, value_result.value) catch {
            allocator.free(key);
            var val = value_result.value;
            val.deinit(allocator);
            return ParseError.OutOfMemory;
        };

        // Skip whitespace
        i = skipWhitespace(data, i);
        if (i >= data.len) return ParseError.UnexpectedEndOfInput;

        const c = data[i];
        if (c == '}') {
            // End of object - success, don't cleanup
            cleanup_needed = false;
            return ParseResult.init(
                .{ .object = object },
                i + 1 - pos,
            );
        } else if (c == ',') {
            // More pairs
            i = skipWhitespace(data, i + 1);

            // Check for trailing comma
            if (i < data.len and data[i] == '}') {
                return ParseError.TrailingComma;
            }
        } else {
            return ParseError.UnexpectedToken;
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "parse null" {
    const allocator = std.testing.allocator;
    var value = try parse(allocator, "null");
    defer value.deinit(allocator);
    try std.testing.expect(value == .null_value);
}

test "parse boolean" {
    const allocator = std.testing.allocator;

    var t = try parse(allocator, "true");
    defer t.deinit(allocator);
    try std.testing.expect(t.bool_value == true);

    var f = try parse(allocator, "false");
    defer f.deinit(allocator);
    try std.testing.expect(f.bool_value == false);
}

test "parse number" {
    const allocator = std.testing.allocator;

    var int_val = try parse(allocator, "42");
    defer int_val.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 42), int_val.number_int);

    var neg_val = try parse(allocator, "-123");
    defer neg_val.deinit(allocator);
    try std.testing.expectEqual(@as(i64, -123), neg_val.number_int);

    var float_val = try parse(allocator, "3.14");
    defer float_val.deinit(allocator);
    try std.testing.expectApproxEqRel(@as(f64, 3.14), float_val.number_float, 0.0001);

    var exp_val = try parse(allocator, "1.5e10");
    defer exp_val.deinit(allocator);
    try std.testing.expectApproxEqRel(@as(f64, 1.5e10), exp_val.number_float, 0.0001);
}

test "parse string" {
    const allocator = std.testing.allocator;

    var value = try parse(allocator, "\"hello\"");
    defer value.deinit(allocator);
    try std.testing.expectEqualStrings("hello", value.string);
}

test "parse string with escapes" {
    const allocator = std.testing.allocator;

    var value = try parse(allocator, "\"hello\\nworld\"");
    defer value.deinit(allocator);
    try std.testing.expectEqualStrings("hello\nworld", value.string);
}

test "parse string with unicode" {
    const allocator = std.testing.allocator;

    var value = try parse(allocator, "\"\\u0048\\u0065\\u006C\\u006C\\u006F\"");
    defer value.deinit(allocator);
    try std.testing.expectEqualStrings("Hello", value.string);
}

test "parse empty array" {
    const allocator = std.testing.allocator;
    var value = try parse(allocator, "[]");
    defer value.deinit(allocator);

    try std.testing.expect(value == .array);
    try std.testing.expectEqual(@as(usize, 0), value.array.items.len);
}

test "parse array with numbers" {
    const allocator = std.testing.allocator;
    var value = try parse(allocator, "[1, 2, 3]");
    defer value.deinit(allocator);

    try std.testing.expect(value == .array);
    try std.testing.expectEqual(@as(usize, 3), value.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), value.array.items[0].number_int);
    try std.testing.expectEqual(@as(i64, 2), value.array.items[1].number_int);
    try std.testing.expectEqual(@as(i64, 3), value.array.items[2].number_int);
}

test "parse empty object" {
    const allocator = std.testing.allocator;
    var value = try parse(allocator, "{}");
    defer value.deinit(allocator);

    try std.testing.expect(value == .object);
    try std.testing.expectEqual(@as(usize, 0), value.object.count());
}

test "parse object with values" {
    const allocator = std.testing.allocator;
    var value = try parse(allocator, "{\"name\": \"PyAOT\", \"count\": 3}");
    defer value.deinit(allocator);

    try std.testing.expect(value == .object);
    try std.testing.expectEqual(@as(usize, 2), value.object.count());

    const name = value.object.get("name").?;
    try std.testing.expectEqualStrings("PyAOT", name.string);

    const count = value.object.get("count").?;
    try std.testing.expectEqual(@as(i64, 3), count.number_int);
}

test "parse nested structure" {
    const allocator = std.testing.allocator;
    var value = try parse(allocator, "{\"items\": [1, 2], \"meta\": {\"count\": 2}}");
    defer value.deinit(allocator);

    try std.testing.expect(value == .object);

    const items = value.object.get("items").?;
    try std.testing.expectEqual(@as(usize, 2), items.array.items.len);

    const meta = value.object.get("meta").?;
    const count = meta.object.get("count").?;
    try std.testing.expectEqual(@as(i64, 2), count.number_int);
}

test "parse with whitespace" {
    const allocator = std.testing.allocator;
    var value = try parse(allocator, "  { \"key\" : \"value\" }  ");
    defer value.deinit(allocator);

    try std.testing.expect(value == .object);
    const v = value.object.get("key").?;
    try std.testing.expectEqualStrings("value", v.string);
}

test "parse trailing data error" {
    const allocator = std.testing.allocator;
    const result = parse(allocator, "null extra");
    try std.testing.expectError(ParseError.TrailingData, result);
}

test "parse trailing comma error" {
    const allocator = std.testing.allocator;

    const arr_result = parse(allocator, "[1, 2,]");
    try std.testing.expectError(ParseError.TrailingComma, arr_result);

    const obj_result = parse(allocator, "{\"a\": 1,}");
    try std.testing.expectError(ParseError.TrailingComma, obj_result);
}
