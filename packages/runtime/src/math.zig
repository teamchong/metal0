/// Python math module - mathematical functions
///
/// Provides standard mathematical functions (trigonometry, logarithms, etc.)
/// Compatible with Python's math module API
const std = @import("std");
const runtime = @import("runtime.zig");

// Mathematical constants
pub const pi = std.math.pi;
pub const e = std.math.e;
pub const tau = 2.0 * std.math.pi;
pub const inf = std.math.inf(f64);
pub const nan = std.math.nan(f64);

/// Trigonometric functions
pub fn sin(x: f64) f64 {
    return @sin(x);
}

pub fn cos(x: f64) f64 {
    return @cos(x);
}

pub fn tan(x: f64) f64 {
    return @tan(x);
}

pub fn asin(x: f64) f64 {
    return std.math.asin(x);
}

pub fn acos(x: f64) f64 {
    return std.math.acos(x);
}

pub fn atan(x: f64) f64 {
    return std.math.atan(x);
}

pub fn atan2(y: f64, x: f64) f64 {
    return std.math.atan2(y, x);
}

/// Hyperbolic functions
pub fn sinh(x: f64) f64 {
    return std.math.sinh(x);
}

pub fn cosh(x: f64) f64 {
    return std.math.cosh(x);
}

pub fn tanh(x: f64) f64 {
    return std.math.tanh(x);
}

pub fn asinh(x: f64) f64 {
    return std.math.asinh(x);
}

pub fn acosh(x: f64) f64 {
    return std.math.acosh(x);
}

pub fn atanh(x: f64) f64 {
    return std.math.atanh(x);
}

/// Exponential and logarithmic functions
pub fn exp(x: f64) f64 {
    return @exp(x);
}

pub fn expm1(x: f64) f64 {
    return std.math.expm1(x);
}

pub fn log(x: f64) f64 {
    return @log(x);
}

pub fn log10(x: f64) f64 {
    return @log10(x);
}

pub fn log2(x: f64) f64 {
    return @log2(x);
}

pub fn log1p(x: f64) f64 {
    return std.math.log1p(x);
}

/// Power and root functions
pub fn pow(x: f64, y: f64) f64 {
    return std.math.pow(f64, x, y);
}

pub fn sqrt(x: f64) f64 {
    return @sqrt(x);
}

pub fn cbrt(x: f64) f64 {
    return std.math.cbrt(x);
}

pub fn hypot(x: f64, y: f64) f64 {
    return std.math.hypot(x, y);
}

/// Rounding and absolute value
pub fn ceil(x: f64) f64 {
    return @ceil(x);
}

pub fn floor(x: f64) f64 {
    return @floor(x);
}

pub fn trunc(x: f64) f64 {
    return @trunc(x);
}

pub fn round(x: f64) f64 {
    return @round(x);
}

pub fn fabs(x: f64) f64 {
    return @abs(x);
}

pub fn abs(x: f64) f64 {
    return @abs(x);
}

/// Modulo and remainder
pub fn fmod(x: f64, y: f64) f64 {
    return @mod(x, y);
}

pub fn remainder(x: f64, y: f64) f64 {
    return @rem(x, y);
}

pub fn modf(x: f64) struct { fractional: f64, integral: f64 } {
    const integral = @trunc(x);
    const fractional = x - integral;
    return .{ .fractional = fractional, .integral = integral };
}

/// Special functions
pub fn factorial(n: i64) i64 {
    if (n < 0) return 0; // Error: factorial of negative
    if (n == 0 or n == 1) return 1;

    var result: i64 = 1;
    var i: i64 = 2;
    while (i <= n) : (i += 1) {
        result *= i;
    }
    return result;
}

pub fn gcd(a: i64, b: i64) i64 {
    var x = @abs(a);
    var y = @abs(b);

    while (y != 0) {
        const temp = y;
        y = @rem(x, y);
        x = temp;
    }

    return x;
}

pub fn lcm(a: i64, b: i64) i64 {
    if (a == 0 or b == 0) return 0;
    return @abs(a * b) / gcd(a, b);
}

/// Comparison and testing
/// Handles both f64 and PyPowResult types
pub fn isnan(x: anytype) bool {
    const T = @TypeOf(x);
    if (T == f64 or T == f32) {
        return std.math.isNan(x);
    }
    // Handle PyPowResult via its isNan method
    if (@hasDecl(T, "isNan")) {
        return x.isNan();
    }
    // For structs with float_val field (PyPowResult union)
    if (@typeInfo(T) == .@"union" and @hasField(T, "float_val")) {
        return x.isNan();
    }
    return false;
}

