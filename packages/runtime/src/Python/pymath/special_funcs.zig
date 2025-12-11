/// Special functions (erf, gamma, etc.)
/// Mirrors cpython/Python/pymath.c

const std = @import("std");

// ============================================================================
// Special Functions
// ============================================================================

/// Error function
pub fn Py_ERF(x: f64) f64 {
    return std.math.erf(x);
}

/// Complementary error function
pub fn Py_ERFC(x: f64) f64 {
    return std.math.erfc(x);
}

/// Gamma function
pub fn Py_TGAMMA(x: f64) f64 {
    return std.math.gamma(f64, x);
}

/// Natural log of gamma function
pub fn Py_LGAMMA(x: f64) f64 {
    return std.math.lgamma(f64, x);
}
