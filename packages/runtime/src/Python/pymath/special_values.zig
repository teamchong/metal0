/// Special value detection
/// Mirrors cpython/Python/pymath.c

const std = @import("std");
const constants = @import("constants.zig");

// ============================================================================
// Special Value Detection
// ============================================================================

/// Check if value is positive or negative infinity
pub fn Py_IS_INFINITY(x: f64) bool {
    return std.math.isInf(x);
}

/// Check if value is positive infinity
pub fn Py_IS_POSITIVE_INFINITY(x: f64) bool {
    return std.math.isPositiveInf(x);
}

/// Check if value is negative infinity
pub fn Py_IS_NEGATIVE_INFINITY(x: f64) bool {
    return std.math.isNegativeInf(x);
}

/// Check if value is NaN
pub fn Py_IS_NAN(x: f64) bool {
    return std.math.isNan(x);
}

/// Check if value is finite (not inf or nan)
pub fn Py_IS_FINITE(x: f64) bool {
    return std.math.isFinite(x);
}

/// Check if value is normal (not zero, subnormal, inf, or nan)
pub fn Py_IS_NORMAL(x: f64) bool {
    return std.math.isNormal(x);
}

/// Check if value is subnormal (denormalized)
pub fn Py_IS_SUBNORMAL(x: f64) bool {
    if (Py_IS_NAN(x) or Py_IS_INFINITY(x) or x == 0.0) return false;
    return @abs(x) < constants.DBL_MIN;
}

/// Check if value is zero (positive or negative)
pub fn Py_IS_ZERO(x: f64) bool {
    return x == 0.0;
}

/// Get the sign bit
pub fn Py_SIGN(x: f64) bool {
    return std.math.signbit(x);
}

// ============================================================================
// Float Classification
// ============================================================================

pub const FloatClass = enum {
    nan,
    infinite,
    zero,
    subnormal,
    normal,
};

/// Classify a floating point value
pub fn Py_CLASSIFY(x: f64) FloatClass {
    if (Py_IS_NAN(x)) return .nan;
    if (Py_IS_INFINITY(x)) return .infinite;
    if (x == 0.0) return .zero;
    if (Py_IS_SUBNORMAL(x)) return .subnormal;
    return .normal;
}
