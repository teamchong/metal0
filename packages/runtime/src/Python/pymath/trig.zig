/// Trigonometric functions
/// Mirrors cpython/Python/pymath.c

const std = @import("std");

// ============================================================================
// Trigonometric Functions
// ============================================================================

/// Sine
pub fn Py_SIN(x: f64) f64 {
    return @sin(x);
}

/// Cosine
pub fn Py_COS(x: f64) f64 {
    return @cos(x);
}

/// Tangent
pub fn Py_TAN(x: f64) f64 {
    return @tan(x);
}

/// Arc sine
pub fn Py_ASIN(x: f64) f64 {
    return std.math.asin(x);
}

/// Arc cosine
pub fn Py_ACOS(x: f64) f64 {
    return std.math.acos(x);
}

/// Arc tangent
pub fn Py_ATAN(x: f64) f64 {
    return std.math.atan(x);
}

/// Arc tangent of y/x
pub fn Py_ATAN2(y: f64, x: f64) f64 {
    return std.math.atan2(y, x);
}
