//! Integral (whole) numbers
//!
//! Provides integer operations including arithmetic, bitwise, and comparisons.

const std = @import("std");

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
// Tests
// ============================================================================

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
