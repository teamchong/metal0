//! CPython source: Lib/numbers.py
//!
//! Defines the hierarchy of numeric abstract base classes:
//! Number :> Complex :> Real :> Rational :> Integral
//!
//! Mirrors: CPython Lib/numbers.py

const std = @import("std");

// ============================================================================
// Number - Root of the numeric tower
// ============================================================================

/// Abstract base class for numeric types.
/// All numeric types should be registered as virtual subclasses of Number.
pub const Number = struct {
    /// Type tag for runtime type checking
    pub const Tag = enum {
        integral,
        rational,
        real,
        complex,
    };

    tag: Tag,
    data: Data,

    pub const Data = union {
        integral: i64,
        rational: struct { numerator: i64, denominator: i64 },
        real: f64,
        complex: struct { real: f64, imag: f64 },
    };

    /// Check if a value is an instance of Number
    pub fn isNumber(comptime T: type) bool {
        return @typeInfo(T) == .int or
            @typeInfo(T) == .float or
            @typeInfo(T) == .comptime_int or
            @typeInfo(T) == .comptime_float;
    }
};

// ============================================================================
// Complex - Complex numbers with real and imaginary parts
// ============================================================================

/// Abstract base class for complex numbers.
pub const Complex = struct {
    real: f64,
    imag: f64,

    pub fn init(real: f64, imag: f64) Complex {
        return .{ .real = real, .imag = imag };
    }

    /// Return the real part
    pub fn realPart(self: Complex) f64 {
        return self.real;
    }

    /// Return the imaginary part
    pub fn imagPart(self: Complex) f64 {
        return self.imag;
    }

    /// Return the complex conjugate
    pub fn conjugate(self: Complex) Complex {
        return .{ .real = self.real, .imag = -self.imag };
    }

    /// Add two complex numbers
    pub fn add(a: Complex, b: Complex) Complex {
        return .{
            .real = a.real + b.real,
            .imag = a.imag + b.imag,
        };
    }

    /// Subtract two complex numbers
    pub fn sub(a: Complex, b: Complex) Complex {
        return .{
            .real = a.real - b.real,
            .imag = a.imag - b.imag,
        };
    }

    /// Multiply two complex numbers
    pub fn mul(a: Complex, b: Complex) Complex {
        return .{
            .real = a.real * b.real - a.imag * b.imag,
            .imag = a.real * b.imag + a.imag * b.real,
        };
    }

    /// Divide two complex numbers
    pub fn div(a: Complex, b: Complex) !Complex {
        const denom = b.real * b.real + b.imag * b.imag;
        if (denom == 0) return error.ZeroDivision;
        return .{
            .real = (a.real * b.real + a.imag * b.imag) / denom,
            .imag = (a.imag * b.real - a.real * b.imag) / denom,
        };
    }

    /// Negate
    pub fn neg(self: Complex) Complex {
        return .{ .real = -self.real, .imag = -self.imag };
    }

    /// Positive (unary +)
    pub fn pos(self: Complex) Complex {
        return self;
    }

    /// Absolute value (magnitude)
    pub fn abs(self: Complex) f64 {
        return @sqrt(self.real * self.real + self.imag * self.imag);
    }

    /// Check equality
    pub fn eql(a: Complex, b: Complex) bool {
        return a.real == b.real and a.imag == b.imag;
    }

    /// Check if a type is complex-like
    pub fn isComplex(comptime T: type) bool {
        return T == Complex or (Number.isNumber(T));
    }
};

// ============================================================================
// Real - Real numbers (subset of complex with imag = 0)
// ============================================================================

