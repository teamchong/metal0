/// Main JSON parser dispatcher - coordinates all parsing modules
const std = @import("std");
const JsonValue = @import("value.zig").JsonValue;
const skipWhitespace = @import("value.zig").skipWhitespace;
const JsonError = @import("errors.zig").JsonError;
const ParseResult = @import("errors.zig").ParseResult;

const primitives = @import("parse/primitives.zig");
const number = @import("parse/number.zig");
const string = @import("parse/string.zig");
const array = @import("parse/array.zig");
const object = @import("parse/object.zig");

/// Main entry point: parse JSON string into JsonValue
pub fn parse(data: []const u8, allocator: std.mem.Allocator) JsonError!JsonValue {
    // Set up circular dependencies
    array.setParseValueFn(&parseValue);
    object.setParseValueFn(&parseValue);

    const i = skipWhitespace(data, 0);
    if (i >= data.len) return JsonError.UnexpectedEndOfInput;

    const result = try parseValue(data, i, allocator);

    // Check for trailing content
    const final_pos = skipWhitespace(data, i + result.consumed);
    if (final_pos < data.len) {
        return JsonError.UnexpectedToken;
    }

    return result.value;
}

/// Parse any JSON value based on first non-whitespace character
pub fn parseValue(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(JsonValue) {
    const i = skipWhitespace(data, pos);
    if (i >= data.len) return JsonError.UnexpectedEndOfInput;

    const c = data[i];
    return switch (c) {
        '{' => try object.parseObject(data, i, allocator),
        '[' => try array.parseArray(data, i, allocator),
        '"' => try string.parseString(data, i, allocator),
        '-', '0'...'9' => try number.parseNumber(data, i),
        'n', 't', 'f' => try primitives.parsePrimitive(data, i),
        else => JsonError.UnexpectedToken,
    };
}

test "parse null" {
    const allocator = std.testing.allocator;
    const value = try parse("null", allocator);
    defer {
        var val = value;
        val.deinit(allocator);
    }
    try std.testing.expect(value == .null_value);
}

test "parse boolean" {
    const allocator = std.testing.allocator;

    const t = try parse("true", allocator);
    defer {
        var val = t;
        val.deinit(allocator);
    }
    try std.testing.expect(t.bool_value == true);

    const f = try parse("false", allocator);
    defer {
        var val = f;
        val.deinit(allocator);
    }
    try std.testing.expect(f.bool_value == false);
}

test "parse number" {
    const allocator = std.testing.allocator;

    const int_val = try parse("42", allocator);
    defer {
        var val = int_val;
        val.deinit(allocator);
    }
    try std.testing.expectEqual(@as(i64, 42), int_val.number_int);

    const float_val = try parse("3.14", allocator);
    defer {
        var val = float_val;
        val.deinit(allocator);
    }
    try std.testing.expectApproxEqRel(@as(f64, 3.14), float_val.number_float, 0.0001);
}

test "parse string" {
    const allocator = std.testing.allocator;
    const value = try parse("\"hello\"", allocator);
    defer {
        var val = value;
        val.deinit(allocator);
    }
    try std.testing.expectEqualStrings("hello", value.string);
}

test "parse empty array" {
    const allocator = std.testing.allocator;
    var value = try parse("[]", allocator);
    defer value.deinit(allocator);

    try std.testing.expect(value == .array);
    try std.testing.expectEqual(@as(usize, 0), value.array.items.len);
}

test "parse array with numbers" {
    const allocator = std.testing.allocator;
    var value = try parse("[1, 2, 3]", allocator);
    defer value.deinit(allocator);

    try std.testing.expect(value == .array);
    try std.testing.expectEqual(@as(usize, 3), value.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), value.array.items[0].number_int);
    try std.testing.expectEqual(@as(i64, 2), value.array.items[1].number_int);
    try std.testing.expectEqual(@as(i64, 3), value.array.items[2].number_int);
}

test "parse empty object" {
    const allocator = std.testing.allocator;
    var value = try parse("{}", allocator);
    defer value.deinit(allocator);

    try std.testing.expect(value == .object);
    try std.testing.expectEqual(@as(usize, 0), value.object.count());
}

test "parse object with values" {
    const allocator = std.testing.allocator;
    var value = try parse("{\"name\": \"PyAOT\", \"count\": 3}", allocator);
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
    var value = try parse("{\"items\": [1, 2], \"meta\": {\"count\": 2}}", allocator);
    defer value.deinit(allocator);

    try std.testing.expect(value == .object);

    const items = value.object.get("items").?;
    try std.testing.expectEqual(@as(usize, 2), items.array.items.len);

    const meta = value.object.get("meta").?;
    const count = meta.object.get("count").?;
    try std.testing.expectEqual(@as(i64, 2), count.number_int);
}
