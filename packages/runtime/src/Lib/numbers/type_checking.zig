//! Type checking functions for the numeric tower
//!
//! Provides runtime type checking for Number, Complex, Real, Rational, and Integral.

const types = @import("types.zig");
const Complex = @import("complex.zig").Complex;
const Real = @import("real.zig").Real;
const Rational = @import("rational.zig").Rational;
const Integral = @import("integral.zig").Integral;

/// Check if a value is an instance of the numeric tower
pub fn isNumber(comptime T: type) bool {
    return types.Number.isNumber(T);
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

const std = @import("std");

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
