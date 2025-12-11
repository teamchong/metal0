//! Rational numbers (numerator/denominator)
//!
//! Includes properties numerator and denominator, with automatic reduction to lowest terms.

const std = @import("std");
const utils = @import("utils.zig");
const Integral = @import("integral.zig").Integral;

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
        const g = utils.gcd(@abs(num), @abs(den));
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
// Tests
// ============================================================================

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