/// Abstract base class for real numbers.
/// Real numbers are a subset of complex numbers.
pub const Real = struct {
    value: f64,

    pub fn init(value: f64) Real {
        return .{ .value = value };
    }

    /// Convert to float
    pub fn toFloat(self: Real) f64 {
        return self.value;
    }

    /// Return the real part (the value itself)
    pub fn realPart(self: Real) f64 {
        return self.value;
    }

    /// Return the imaginary part (always 0)
    pub fn imagPart(_: Real) f64 {
        return 0.0;
    }

    /// Conjugate of a real is itself
    pub fn conjugate(self: Real) Real {
        return self;
    }

    /// Truncate towards zero
    pub fn trunc(self: Real) i64 {
        return @intFromFloat(@trunc(self.value));
    }

    /// Floor division
    pub fn floor(self: Real) i64 {
        return @intFromFloat(@floor(self.value));
    }

    /// Ceiling
    pub fn ceil(self: Real) i64 {
        return @intFromFloat(@ceil(self.value));
    }

    /// Round to nearest integer
    pub fn round(self: Real) i64 {
        return @intFromFloat(@round(self.value));
    }

    // Arithmetic operations

    pub fn add(a: Real, b: Real) Real {
        return .{ .value = a.value + b.value };
    }

    pub fn sub(a: Real, b: Real) Real {
        return .{ .value = a.value - b.value };
    }

    pub fn mul(a: Real, b: Real) Real {
        return .{ .value = a.value * b.value };
    }

    pub fn div(a: Real, b: Real) !Real {
        if (b.value == 0) return error.ZeroDivision;
        return .{ .value = a.value / b.value };
    }

    pub fn floordiv(a: Real, b: Real) !Real {
        if (b.value == 0) return error.ZeroDivision;
        return .{ .value = @floor(a.value / b.value) };
    }

    pub fn mod(a: Real, b: Real) !Real {
        if (b.value == 0) return error.ZeroDivision;
        return .{ .value = @mod(a.value, b.value) };
    }

    pub fn neg(self: Real) Real {
        return .{ .value = -self.value };
    }

    pub fn pos(self: Real) Real {
        return self;
    }

    pub fn abs(self: Real) Real {
        return .{ .value = @abs(self.value) };
    }

    // Comparisons

    pub fn lessThan(a: Real, b: Real) bool {
        return a.value < b.value;
    }

    pub fn lessThanOrEqual(a: Real, b: Real) bool {
        return a.value <= b.value;
    }

    pub fn greaterThan(a: Real, b: Real) bool {
        return a.value > b.value;
    }

    pub fn greaterThanOrEqual(a: Real, b: Real) bool {
        return a.value >= b.value;
    }

    pub fn eql(a: Real, b: Real) bool {
        return a.value == b.value;
    }

    /// Check if a type is real-like
    pub fn isReal(comptime T: type) bool {
        return @typeInfo(T) == .float or
            @typeInfo(T) == .int or
            @typeInfo(T) == .comptime_float or
            @typeInfo(T) == .comptime_int;
    }
};

// ============================================================================
// Rational - Rational numbers (numerator/denominator)
// ============================================================================

/// Abstract base class for rational numbers.
/// Includes properties numerator and denominator.
pub const Rational = struct {
    numerator: i64,
    denominator: i64,

    pub fn init(numerator: i64, denominator: i64) !Rational {
        if (denominator == 0) return error.ZeroDivision;

        var num = numerator;
        var den = denominator;

        // Normalize sign
        if (den < 0) {
            num = -num;
            den = -den;
        }

        // Reduce to lowest terms
        const g = gcd(@abs(num), @abs(den));
        return .{
            .numerator = @divTrunc(num, @as(i64, @intCast(g))),
            .denominator = @divTrunc(den, @as(i64, @intCast(g))),
        };
    }

    pub fn fromInt(n: i64) Rational {
        return .{ .numerator = n, .denominator = 1 };
    }

    /// Convert to float
    pub fn toFloat(self: Rational) f64 {
        return @as(f64, @floatFromInt(self.numerator)) / @as(f64, @floatFromInt(self.denominator));
    }

    /// Add two rationals
    pub fn add(a: Rational, b: Rational) !Rational {
        const num = a.numerator * b.denominator + b.numerator * a.denominator;
        const den = a.denominator * b.denominator;
        return init(num, den);
    }

    /// Subtract two rationals
    pub fn sub(a: Rational, b: Rational) !Rational {
        const num = a.numerator * b.denominator - b.numerator * a.denominator;
        const den = a.denominator * b.denominator;
        return init(num, den);
    }

    /// Multiply two rationals
    pub fn mul(a: Rational, b: Rational) !Rational {
        const num = a.numerator * b.numerator;
        const den = a.denominator * b.denominator;
        return init(num, den);
    }

    /// Divide two rationals
    pub fn div(a: Rational, b: Rational) !Rational {
        if (b.numerator == 0) return error.ZeroDivision;
        const num = a.numerator * b.denominator;
        const den = a.denominator * b.numerator;
        return init(num, den);
    }

    /// Floor division
    pub fn floordiv(a: Rational, b: Rational) !Rational {
        if (b.numerator == 0) return error.ZeroDivision;
        const num = a.numerator * b.denominator;
        const den = a.denominator * b.numerator;
        const result = @divFloor(num, den);
        return fromInt(result);
    }

    pub fn neg(self: Rational) Rational {
        return .{ .numerator = -self.numerator, .denominator = self.denominator };
    }

    pub fn abs(self: Rational) Rational {
        return .{
            .numerator = if (self.numerator < 0) -self.numerator else self.numerator,
            .denominator = self.denominator,
        };
    }

    /// Compare two rationals
    pub fn cmp(a: Rational, b: Rational) std.math.Order {
        const lhs = a.numerator * b.denominator;
        const rhs = b.numerator * a.denominator;
        return std.math.order(lhs, rhs);
    }

    pub fn eql(a: Rational, b: Rational) bool {
        return a.numerator == b.numerator and a.denominator == b.denominator;
    }

    pub fn lessThan(a: Rational, b: Rational) bool {
        return cmp(a, b) == .lt;
    }

    /// Check if a type is rational-like
    pub fn isRational(comptime T: type) bool {
        return T == Rational or Integral.isIntegral(T);
    }
};

