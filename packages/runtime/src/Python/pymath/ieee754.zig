/// IEEE 754 operations
/// Mirrors cpython/Python/pymath.c

const std = @import("std");
const special_values = @import("special_values.zig");

// ============================================================================
// IEEE 754 Operations
// ============================================================================

/// Extract mantissa and exponent
pub fn Py_FREXP(x: f64) struct { frac: f64, exp: i32 } {
    const result = std.math.frexp(x);
    return .{ .frac = result.significand, .exp = result.exponent };
}

/// Compose from mantissa and exponent
pub fn Py_LDEXP(x: f64, exp: i32) f64 {
    return std.math.ldexp(x, exp);
}

/// Split into integer and fractional parts
pub fn Py_MODF(x: f64) struct { int_part: f64, frac_part: f64 } {
    const result = std.math.modf(x);
    return .{ .int_part = result.ipart, .frac_part = result.fpart };
}

/// Floating-point remainder
pub fn Py_FMOD(x: f64, y: f64) f64 {
    return @mod(x, y);
}

/// IEEE remainder (different from fmod)
pub fn Py_REMAINDER(x: f64, y: f64) f64 {
    if (y == 0) return @import("constants.zig").Py_NAN;

    // IEEE 754 remainder: x - n*y where n is the nearest integer to x/y
    const n = @round(x / y);
    return x - n * y;
}

/// Get next representable value
pub fn Py_NEXTAFTER(x: f64, y: f64) f64 {
    if (special_values.Py_IS_NAN(x) or special_values.Py_IS_NAN(y)) return @import("constants.zig").Py_NAN;
    if (x == y) return y;

    const bits_x: u64 = @bitCast(x);
    const bits_y: u64 = @bitCast(y);

    var new_bits: u64 = undefined;
    if (x == 0.0) {
        // Move from zero towards y
        new_bits = 1;
        if (y < 0) new_bits |= 0x8000000000000000;
    } else if ((x < y) == (x > 0)) {
        new_bits = bits_x + 1;
    } else {
        new_bits = bits_x - 1;
    }

    _ = bits_y;
    return @bitCast(new_bits);
}
