/// pymath - Python Math Functions
/// Mirrors cpython/Python/pymath.c
///
/// This module provides low-level math utilities used by the Python runtime:
/// - IEEE 754 special value handling (inf, nan)
/// - Platform-independent math operations
/// - Overflow and underflow detection

const std = @import("std");
const builtin = @import("builtin");

// Submodules
pub const constants = @import("pymath/constants.zig");
pub const special_values = @import("pymath/special_values.zig");
pub const basic_ops = @import("pymath/basic_ops.zig");
pub const trig = @import("pymath/trig.zig");
pub const hyperbolic = @import("pymath/hyperbolic.zig");
pub const special_funcs = @import("pymath/special_funcs.zig");
pub const ieee754 = @import("pymath/ieee754.zig");
pub const overflow = @import("pymath/overflow.zig");
pub const int_ops = @import("pymath/int_ops.zig");
pub const safe_arith = @import("pymath/safe_arith.zig");
pub const utilities = @import("pymath/utilities.zig");

// ============================================================================
// Re-export all public symbols
// ============================================================================

// Constants
pub const Py_INFINITY = constants.Py_INFINITY;
pub const Py_NAN = constants.Py_NAN;
pub const Py_HUGE_VAL = constants.Py_HUGE_VAL;
pub const DBL_EPSILON = constants.DBL_EPSILON;
pub const DBL_MIN = constants.DBL_MIN;
pub const DBL_MAX = constants.DBL_MAX;
pub const DBL_MANT_DIG = constants.DBL_MANT_DIG;
pub const DBL_MAX_EXP = constants.DBL_MAX_EXP;
pub const DBL_MIN_EXP = constants.DBL_MIN_EXP;
pub const Py_MATH_PI = constants.Py_MATH_PI;
pub const Py_MATH_E = constants.Py_MATH_E;
pub const Py_MATH_TAU = constants.Py_MATH_TAU;

// Special value detection
pub const Py_IS_INFINITY = special_values.Py_IS_INFINITY;
pub const Py_IS_POSITIVE_INFINITY = special_values.Py_IS_POSITIVE_INFINITY;
pub const Py_IS_NEGATIVE_INFINITY = special_values.Py_IS_NEGATIVE_INFINITY;
pub const Py_IS_NAN = special_values.Py_IS_NAN;
pub const Py_IS_FINITE = special_values.Py_IS_FINITE;
pub const Py_IS_NORMAL = special_values.Py_IS_NORMAL;
pub const Py_IS_SUBNORMAL = special_values.Py_IS_SUBNORMAL;
pub const Py_IS_ZERO = special_values.Py_IS_ZERO;
pub const Py_SIGN = special_values.Py_SIGN;
pub const FloatClass = special_values.FloatClass;
pub const Py_CLASSIFY = special_values.Py_CLASSIFY;

// Basic operations
pub const Py_ABS = basic_ops.Py_ABS;
pub const Py_FLOOR = basic_ops.Py_FLOOR;
pub const Py_CEIL = basic_ops.Py_CEIL;
pub const Py_TRUNC = basic_ops.Py_TRUNC;
pub const Py_ROUND = basic_ops.Py_ROUND;
pub const Py_SQRT = basic_ops.Py_SQRT;
pub const Py_EXP = basic_ops.Py_EXP;
pub const Py_LOG = basic_ops.Py_LOG;
pub const Py_LOG10 = basic_ops.Py_LOG10;
pub const Py_LOG2 = basic_ops.Py_LOG2;
pub const Py_POW = basic_ops.Py_POW;
pub const Py_HYPOT = basic_ops.Py_HYPOT;
pub const Py_COPYSIGN = basic_ops.Py_COPYSIGN;
pub const Py_FMA = basic_ops.Py_FMA;

// Trigonometric functions
pub const Py_SIN = trig.Py_SIN;
pub const Py_COS = trig.Py_COS;
pub const Py_TAN = trig.Py_TAN;
pub const Py_ASIN = trig.Py_ASIN;
pub const Py_ACOS = trig.Py_ACOS;
pub const Py_ATAN = trig.Py_ATAN;
pub const Py_ATAN2 = trig.Py_ATAN2;

// Hyperbolic functions
pub const Py_SINH = hyperbolic.Py_SINH;
pub const Py_COSH = hyperbolic.Py_COSH;
pub const Py_TANH = hyperbolic.Py_TANH;
pub const Py_ASINH = hyperbolic.Py_ASINH;
pub const Py_ACOSH = hyperbolic.Py_ACOSH;
pub const Py_ATANH = hyperbolic.Py_ATANH;

// Special functions
pub const Py_ERF = special_funcs.Py_ERF;
pub const Py_ERFC = special_funcs.Py_ERFC;
pub const Py_TGAMMA = special_funcs.Py_TGAMMA;
pub const Py_LGAMMA = special_funcs.Py_LGAMMA;

// IEEE 754 operations
pub const Py_FREXP = ieee754.Py_FREXP;
pub const Py_LDEXP = ieee754.Py_LDEXP;
pub const Py_MODF = ieee754.Py_MODF;
pub const Py_FMOD = ieee754.Py_FMOD;
pub const Py_REMAINDER = ieee754.Py_REMAINDER;
pub const Py_NEXTAFTER = ieee754.Py_NEXTAFTER;

// Overflow and underflow detection
pub const Py_OVERFLOWED = overflow.Py_OVERFLOWED;
pub const Py_UNDERFLOWED = overflow.Py_UNDERFLOWED;
pub const Py_MATH_DOMAIN_ERROR = overflow.Py_MATH_DOMAIN_ERROR;
pub const Py_ADJUST_ZERO = overflow.Py_ADJUST_ZERO;

