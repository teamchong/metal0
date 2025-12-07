//! Python 'fractions' module - Rational numbers
//!
//! Provides support for rational number arithmetic.
//!
//! Mirrors: CPython Lib/fractions.py

const std = @import("std");

// ============================================================================
// Fraction type
// ============================================================================

/// Represents a rational number as numerator/denominator
pub const Fraction = struct {
    numerator: i64,
    denominator: i64,

    /// Create a new fraction (auto-reduces)
    pub fn init(numerator: i64, denominator: i64) !Fraction {
        if (denominator == 0) {
            return error.ZeroDivision;
        }

        var num = numerator;
        var den = denominator;

        // Handle negative denominator
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

    /// Create a fraction from an integer
    pub fn fromInt(n: i64) Fraction {
        return .{ .numerator = n, .denominator = 1 };
    }

    /// Create a fraction from a float (best rational approximation)
    pub fn fromFloat(f: f64, max_denominator: i64) Fraction {
        if (std.math.isNan(f) or std.math.isInf(f)) {
            return .{ .numerator = 0, .denominator = 1 };
        }

        // Use continued fraction expansion
        var p0: i64 = 0;
        var q0: i64 = 1;
        var p1: i64 = 1;
        var q1: i64 = 0;

        var x = f;
        if (x < 0) {
            const result = fromFloat(-f, max_denominator);
            return .{ .numerator = -result.numerator, .denominator = result.denominator };
        }

        while (true) {
            const a: i64 = @intFromFloat(@floor(x));

            const p2 = a * p1 + p0;
            const q2 = a * q1 + q0;

            if (q2 > max_denominator) break;

            p0 = p1;
            q0 = q1;
            p1 = p2;
            q1 = q2;

            const frac = x - @as(f64, @floatFromInt(a));
            if (frac < 1e-15) break;

            x = 1.0 / frac;
        }

        if (q1 == 0) q1 = 1;

        const g = gcd(@abs(p1), @abs(q1));
        return .{
            .numerator = @divTrunc(p1, @as(i64, @intCast(g))),
            .denominator = @divTrunc(q1, @as(i64, @intCast(g))),
        };
    }

    /// Parse a fraction from a string like "3/4" or "1.5"
    pub fn fromString(s: []const u8) !Fraction {
        // Check for slash
        if (std.mem.indexOf(u8, s, "/")) |slash_pos| {
            const num_str = std.mem.trim(u8, s[0..slash_pos], " ");
            const den_str = std.mem.trim(u8, s[slash_pos + 1 ..], " ");

            const num = std.fmt.parseInt(i64, num_str, 10) catch return error.InvalidFormat;
            const den = std.fmt.parseInt(i64, den_str, 10) catch return error.InvalidFormat;

            return init(num, den);
        }

        // Check for decimal point
        if (std.mem.indexOf(u8, s, ".")) |_| {
            const f = std.fmt.parseFloat(f64, s) catch return error.InvalidFormat;
            return fromFloat(f, 1_000_000_000);
        }

        // Plain integer
        const num = std.fmt.parseInt(i64, std.mem.trim(u8, s, " "), 10) catch return error.InvalidFormat;
        return fromInt(num);
    }

    // ========================================================================
    // Arithmetic operations
    // ========================================================================

    /// Add two fractions
    pub fn add(a: Fraction, b: Fraction) !Fraction {
        const num = a.numerator * b.denominator + b.numerator * a.denominator;
        const den = a.denominator * b.denominator;
        return init(num, den);
    }

    /// Subtract two fractions
    pub fn sub(a: Fraction, b: Fraction) !Fraction {
        const num = a.numerator * b.denominator - b.numerator * a.denominator;
        const den = a.denominator * b.denominator;
        return init(num, den);
    }

    /// Multiply two fractions
    pub fn mul(a: Fraction, b: Fraction) !Fraction {
        const num = a.numerator * b.numerator;
        const den = a.denominator * b.denominator;
        return init(num, den);
    }

    /// Divide two fractions
    pub fn div(a: Fraction, b: Fraction) !Fraction {
        if (b.numerator == 0) {
            return error.ZeroDivision;
        }
        const num = a.numerator * b.denominator;
        const den = a.denominator * b.numerator;
        return init(num, den);
    }

    /// Floor division
    pub fn floordiv(a: Fraction, b: Fraction) !Fraction {
        if (b.numerator == 0) {
            return error.ZeroDivision;
        }
        const num = a.numerator * b.denominator;
        const den = a.denominator * b.numerator;
        const result = @divFloor(num, den);
        return fromInt(result);
    }

    /// Modulo
    pub fn mod(a: Fraction, b: Fraction) !Fraction {
        const quotient = try floordiv(a, b);
        const product = try mul(quotient, b);
        return sub(a, product);
    }

    /// Power (integer exponent)
    pub fn pow(base: Fraction, exp: i32) !Fraction {
        if (exp == 0) return fromInt(1);

        if (exp > 0) {
            var result = fromInt(1);
            var e = exp;
            var b = base;
            while (e > 0) {
                if (@rem(e, 2) == 1) {
                    result = try mul(result, b);
                }
                b = try mul(b, b);
                e = @divTrunc(e, 2);
            }
            return result;
        } else {
            // Negative exponent: invert and use positive exponent
            const inverted = try init(base.denominator, base.numerator);
            return pow(inverted, -exp);
        }
    }

    /// Negate
    pub fn neg(self: Fraction) Fraction {
        return .{ .numerator = -self.numerator, .denominator = self.denominator };
    }

    /// Absolute value
    pub fn abs(self: Fraction) Fraction {
        return .{
            .numerator = if (self.numerator < 0) -self.numerator else self.numerator,
            .denominator = self.denominator,
        };
    }

    // ========================================================================
    // Comparison operations
    // ========================================================================

    /// Compare two fractions
    pub fn cmp(a: Fraction, b: Fraction) std.math.Order {
        const lhs = a.numerator * b.denominator;
        const rhs = b.numerator * a.denominator;
        return std.math.order(lhs, rhs);
    }

    pub fn eql(a: Fraction, b: Fraction) bool {
        return a.numerator == b.numerator and a.denominator == b.denominator;
    }

    pub fn lessThan(a: Fraction, b: Fraction) bool {
        return cmp(a, b) == .lt;
    }

    pub fn lessThanOrEqual(a: Fraction, b: Fraction) bool {
        return cmp(a, b) != .gt;
    }

    pub fn greaterThan(a: Fraction, b: Fraction) bool {
        return cmp(a, b) == .gt;
    }

    pub fn greaterThanOrEqual(a: Fraction, b: Fraction) bool {
        return cmp(a, b) != .lt;
    }

    // ========================================================================
    // Conversion
    // ========================================================================

    /// Convert to float
    pub fn toFloat(self: Fraction) f64 {
        return @as(f64, @floatFromInt(self.numerator)) / @as(f64, @floatFromInt(self.denominator));
    }

    /// Convert to integer (truncated)
    pub fn toInt(self: Fraction) i64 {
        return @divTrunc(self.numerator, self.denominator);
    }

    /// Floor value
    pub fn floor(self: Fraction) i64 {
        return @divFloor(self.numerator, self.denominator);
    }

    /// Ceiling value
    pub fn ceil(self: Fraction) i64 {
        const f = @divFloor(self.numerator, self.denominator);
        if (@rem(self.numerator, self.denominator) != 0) {
            return f + 1;
        }
        return f;
    }

    /// Round to nearest integer
    pub fn round(self: Fraction) i64 {
        const f = self.toFloat();
        return @intFromFloat(@round(f));
    }

    // ========================================================================
    // Utility
    // ========================================================================

    /// Limit denominator to max_denominator
    pub fn limitDenominator(self: Fraction, max_denominator: i64) Fraction {
        if (self.denominator <= max_denominator) {
            return self;
        }
        return fromFloat(self.toFloat(), max_denominator);
    }

    /// Format as string "numerator/denominator"
    pub fn format(self: Fraction, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        if (self.denominator == 1) {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{self.numerator}) catch return result.toOwnedSlice();
            try result.appendSlice(str);
        } else {
            var buf: [64]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}/{d}", .{ self.numerator, self.denominator }) catch return result.toOwnedSlice();
            try result.appendSlice(str);
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Utility functions
// ============================================================================

/// Greatest common divisor
pub fn gcd(a: anytype, b: anytype) @TypeOf(a) {
    var x = if (a < 0) -a else a;
    var y = if (b < 0) -b else b;

    while (y != 0) {
        const t = y;
        y = @rem(x, y);
        x = t;
    }
    return x;
}

/// Least common multiple
pub fn lcm(a: anytype, b: anytype) @TypeOf(a) {
    if (a == 0 or b == 0) return 0;
    const g = gcd(a, b);
    return @divExact(a, g) * b;
}

// ============================================================================
// Tests
// ============================================================================

test "Fraction init" {
    const f = try Fraction.init(6, 8);
    try std.testing.expectEqual(@as(i64, 3), f.numerator);
    try std.testing.expectEqual(@as(i64, 4), f.denominator);
}

test "Fraction init negative" {
    const f = try Fraction.init(-3, 4);
    try std.testing.expectEqual(@as(i64, -3), f.numerator);
    try std.testing.expectEqual(@as(i64, 4), f.denominator);
}

test "Fraction init negative denominator" {
    const f = try Fraction.init(3, -4);
    try std.testing.expectEqual(@as(i64, -3), f.numerator);
    try std.testing.expectEqual(@as(i64, 4), f.denominator);
}

test "Fraction zero denominator" {
    const result = Fraction.init(1, 0);
    try std.testing.expectError(error.ZeroDivision, result);
}

test "Fraction add" {
    const a = try Fraction.init(1, 2);
    const b = try Fraction.init(1, 3);
    const result = try a.add(b);
    try std.testing.expectEqual(@as(i64, 5), result.numerator);
    try std.testing.expectEqual(@as(i64, 6), result.denominator);
}

test "Fraction sub" {
    const a = try Fraction.init(1, 2);
    const b = try Fraction.init(1, 3);
    const result = try a.sub(b);
    try std.testing.expectEqual(@as(i64, 1), result.numerator);
    try std.testing.expectEqual(@as(i64, 6), result.denominator);
}

test "Fraction mul" {
    const a = try Fraction.init(2, 3);
    const b = try Fraction.init(3, 4);
    const result = try a.mul(b);
    try std.testing.expectEqual(@as(i64, 1), result.numerator);
    try std.testing.expectEqual(@as(i64, 2), result.denominator);
}

test "Fraction div" {
    const a = try Fraction.init(1, 2);
    const b = try Fraction.init(3, 4);
    const result = try a.div(b);
    try std.testing.expectEqual(@as(i64, 2), result.numerator);
    try std.testing.expectEqual(@as(i64, 3), result.denominator);
}

test "Fraction pow" {
    const a = try Fraction.init(2, 3);
    const result = try a.pow(3);
    try std.testing.expectEqual(@as(i64, 8), result.numerator);
    try std.testing.expectEqual(@as(i64, 27), result.denominator);
}

test "Fraction pow negative" {
    const a = try Fraction.init(2, 3);
    const result = try a.pow(-1);
    try std.testing.expectEqual(@as(i64, 3), result.numerator);
    try std.testing.expectEqual(@as(i64, 2), result.denominator);
}

test "Fraction toFloat" {
    const f = try Fraction.init(1, 4);
    try std.testing.expectApproxEqAbs(0.25, f.toFloat(), 0.001);
}

test "Fraction fromFloat" {
    const f = Fraction.fromFloat(0.5, 100);
    try std.testing.expectEqual(@as(i64, 1), f.numerator);
    try std.testing.expectEqual(@as(i64, 2), f.denominator);
}

test "Fraction fromFloat pi approximation" {
    const f = Fraction.fromFloat(3.14159, 1000);
    try std.testing.expectApproxEqAbs(3.14159, f.toFloat(), 0.01);
}

test "Fraction fromString" {
    const f = try Fraction.fromString("3/4");
    try std.testing.expectEqual(@as(i64, 3), f.numerator);
    try std.testing.expectEqual(@as(i64, 4), f.denominator);
}

test "Fraction fromString decimal" {
    const f = try Fraction.fromString("0.5");
    try std.testing.expectEqual(@as(i64, 1), f.numerator);
    try std.testing.expectEqual(@as(i64, 2), f.denominator);
}

test "Fraction comparison" {
    const a = try Fraction.init(1, 2);
    const b = try Fraction.init(2, 3);
    try std.testing.expect(a.lessThan(b));
    try std.testing.expect(b.greaterThan(a));
}

test "Fraction floor and ceil" {
    const f = try Fraction.init(7, 3);
    try std.testing.expectEqual(@as(i64, 2), f.floor());
    try std.testing.expectEqual(@as(i64, 3), f.ceil());
}

test "gcd" {
    try std.testing.expectEqual(@as(i32, 6), gcd(@as(i32, 12), @as(i32, 18)));
    try std.testing.expectEqual(@as(i32, 1), gcd(@as(i32, 7), @as(i32, 13)));
}

test "lcm" {
    try std.testing.expectEqual(@as(i32, 36), lcm(@as(i32, 12), @as(i32, 18)));
    try std.testing.expectEqual(@as(i32, 91), lcm(@as(i32, 7), @as(i32, 13)));
}

test "Fraction format" {
    const allocator = std.testing.allocator;

    const f1 = try Fraction.init(3, 4);
    const s1 = try f1.format(allocator);
    defer allocator.free(s1);
    try std.testing.expectEqualStrings("3/4", s1);

    const f2 = Fraction.fromInt(5);
    const s2 = try f2.format(allocator);
    defer allocator.free(s2);
    try std.testing.expectEqualStrings("5", s2);
}
