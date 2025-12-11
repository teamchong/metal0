/// Hyperbolic functions
/// Mirrors cpython/Python/pymath.c

const std = @import("std");

// ============================================================================
// Hyperbolic Functions
// ============================================================================

/// Hyperbolic sine
pub fn Py_SINH(x: f64) f64 {
    return std.math.sinh(x);
}

/// Hyperbolic cosine
pub fn Py_COSH(x: f64) f64 {
    return std.math.cosh(x);
}

/// Hyperbolic tangent
pub fn Py_TANH(x: f64) f64 {
    return std.math.tanh(x);
}

/// Inverse hyperbolic sine
pub fn Py_ASINH(x: f64) f64 {
    return std.math.asinh(x);
}

/// Inverse hyperbolic cosine
pub fn Py_ACOSH(x: f64) f64 {
    return std.math.acosh(x);
}

/// Inverse hyperbolic tangent
pub fn Py_ATANH(x: f64) f64 {
    return std.math.atanh(x);
}
