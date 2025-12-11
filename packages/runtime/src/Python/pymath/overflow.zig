/// Overflow and underflow detection
/// Mirrors cpython/Python/pymath.c

const special_values = @import("special_values.zig");

// ============================================================================
// Overflow and Underflow Detection
// ============================================================================

/// Check if result overflowed to infinity
pub fn Py_OVERFLOWED(result: f64) bool {
    return special_values.Py_IS_INFINITY(result);
}

/// Check if result underflowed to zero
pub fn Py_UNDERFLOWED(result: f64, orig: f64) bool {
    return result == 0.0 and orig != 0.0;
}

/// Check for math domain error
pub fn Py_MATH_DOMAIN_ERROR(result: f64) bool {
    return special_values.Py_IS_NAN(result);
}

/// Adjust negative zero to positive zero
pub fn Py_ADJUST_ZERO(x: f64) f64 {
    return if (x == 0.0) 0.0 else x;
}
