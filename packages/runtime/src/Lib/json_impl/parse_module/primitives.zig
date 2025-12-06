/// Parse JSON primitives: null, true, false
const std = @import("std");
const JsonValue = @import("../value.zig").JsonValue;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;

/// Parse 'null'
pub fn parseNull(data: []const u8, pos: usize) JsonError!ParseResult(JsonValue) {
    if (pos + 4 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 4], "null")) {
        return JsonError.UnexpectedToken;
    }
    return ParseResult(JsonValue).init(.null_value, 4);
}

/// Parse 'true'
pub fn parseTrue(data: []const u8, pos: usize) JsonError!ParseResult(JsonValue) {
    if (pos + 4 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 4], "true")) {
        return JsonError.UnexpectedToken;
    }
    return ParseResult(JsonValue).init(.{ .bool_value = true }, 4);
}

/// Parse 'false'
pub fn parseFalse(data: []const u8, pos: usize) JsonError!ParseResult(JsonValue) {
    if (pos + 5 > data.len) return JsonError.UnexpectedEndOfInput;
    if (!std.mem.eql(u8, data[pos .. pos + 5], "false")) {
        return JsonError.UnexpectedToken;
    }
    return ParseResult(JsonValue).init(.{ .bool_value = false }, 5);
}

/// Parse any primitive based on first character
pub fn parsePrimitive(data: []const u8, pos: usize) JsonError!ParseResult(JsonValue) {
    if (pos >= data.len) return JsonError.UnexpectedEndOfInput;

    const c = data[pos];
    return switch (c) {
        'n' => try parseNull(data, pos),
        't' => try parseTrue(data, pos),
        'f' => try parseFalse(data, pos),
        else => JsonError.UnexpectedToken,
    };
}

test "parse null" {
    const result = try parseNull("null", 0);
    try std.testing.expectEqual(JsonValue.null_value, result.value);
    try std.testing.expectEqual(@as(usize, 4), result.consumed);
}

test "parse true" {
    const result = try parseTrue("true", 0);
    try std.testing.expect(result.value.bool_value == true);
    try std.testing.expectEqual(@as(usize, 4), result.consumed);
}

test "parse false" {
    const result = try parseFalse("false", 0);
    try std.testing.expect(result.value.bool_value == false);
    try std.testing.expectEqual(@as(usize, 5), result.consumed);
}
