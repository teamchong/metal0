/// Parse JSON numbers with fast integer path - uses shared primitives
const std = @import("std");
const JsonValue = @import("../value.zig").JsonValue;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const json = @import("json");
const primitives = json.primitives;

/// Parse number - handles integers and floats (delegates to shared primitives)
pub fn parseNumber(data: []const u8, pos: usize) JsonError!ParseResult(JsonValue) {
    const result = primitives.parseNumber(data, pos) catch |err| {
        return switch (err) {
            error.InvalidNumber => JsonError.InvalidNumber,
            error.NumberOutOfRange => JsonError.NumberOutOfRange,
            error.UnexpectedEndOfInput => JsonError.UnexpectedEndOfInput,
            else => JsonError.InvalidNumber,
        };
    };

    const value: JsonValue = switch (result.value) {
        .int => |v| .{ .number_int = v },
        .float => |v| .{ .number_float = v },
    };

    return ParseResult(JsonValue).init(value, result.consumed);
}

test "parse positive integer" {
    const result = try parseNumber("42", 0);
    try std.testing.expect(result.value == .number_int);
    try std.testing.expectEqual(@as(i64, 42), result.value.number_int);
    try std.testing.expectEqual(@as(usize, 2), result.consumed);
}

test "parse negative integer" {
    const result = try parseNumber("-123", 0);
    try std.testing.expect(result.value == .number_int);
    try std.testing.expectEqual(@as(i64, -123), result.value.number_int);
    try std.testing.expectEqual(@as(usize, 4), result.consumed);
}

test "parse zero" {
    const result = try parseNumber("0", 0);
    try std.testing.expect(result.value == .number_int);
    try std.testing.expectEqual(@as(i64, 0), result.value.number_int);
}

test "parse float" {
    const result = try parseNumber("3.14", 0);
    try std.testing.expect(result.value == .number_float);
    try std.testing.expectApproxEqRel(@as(f64, 3.14), result.value.number_float, 0.0001);
}

test "parse float with exponent" {
    const result = try parseNumber("1.5e10", 0);
    try std.testing.expect(result.value == .number_float);
    try std.testing.expectApproxEqRel(@as(f64, 1.5e10), result.value.number_float, 0.0001);
}