pub fn isinf(x: anytype) bool {
    const T = @TypeOf(x);
    if (T == f64 or T == f32) {
        return std.math.isInf(x);
    }
    // Handle PyPowResult via its isInf method
    if (@hasDecl(T, "isInf")) {
        return x.isInf();
    }
    // For structs with float_val field (PyPowResult union)
    if (@typeInfo(T) == .@"union" and @hasField(T, "float_val")) {
        return x.isInf();
    }
    return false;
}

pub fn isfinite(x: anytype) bool {
    const T = @TypeOf(x);
    if (T == f64 or T == f32) {
        return std.math.isFinite(x);
    }
    // For PyPowResult, check both isNan and isInf
    if (@hasDecl(T, "isNan") and @hasDecl(T, "isInf")) {
        return !x.isNan() and !x.isInf();
    }
    return true;
}

pub fn copysign(x: anytype, y: anytype) f64 {
    const X = @TypeOf(x);
    const Y = @TypeOf(y);

    // Convert x to f64
    const xf: f64 = if (X == f64)
        x
    else if (@hasDecl(X, "toFloat"))
        x.toFloat()
    else if (@typeInfo(X) == .@"union" and @hasField(X, "float_val"))
        x.toFloat()
    else
        @as(f64, x);

    // Convert y to f64
    const yf: f64 = if (Y == f64)
        y
    else if (@hasDecl(Y, "toFloat"))
        y.toFloat()
    else if (@typeInfo(Y) == .@"union" and @hasField(Y, "float_val"))
        y.toFloat()
    else
        @as(f64, y);

    return std.math.copysign(xf, yf);
}

/// Conversion
pub fn degrees(rad: f64) f64 {
    return rad * (180.0 / std.math.pi);
}

pub fn radians(deg: f64) f64 {
    return deg * (std.math.pi / 180.0);
}

/// Error function (erf) and complementary error function (erfc)
/// Approximations for now - can improve precision later
pub fn erf(x: f64) f64 {
    // Abramowitz and Stegun approximation
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;

    const sign: f64 = if (x < 0) -1.0 else 1.0;
    const abs_x = @abs(x);

    const t = 1.0 / (1.0 + p * abs_x);
    const t2 = t * t;
    const t3 = t2 * t;
    const t4 = t3 * t;
    const t5 = t4 * t;

    const y = 1.0 - (((((a5 * t5 + a4 * t4) + a3 * t3) + a2 * t2) + a1 * t) * @exp(-abs_x * abs_x));
    return sign * y;
}

pub fn erfc(x: f64) f64 {
    return 1.0 - erf(x);
}

pub fn gamma(x: f64) f64 {
    // Stirling's approximation for large x
    // For small x, use recurrence relation
    if (x < 0.5) {
        // Use reflection formula: Γ(1-x)Γ(x) = π/sin(πx)
        return std.math.pi / (@sin(std.math.pi * x) * gamma(1.0 - x));
    }

    // Stirling's approximation
    const x_minus_1 = x - 1.0;
    return @sqrt(2.0 * std.math.pi / x_minus_1) *
        std.math.pow(f64, x_minus_1 / std.math.e, x_minus_1);
}

pub fn lgamma(x: f64) f64 {
    return @log(gamma(x));
}

// Tests
test "math constants" {
    try std.testing.expect(pi > 3.14 and pi < 3.15);
    try std.testing.expect(e > 2.71 and e < 2.72);
}

test "trigonometric functions" {
    try std.testing.expectApproxEqAbs(sin(0.0), 0.0, 0.0001);
    try std.testing.expectApproxEqAbs(cos(0.0), 1.0, 0.0001);
    try std.testing.expectApproxEqAbs(tan(0.0), 0.0, 0.0001);
}

test "power functions" {
    try std.testing.expectApproxEqAbs(sqrt(4.0), 2.0, 0.0001);
    try std.testing.expectApproxEqAbs(pow(2.0, 3.0), 8.0, 0.0001);
}

test "factorial and gcd" {
    try std.testing.expectEqual(factorial(5), 120);
    try std.testing.expectEqual(gcd(48, 18), 6);
}
