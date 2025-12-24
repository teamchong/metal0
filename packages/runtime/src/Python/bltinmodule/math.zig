/// math - Math Built-in Functions
/// abs(), pow(), round(), min(), max(), sum(), divmod() implementations.

const std = @import("std");
const errors = @import("../errors.zig");

// ============================================================================
// Math Functions
// ============================================================================

/// Absolute value
/// Mirrors: builtin abs()
pub fn abs_builtin(value: anytype) @TypeOf(value) {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .int => @intCast(@abs(value)),
        .float => @abs(value),
        else => value,
    };
}

/// Power function with optional modular exponentiation
/// Mirrors: builtin pow(base, exp[, mod])
/// When mod is provided, computes (base ** exp) % mod efficiently using
/// modular exponentiation (square-and-multiply algorithm)
pub fn pow_builtin(base: anytype, exp: anytype, mod: anytype) !i64 {
    const T = @TypeOf(mod);
    const has_mod = switch (@typeInfo(T)) {
        .optional => mod != null,
        .null => false,
        else => true,
    };

    if (has_mod) {
        // Modular exponentiation: (base ** exp) % mod
        const m: i64 = switch (@typeInfo(T)) {
            .optional => mod.?,
            else => @intCast(mod),
        };
        if (m == 0) {
            errors.setString("ValueError", "pow() 3rd argument cannot be 0");
            return error.ValueError;
        }
        if (m == 1) return 0;

        var result: i64 = 1;
        var b: i64 = @intCast(base);
        var e: u64 = @intCast(exp);

        // Ensure base is positive modulo m
        b = @mod(b, m);

        // Square-and-multiply algorithm
        while (e > 0) {
            if (e & 1 == 1) {
                result = @mod(result * b, m);
            }
            e >>= 1;
            b = @mod(b * b, m);
        }
        return result;
    } else {
        // Regular exponentiation
        const b: f64 = @floatFromInt(base);
        const e: f64 = @floatFromInt(exp);
        const result = std.math.pow(f64, b, e);
        return @intFromFloat(result);
    }
}

/// Round to nearest integer (banker's rounding - round half to even)
/// Mirrors: builtin round()
/// Python uses IEEE 754 round-half-to-even semantics
pub fn round_builtin(value: f64, ndigits: ?i32) f64 {
    const bankersRound = @import("../../runtime/builtins/conversion.zig").bankersRound;
    if (ndigits) |n| {
        const factor = std.math.pow(f64, 10, @floatFromInt(n));
        return bankersRound(value * factor) / factor;
    }
    return bankersRound(value);
}

/// Integer division and modulo
/// Mirrors: builtin divmod()
pub fn divmod_builtin(a: i64, b: i64) !struct { i64, i64 } {
    if (b == 0) {
        errors.setString("ZeroDivisionError", "integer division or modulo by zero");
        return error.ZeroDivisionError;
    }
    return .{ @divFloor(a, b), @mod(a, b) };
}

/// Minimum value
/// Mirrors: builtin min()
pub fn min_builtin(values: anytype) @TypeOf(values[0]) {
    var result = values[0];
    for (values[1..]) |v| {
        if (v < result) result = v;
    }
    return result;
}

/// Maximum value
/// Mirrors: builtin max()
pub fn max_builtin(values: anytype) @TypeOf(values[0]) {
    var result = values[0];
    for (values[1..]) |v| {
        if (v > result) result = v;
    }
    return result;
}

/// Sum of iterable
/// Mirrors: builtin sum()
pub fn sum_builtin(comptime T: type, values: []const T, start: T) T {
    var result = start;
    for (values) |v| {
        result += v;
    }
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "abs function" {
    try std.testing.expectEqual(@as(i32, 5), abs_builtin(@as(i32, -5)));
    try std.testing.expectEqual(@as(f64, 3.14), abs_builtin(@as(f64, -3.14)));
}
