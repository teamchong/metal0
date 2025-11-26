/// Parse JSON numbers directly to PyInt (zero extra allocations)
const std = @import("std");
const runtime = @import("../../runtime.zig");
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;

/// Fast path for positive integers (most common case)
fn parsePositiveInt(data: []const u8, pos: usize) ?struct { value: i64, consumed: usize } {
    var value: i64 = 0;
    var i: usize = 0;
    const remaining = data.len - pos;

    // SIMD fast path: Parse 8 digits at once
    while (remaining >= i + 8) {
        const chunk = data[pos + i..][0..8];

        // Load 8 bytes as a vector
        const digits_ascii: @Vector(8, u8) = chunk.*;
        const zeros: @Vector(8, u8) = @splat('0');
        const nines: @Vector(8, u8) = @splat('9');

        // Check if all 8 bytes are digits (vectorized comparison)
        const is_digit = (digits_ascii >= zeros) & (digits_ascii <= nines);
        const all_digits = @reduce(.And, is_digit);

        if (!all_digits) break; // Found non-digit, fall back to scalar

        // Convert ASCII to numeric values: '5' -> 5
        const digits: @Vector(8, u64) = @as(@Vector(8, u64), digits_ascii - zeros);

        // Multiply by powers of 10: [d0*10^7, d1*10^6, ..., d7*10^0]
        const multipliers = @Vector(8, u64){
            10_000_000,
            1_000_000,
            100_000,
            10_000,
            1_000,
            100,
            10,
            1,
        };
        const weighted = digits * multipliers;

        // Sum all 8 digits
        const chunk_value: u64 = @reduce(.Add, weighted);

        // Check for overflow before adding
        if (chunk_value > std.math.maxInt(i64)) return null;
        const chunk_i64: i64 = @intCast(chunk_value);

        // Check multiplication overflow
        const max_safe = @divTrunc(std.math.maxInt(i64) - chunk_i64, 100_000_000);
        if (value > max_safe) return null;

        value = value * 100_000_000 + chunk_i64;
        i += 8;
    }

    // Scalar fallback for remaining digits (< 8)
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

/// Parse number directly to PyInt
pub fn parseNumber(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
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
                const py_int = try runtime.PyInt.create(allocator, result.value);
                return ParseResult(*runtime.PyObject).init(
                    py_int,
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
        const py_int = try runtime.PyInt.create(allocator, value);
        return ParseResult(*runtime.PyObject).init(py_int, i - pos);
    }

    // Parse as float - for now store as truncated int
    // TODO: Add PyFloat type when needed
    const float_value = std.fmt.parseFloat(f64, num_str) catch return JsonError.InvalidNumber;
    const int_value: i64 = @intFromFloat(float_value);
    const py_int = try runtime.PyInt.create(allocator, int_value);
    return ParseResult(*runtime.PyObject).init(py_int, i - pos);
}

/// Check if character can continue a number
inline fn isNumberContinuation(c: u8) bool {
    return c == '.' or c == 'e' or c == 'E';
}
