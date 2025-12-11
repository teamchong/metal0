//! Complex numbers with real and imaginary parts
//!
//! Mirrors CPython's complex number implementation from numbers.py

const std = @import("std");
const types = @import("types.zig");

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
        return T == Complex or (types.Number.isNumber(T));
    }
};

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