// ============================================================================
// Integral - Whole numbers
// ============================================================================

/// Abstract base class for integral numbers (integers).
pub const Integral = struct {
    value: i64,

    pub fn init(value: i64) Integral {
        return .{ .value = value };
    }

    /// Convert to int
    pub fn toInt(self: Integral) i64 {
        return self.value;
    }

    /// Numerator (for Rational interface)
    pub fn numerator(self: Integral) i64 {
        return self.value;
    }

    /// Denominator (for Rational interface)
    pub fn denominator(_: Integral) i64 {
        return 1;
    }

    // Arithmetic operations

    pub fn add(a: Integral, b: Integral) Integral {
        return .{ .value = a.value + b.value };
    }

    pub fn sub(a: Integral, b: Integral) Integral {
        return .{ .value = a.value - b.value };
    }

    pub fn mul(a: Integral, b: Integral) Integral {
        return .{ .value = a.value * b.value };
    }

    pub fn div(a: Integral, b: Integral) !Integral {
        if (b.value == 0) return error.ZeroDivision;
        return .{ .value = @divTrunc(a.value, b.value) };
    }

    pub fn floordiv(a: Integral, b: Integral) !Integral {
        if (b.value == 0) return error.ZeroDivision;
        return .{ .value = @divFloor(a.value, b.value) };
    }

    pub fn mod(a: Integral, b: Integral) !Integral {
        if (b.value == 0) return error.ZeroDivision;
        return .{ .value = @mod(a.value, b.value) };
    }

    pub fn neg(self: Integral) Integral {
        return .{ .value = -self.value };
    }

    pub fn pos(self: Integral) Integral {
        return self;
    }

    pub fn abs(self: Integral) Integral {
        return .{ .value = if (self.value < 0) -self.value else self.value };
    }

    // Bit operations

    pub fn bitwiseAnd(a: Integral, b: Integral) Integral {
        return .{ .value = a.value & b.value };
    }

    pub fn bitwiseOr(a: Integral, b: Integral) Integral {
        return .{ .value = a.value | b.value };
    }

    pub fn bitwiseXor(a: Integral, b: Integral) Integral {
        return .{ .value = a.value ^ b.value };
    }

    pub fn bitwiseNot(self: Integral) Integral {
        return .{ .value = ~self.value };
    }

    pub fn leftShift(self: Integral, n: u6) Integral {
        return .{ .value = self.value << n };
    }

    pub fn rightShift(self: Integral, n: u6) Integral {
        return .{ .value = self.value >> n };
    }

    // Comparisons

    pub fn lessThan(a: Integral, b: Integral) bool {
        return a.value < b.value;
    }

    pub fn lessThanOrEqual(a: Integral, b: Integral) bool {
        return a.value <= b.value;
    }

    pub fn greaterThan(a: Integral, b: Integral) bool {
        return a.value > b.value;
    }

    pub fn greaterThanOrEqual(a: Integral, b: Integral) bool {
        return a.value >= b.value;
    }

    pub fn eql(a: Integral, b: Integral) bool {
        return a.value == b.value;
    }

    /// Check if a type is integral-like
    pub fn isIntegral(comptime T: type) bool {
        return @typeInfo(T) == .int or @typeInfo(T) == .comptime_int;
    }
};

// ============================================================================
// Utility functions
// ============================================================================

