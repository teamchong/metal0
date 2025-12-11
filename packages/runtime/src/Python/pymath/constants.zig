/// Constants and special values
/// Mirrors cpython/Python/pymath.c

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Positive infinity
pub const Py_INFINITY: f64 = std.math.inf(f64);

/// Not a Number
pub const Py_NAN: f64 = std.math.nan(f64);

/// Huge value (largest finite double)
pub const Py_HUGE_VAL: f64 = std.math.floatMax(f64);

/// Machine epsilon for doubles
pub const DBL_EPSILON: f64 = std.math.floatEps(f64);

/// Minimum positive normalized double
pub const DBL_MIN: f64 = std.math.floatMin(f64);

/// Maximum finite double
pub const DBL_MAX: f64 = std.math.floatMax(f64);

/// Number of bits in mantissa
pub const DBL_MANT_DIG: comptime_int = 53;

/// Maximum decimal exponent
pub const DBL_MAX_EXP: comptime_int = 1024;

/// Minimum decimal exponent
pub const DBL_MIN_EXP: comptime_int = -1021;

/// Pi constant
pub const Py_MATH_PI: f64 = std.math.pi;

/// e constant
pub const Py_MATH_E: f64 = std.math.e;

/// Tau (2 * pi)
pub const Py_MATH_TAU: f64 = std.math.tau;
