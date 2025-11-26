/// Parse JSON arrays
const std = @import("std");
const JsonValue = @import("../value.zig").JsonValue;
const skipWhitespace = @import("../value.zig").skipWhitespace;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;

// Forward declaration - will be set by parse.zig
var parseValueFn: ?*const fn ([]const u8, usize, std.mem.Allocator) JsonError!ParseResult(JsonValue) = null;

pub fn setParseValueFn(func: *const fn ([]const u8, usize, std.mem.Allocator) JsonError!ParseResult(JsonValue)) void {
    parseValueFn = func;
}

/// Parse JSON array: [ value, value, ... ]
pub fn parseArray(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(JsonValue) {
    if (pos >= data.len or data[pos] != '[') return JsonError.UnexpectedToken;

    var array = std.ArrayList(JsonValue){};
    errdefer {
        for (array.items) |*item| {
            item.deinit(allocator);
        }
        array.deinit(allocator);
    }

    var i = skipWhitespace(data, pos + 1);

    // Check for empty array
    if (i < data.len and data[i] == ']') {
        return ParseResult(JsonValue).init(
            .{ .array = array },
            i + 1 - pos,
        );
    }

    // Parse elements
    while (true) {
        // Parse value
        const parse_fn = parseValueFn orelse return JsonError.UnexpectedToken;
        const value_result = try parse_fn(data, i, allocator);
        try array.append(allocator, value_result.value);
        i += value_result.consumed;

        // Skip whitespace
        i = skipWhitespace(data, i);
        if (i >= data.len) return JsonError.UnexpectedEndOfInput;

        const c = data[i];
        if (c == ']') {
            // End of array
            return ParseResult(JsonValue).init(
                .{ .array = array },
                i + 1 - pos,
            );
        } else if (c == ',') {
            // More elements
            i = skipWhitespace(data, i + 1);

            // Check for trailing comma
            if (i < data.len and data[i] == ']') {
                return JsonError.TrailingComma;
            }
        } else {
            return JsonError.UnexpectedToken;
        }
    }
}

test "parse empty array" {
    const allocator = std.testing.allocator;

    // Set up parseValueFn (would normally be done by parse.zig)
    const testParseValue = struct {
        fn parse(_: []const u8, _: usize, _: std.mem.Allocator) JsonError!ParseResult(JsonValue) {
            return JsonError.UnexpectedToken;
        }
    }.parse;
    setParseValueFn(&testParseValue);

    const result = try parseArray("[]", 0, allocator);
    defer {
        var val = result.value;
        val.deinit(allocator);
    }

    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 0), result.value.array.items.len);
    try std.testing.expectEqual(@as(usize, 2), result.consumed);
}

test "parse array with whitespace" {
    const allocator = std.testing.allocator;

    const testParseValue = struct {
        fn parse(_: []const u8, _: usize, _: std.mem.Allocator) JsonError!ParseResult(JsonValue) {
            return JsonError.UnexpectedToken;
        }
    }.parse;
    setParseValueFn(&testParseValue);

    const result = try parseArray("[  ]", 0, allocator);
    defer {
        var val = result.value;
        val.deinit(allocator);
    }

    try std.testing.expect(result.value == .array);
    try std.testing.expectEqual(@as(usize, 0), result.value.array.items.len);
}
