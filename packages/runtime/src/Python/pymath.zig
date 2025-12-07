/// pymath - Python Math Functions
/// Mirrors cpython/Python/pymath.c
///
/// This module provides low-level math utilities used by the Python runtime:
/// - IEEE 754 special value handling (inf, nan)
/// - Platform-independent math operations
/// - Overflow and underflow detection

const std = @import("std");
const builtin = @import("builtin");

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
    return @abs(x) < DBL_MIN;
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

/// Round to nearest integer
pub fn Py_ROUND(x: f64) f64 {
    return @round(x);
}

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
    if (y == 0) return Py_NAN;

    // IEEE 754 remainder: x - n*y where n is the nearest integer to x/y
    const n = @round(x / y);
    return x - n * y;
}

/// Get next representable value
pub fn Py_NEXTAFTER(x: f64, y: f64) f64 {
    if (Py_IS_NAN(x) or Py_IS_NAN(y)) return Py_NAN;
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

// ============================================================================
// Overflow and Underflow Detection
// ============================================================================

/// Check if result overflowed to infinity
pub fn Py_OVERFLOWED(result: f64) bool {
    return Py_IS_INFINITY(result);
}

/// Check if result underflowed to zero
pub fn Py_UNDERFLOWED(result: f64, orig: f64) bool {
    return result == 0.0 and orig != 0.0;
}

/// Check for math domain error
pub fn Py_MATH_DOMAIN_ERROR(result: f64) bool {
    return Py_IS_NAN(result);
}

/// Adjust negative zero to positive zero
pub fn Py_ADJUST_ZERO(x: f64) f64 {
    return if (x == 0.0) 0.0 else x;
}

// ============================================================================
// Integer Operations
// ============================================================================

/// Count leading zeros in 32-bit integer
pub fn Py_CLZ32(x: u32) u32 {
    if (x == 0) return 32;
    return @clz(x);
}

/// Count leading zeros in 64-bit integer
pub fn Py_CLZ64(x: u64) u64 {
    if (x == 0) return 64;
    return @clz(x);
}

/// Count trailing zeros in 32-bit integer
pub fn Py_CTZ32(x: u32) u32 {
    if (x == 0) return 32;
    return @ctz(x);
}

/// Count trailing zeros in 64-bit integer
pub fn Py_CTZ64(x: u64) u64 {
    if (x == 0) return 64;
    return @ctz(x);
}

/// Population count (number of 1 bits)
pub fn Py_POPCOUNT32(x: u32) u32 {
    return @popCount(x);
}

/// Population count (number of 1 bits)
pub fn Py_POPCOUNT64(x: u64) u64 {
    return @popCount(x);
}

/// Bit length (position of highest set bit)
pub fn Py_BIT_LENGTH32(x: u32) u32 {
    if (x == 0) return 0;
    return 32 - @clz(x);
}

/// Bit length (position of highest set bit)
pub fn Py_BIT_LENGTH64(x: u64) u64 {
    if (x == 0) return 0;
    return 64 - @clz(x);
}

// ============================================================================
// Safe Arithmetic
// ============================================================================

/// Checked addition
pub fn Py_SAFE_ADD(a: i64, b: i64) ?i64 {
    const result = @addWithOverflow(a, b);
    return if (result[1] != 0) null else result[0];
}

/// Checked subtraction
pub fn Py_SAFE_SUB(a: i64, b: i64) ?i64 {
    const result = @subWithOverflow(a, b);
    return if (result[1] != 0) null else result[0];
}

/// Checked multiplication
pub fn Py_SAFE_MUL(a: i64, b: i64) ?i64 {
    const result = @mulWithOverflow(a, b);
    return if (result[1] != 0) null else result[0];
}

/// Saturating addition
pub fn Py_SATURATE_ADD(a: i64, b: i64) i64 {
    return a +| b;
}

/// Saturating subtraction
pub fn Py_SATURATE_SUB(a: i64, b: i64) i64 {
    return a -| b;
}

/// Saturating multiplication
pub fn Py_SATURATE_MUL(a: i64, b: i64) i64 {
    return a *| b;
}

// ============================================================================
// Utilities
// ============================================================================

/// Greatest common divisor
pub fn Py_GCD(a: u64, b: u64) u64 {
    if (b == 0) return a;
    return Py_GCD(b, a % b);
}

/// Least common multiple
pub fn Py_LCM(a: u64, b: u64) u64 {
    if (a == 0 or b == 0) return 0;
    return (a / Py_GCD(a, b)) * b;
}

/// Integer square root
pub fn Py_ISQRT(n: u64) u64 {
    if (n < 2) return n;

    var x = n;
    var y = (x + 1) / 2;

    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }

    return x;
}

/// Check if integer is power of 2
pub fn Py_IS_POWER_OF_TWO(n: u64) bool {
    return n != 0 and (n & (n - 1)) == 0;
}

/// Round up to next power of 2
pub fn Py_NEXT_POWER_OF_TWO(n: u64) u64 {
    if (n == 0) return 1;
    if (Py_IS_POWER_OF_TWO(n)) return n;
    return @as(u64, 1) << @intCast(64 - @clz(n));
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