/// Greatest common divisor
fn gcd(a: anytype, b: anytype) @TypeOf(a) {
    var x = if (a < 0) -a else a;
    var y = if (b < 0) -b else b;

    while (y != 0) {
        const t = y;
        y = @rem(x, y);
        x = t;
    }
    return x;
}

// ============================================================================
// Type checking functions (for runtime use)
// ============================================================================

/// Check if a value is an instance of the numeric tower
pub fn isNumber(comptime T: type) bool {
    return Number.isNumber(T);
}

pub fn isComplex(comptime T: type) bool {
    return Complex.isComplex(T);
}

pub fn isReal(comptime T: type) bool {
    return Real.isReal(T);
}

pub fn isRational(comptime T: type) bool {
    return Rational.isRational(T);
}

pub fn isIntegral(comptime T: type) bool {
    return Integral.isIntegral(T);
}

// ============================================================================
// Tests
// ============================================================================

test "Complex operations" {
    const a = Complex.init(3, 4);
    const b = Complex.init(1, 2);

    const sum = Complex.add(a, b);
    try std.testing.expectApproxEqAbs(@as(f64, 4), sum.real, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 6), sum.imag, 0.001);

    const product = Complex.mul(a, b);
    try std.testing.expectApproxEqAbs(@as(f64, -5), product.real, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 10), product.imag, 0.001);

    try std.testing.expectApproxEqAbs(@as(f64, 5), a.abs(), 0.001);
}

test "Complex conjugate" {
    const c = Complex.init(3, 4);
    const conj = c.conjugate();
    try std.testing.expectApproxEqAbs(@as(f64, 3), conj.real, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, -4), conj.imag, 0.001);
}

test "Real operations" {
    const a = Real.init(3.5);
    const b = Real.init(2.0);

    const sum = Real.add(a, b);
    try std.testing.expectApproxEqAbs(@as(f64, 5.5), sum.value, 0.001);

    try std.testing.expectEqual(@as(i64, 3), a.trunc());
    try std.testing.expectEqual(@as(i64, 3), a.floor());
    try std.testing.expectEqual(@as(i64, 4), a.ceil());
}

test "Real comparisons" {
    const a = Real.init(3.5);
    const b = Real.init(2.0);

    try std.testing.expect(Real.greaterThan(a, b));
    try std.testing.expect(Real.lessThan(b, a));
}

test "Rational operations" {
    const a = try Rational.init(1, 2);
    const b = try Rational.init(1, 3);

    const sum = try Rational.add(a, b);
    try std.testing.expectEqual(@as(i64, 5), sum.numerator);
    try std.testing.expectEqual(@as(i64, 6), sum.denominator);

    const product = try Rational.mul(a, b);
    try std.testing.expectEqual(@as(i64, 1), product.numerator);
    try std.testing.expectEqual(@as(i64, 6), product.denominator);
}

test "Rational reduction" {
    const r = try Rational.init(6, 8);
    try std.testing.expectEqual(@as(i64, 3), r.numerator);
    try std.testing.expectEqual(@as(i64, 4), r.denominator);
}

test "Integral operations" {
    const a = Integral.init(10);
    const b = Integral.init(3);

    const sum = Integral.add(a, b);
    try std.testing.expectEqual(@as(i64, 13), sum.value);

    const div_result = try Integral.div(a, b);
    try std.testing.expectEqual(@as(i64, 3), div_result.value);

    const mod_result = try Integral.mod(a, b);
    try std.testing.expectEqual(@as(i64, 1), mod_result.value);
}

test "Integral bitwise" {
    const a = Integral.init(0b1010);
    const b = Integral.init(0b1100);

    try std.testing.expectEqual(@as(i64, 0b1000), Integral.bitwiseAnd(a, b).value);
    try std.testing.expectEqual(@as(i64, 0b1110), Integral.bitwiseOr(a, b).value);
    try std.testing.expectEqual(@as(i64, 0b0110), Integral.bitwiseXor(a, b).value);
}

test "Type checking" {
    try std.testing.expect(isIntegral(i32));
    try std.testing.expect(isIntegral(i64));
    try std.testing.expect(!isIntegral(f64));

    try std.testing.expect(isReal(f32));
    try std.testing.expect(isReal(f64));
    try std.testing.expect(isReal(i32)); // ints are also reals

    try std.testing.expect(isNumber(i32));
    try std.testing.expect(isNumber(f64));
}
