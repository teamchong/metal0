//! Real numbers (subset of complex with imag = 0)
//!
//! Provides real number operations including conversions, arithmetic, and comparisons.

const std = @import("std");

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

    /// Round to nearest integer (banker's rounding)
    pub fn round(self: Real) i64 {
        const bankersRound = @import("../../runtime/builtins/conversion.zig").bankersRound;
        return @intFromFloat(bankersRound(self.value));
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
// Tests
// ============================================================================

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
