/// Basic math operations
/// Mirrors cpython/Python/pymath.c

const std = @import("std");

// ============================================================================
// Basic Math Operations
// ============================================================================

/// Absolute value
pub fn Py_ABS(x: f64) f64 {
    return @abs(x);
}

/// Floor division
pub fn Py_FLOOR(x: f64) f64 {
    return @floor(x);
}

/// Ceiling
pub fn Py_CEIL(x: f64) f64 {
    return @ceil(x);
}

/// Truncate towards zero
pub fn Py_TRUNC(x: f64) f64 {
    return @trunc(x);
}

/// Round to nearest integer (banker's rounding - round half to even)
pub fn Py_ROUND(x: f64) f64 {
    return bankersRound(x);
}

const bankersRound = @import("../../runtime/builtins/conversion.zig").bankersRound;

/// Square root
pub fn Py_SQRT(x: f64) f64 {
    return @sqrt(x);
}

/// Exponential (e^x)
pub fn Py_EXP(x: f64) f64 {
    return @exp(x);
}

/// Natural logarithm
pub fn Py_LOG(x: f64) f64 {
    return @log(x);
}

/// Base-10 logarithm
pub fn Py_LOG10(x: f64) f64 {
    return std.math.log10(x);
}

/// Base-2 logarithm
pub fn Py_LOG2(x: f64) f64 {
    return std.math.log2(x);
}

/// Power function (x^y)
pub fn Py_POW(x: f64, y: f64) f64 {
    return std.math.pow(x, y);
}

/// Hypotenuse (sqrt(x^2 + y^2))
pub fn Py_HYPOT(x: f64, y: f64) f64 {
    return std.math.hypot(x, y);
}

/// Copy sign of y to x
pub fn Py_COPYSIGN(x: f64, y: f64) f64 {
    return std.math.copysign(x, y);
}

/// Fused multiply-add (x * y + z)
pub fn Py_FMA(x: f64, y: f64, z: f64) f64 {
    return @mulAdd(f64, x, y, z);
}