// Integer operations
pub const Py_CLZ32 = int_ops.Py_CLZ32;
pub const Py_CLZ64 = int_ops.Py_CLZ64;
pub const Py_CTZ32 = int_ops.Py_CTZ32;
pub const Py_CTZ64 = int_ops.Py_CTZ64;
pub const Py_POPCOUNT32 = int_ops.Py_POPCOUNT32;
pub const Py_POPCOUNT64 = int_ops.Py_POPCOUNT64;
pub const Py_BIT_LENGTH32 = int_ops.Py_BIT_LENGTH32;
pub const Py_BIT_LENGTH64 = int_ops.Py_BIT_LENGTH64;

// Safe arithmetic
pub const Py_SAFE_ADD = safe_arith.Py_SAFE_ADD;
pub const Py_SAFE_SUB = safe_arith.Py_SAFE_SUB;
pub const Py_SAFE_MUL = safe_arith.Py_SAFE_MUL;
pub const Py_SATURATE_ADD = safe_arith.Py_SATURATE_ADD;
pub const Py_SATURATE_SUB = safe_arith.Py_SATURATE_SUB;
pub const Py_SATURATE_MUL = safe_arith.Py_SATURATE_MUL;

// Utilities
pub const Py_GCD = utilities.Py_GCD;
pub const Py_LCM = utilities.Py_LCM;
pub const Py_ISQRT = utilities.Py_ISQRT;
pub const Py_IS_POWER_OF_TWO = utilities.Py_IS_POWER_OF_TWO;
pub const Py_NEXT_POWER_OF_TWO = utilities.Py_NEXT_POWER_OF_TWO;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize math module (no-op on most platforms)
pub fn init() void {
    // No initialization needed - Zig handles IEEE 754 properly
}

// ============================================================================
// Tests
// ============================================================================

test "special values" {
    try std.testing.expect(Py_IS_INFINITY(Py_INFINITY));
    try std.testing.expect(Py_IS_INFINITY(-Py_INFINITY));
    try std.testing.expect(!Py_IS_INFINITY(1.0));
    try std.testing.expect(Py_IS_NAN(Py_NAN));
    try std.testing.expect(!Py_IS_NAN(1.0));
    try std.testing.expect(Py_IS_FINITE(1.0));
    try std.testing.expect(!Py_IS_FINITE(Py_INFINITY));
    try std.testing.expect(!Py_IS_FINITE(Py_NAN));
}

test "basic math" {
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), Py_SQRT(9.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), Py_POW(2.0, 3.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), Py_ABS(-5.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), Py_FLOOR(3.7), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), Py_CEIL(3.2), 0.0001);
}

test "trigonometry" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), Py_SIN(0.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), Py_COS(0.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), Py_TAN(0.0), 0.0001);
}

test "frexp and ldexp" {
    const result = Py_FREXP(8.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result.frac, 0.0001);
    try std.testing.expectEqual(@as(i32, 4), result.exp);

    const reconstructed = Py_LDEXP(result.frac, result.exp);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), reconstructed, 0.0001);
}

test "modf" {
    const result = Py_MODF(3.75);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result.int_part, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), result.frac_part, 0.0001);
}

test "copysign" {
    try std.testing.expectApproxEqAbs(@as(f64, -3.0), Py_COPYSIGN(3.0, -1.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), Py_COPYSIGN(-3.0, 1.0), 0.0001);
}

test "integer bit operations" {
    try std.testing.expectEqual(@as(u32, 29), Py_CLZ32(0b111));
    try std.testing.expectEqual(@as(u32, 0), Py_CTZ32(0b111));
    try std.testing.expectEqual(@as(u32, 3), Py_POPCOUNT32(0b111));
    try std.testing.expectEqual(@as(u32, 3), Py_BIT_LENGTH32(0b111));
}

test "safe arithmetic" {
    try std.testing.expectEqual(@as(?i64, 3), Py_SAFE_ADD(1, 2));
    try std.testing.expectEqual(@as(?i64, null), Py_SAFE_ADD(std.math.maxInt(i64), 1));
    try std.testing.expectEqual(@as(?i64, 6), Py_SAFE_MUL(2, 3));
}

test "gcd and lcm" {
    try std.testing.expectEqual(@as(u64, 6), Py_GCD(12, 18));
    try std.testing.expectEqual(@as(u64, 36), Py_LCM(12, 18));
}

test "isqrt" {
    try std.testing.expectEqual(@as(u64, 3), Py_ISQRT(9));
    try std.testing.expectEqual(@as(u64, 3), Py_ISQRT(10));
    try std.testing.expectEqual(@as(u64, 10), Py_ISQRT(100));
}

test "power of two" {
    try std.testing.expect(Py_IS_POWER_OF_TWO(8));
    try std.testing.expect(!Py_IS_POWER_OF_TWO(7));
    try std.testing.expectEqual(@as(u64, 8), Py_NEXT_POWER_OF_TWO(5));
    try std.testing.expectEqual(@as(u64, 8), Py_NEXT_POWER_OF_TWO(8));
}

test "float classification" {
    try std.testing.expectEqual(FloatClass.normal, Py_CLASSIFY(1.0));
    try std.testing.expectEqual(FloatClass.zero, Py_CLASSIFY(0.0));
    try std.testing.expectEqual(FloatClass.infinite, Py_CLASSIFY(Py_INFINITY));
    try std.testing.expectEqual(FloatClass.nan, Py_CLASSIFY(Py_NAN));
}
