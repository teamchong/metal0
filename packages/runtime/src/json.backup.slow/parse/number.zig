/// Parse JSON numbers with fast integer path
const std = @import("std");
const JsonValue = @import("../value.zig").JsonValue;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;

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

/// Parse number - handles integers and floats
pub fn parseNumber(data: []const u8, pos: usize) JsonError!ParseResult(JsonValue) {
    if (pos >= data.len) return JsonError.UnexpectedEndOfInput;

    var i = pos;
    var is_negative = false;
    var has_decimal = false;
    var has_exponent = false;

    // Handle negative sign
    if (data[i] == '-') {
        is_negative = true;
        i += 1;
        if (i >= data.len) return JsonError.InvalidNumber;
    }

    // Fast path: simple positive integer
    if (!is_negative) {
        if (parsePositiveInt(data, i)) |result| {
            // Check if number ends here (no decimal or exponent)
            const next_pos = i + result.consumed;
            if (next_pos >= data.len or !isNumberContinuation(data[next_pos])) {
                return ParseResult(JsonValue).init(
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
            return JsonError.InvalidNumber;
        }
    } else {
        // Parse digits
        const digit_start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == digit_start) return JsonError.InvalidNumber;
    }

    // Decimal part
    if (i < data.len and data[i] == '.') {
        has_decimal = true;
        i += 1;
        const decimal_start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == decimal_start) return JsonError.InvalidNumber; // Must have digits after decimal
    }

    // Exponent part
    if (i < data.len and (data[i] == 'e' or data[i] == 'E')) {
        has_exponent = true;
        i += 1;
        if (i >= data.len) return JsonError.InvalidNumber;

        // Optional sign
        if (data[i] == '+' or data[i] == '-') {
            i += 1;
        }

        const exp_start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == exp_start) return JsonError.InvalidNumber; // Must have digits in exponent
    }

    const num_str = data[pos..i];

    // Parse as integer if no decimal or exponent
    if (!has_decimal and !has_exponent) {
        const value = std.fmt.parseInt(i64, num_str, 10) catch return JsonError.NumberOutOfRange;
        return ParseResult(JsonValue).init(.{ .number_int = value }, i - pos);
    }

    // Parse as float
    const value = std.fmt.parseFloat(f64, num_str) catch return JsonError.InvalidNumber;
    return ParseResult(JsonValue).init(.{ .number_float = value }, i - pos);
}

/// Check if character can continue a number
inline fn isNumberContinuation(c: u8) bool {
    return c == '.' or c == 'e' or c == 'E';
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
