/// Parse JSON objects
const std = @import("std");
const JsonValue = @import("../value.zig").JsonValue;
const skipWhitespace = @import("../value.zig").skipWhitespace;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const parseString = @import("string.zig").parseString;

// Forward declaration - will be set by parse.zig
var parseValueFn: ?*const fn ([]const u8, usize, std.mem.Allocator) JsonError!ParseResult(JsonValue) = null;

pub fn setParseValueFn(func: *const fn ([]const u8, usize, std.mem.Allocator) JsonError!ParseResult(JsonValue)) void {
    parseValueFn = func;
}

/// Parse JSON object: { "key": value, "key2": value2, ... }
pub fn parseObject(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(JsonValue) {
    if (pos >= data.len or data[pos] != '{') return JsonError.UnexpectedToken;

    var object = std.StringHashMap(JsonValue).init(allocator);
    errdefer {
        var it = object.valueIterator();
        while (it.next()) |val| {
            val.deinit(allocator);
        }
        object.deinit();
    }

    var i = skipWhitespace(data, pos + 1);

    // Check for empty object
    if (i < data.len and data[i] == '}') {
        return ParseResult(JsonValue).init(
            .{ .object = object },
            i + 1 - pos,
        );
    }

    // Parse key-value pairs
    while (true) {
        // Parse key (must be string)
        if (i >= data.len or data[i] != '"') return JsonError.UnexpectedToken;

        const key_result = try parseString(data, i, allocator);
        const key = key_result.value.string;
        i += key_result.consumed;

        // Need to own the key string for HashMap
        const owned_key = try allocator.dupe(u8, key);
        errdefer allocator.free(owned_key);

        // Skip whitespace and expect colon
        i = skipWhitespace(data, i);
        if (i >= data.len or data[i] != ':') return JsonError.UnexpectedToken;
        i = skipWhitespace(data, i + 1);

        // Parse value
        const parse_fn = parseValueFn orelse return JsonError.UnexpectedToken;
        const value_result = try parse_fn(data, i, allocator);
        i += value_result.consumed;

        // Check for duplicate key
        if (object.contains(owned_key)) {
            allocator.free(owned_key);
            return JsonError.DuplicateKey;
        }

        // Insert into object
        try object.put(owned_key, value_result.value);

        // Skip whitespace
        i = skipWhitespace(data, i);
        if (i >= data.len) return JsonError.UnexpectedEndOfInput;

        const c = data[i];
        if (c == '}') {
            // End of object
            return ParseResult(JsonValue).init(
                .{ .object = object },
                i + 1 - pos,
            );
        } else if (c == ',') {
            // More pairs
            i = skipWhitespace(data, i + 1);

            // Check for trailing comma
            if (i < data.len and data[i] == '}') {
                return JsonError.TrailingComma;
            }
        } else {
            return JsonError.UnexpectedToken;
        }
    }
}

test "parse empty object" {
    const allocator = std.testing.allocator;

    const testParseValue = struct {
        fn parse(_: []const u8, _: usize, _: std.mem.Allocator) JsonError!ParseResult(JsonValue) {
            return JsonError.UnexpectedToken;
        }
    }.parse;
    setParseValueFn(&testParseValue);

    const result = try parseObject("{}", 0, allocator);
    defer {
        var val = result.value;
        val.deinit(allocator);
    }

    try std.testing.expect(result.value == .object);
    try std.testing.expectEqual(@as(usize, 0), result.value.object.count());
    try std.testing.expectEqual(@as(usize, 2), result.consumed);
}

test "parse object with whitespace" {
    const allocator = std.testing.allocator;

    const testParseValue = struct {
        fn parse(_: []const u8, _: usize, _: std.mem.Allocator) JsonError!ParseResult(JsonValue) {
            return JsonError.UnexpectedToken;
        }
    }.parse;
    setParseValueFn(&testParseValue);

    const result = try parseObject("{  }", 0, allocator);
    defer {
        var val = result.value;
        val.deinit(allocator);
    }

    try std.testing.expect(result.value == .object);
    try std.testing.expectEqual(@as(usize, 0), result.value.object.count());
}
