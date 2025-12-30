/// Fraction - Rational number type for Python fractions module
/// Moved to runtime to avoid monomorphization explosion from inline struct emission
const std = @import("std");
const pyint = @import("pyint.zig");
const UnifiedInt = pyint.UnifiedInt;

pub const Fraction = struct {
    numerator: i64,
    denominator: i64,

    /// Initialize a Fraction from UnifiedInt values (from as_integer_ratio())
    /// Returns error.Overflow if the UnifiedInt values are too large
    pub fn fromUnifiedInt(num: UnifiedInt, den: UnifiedInt) !Fraction {
        const n = num.toI64() orelse return error.Overflow;
        const d = den.toI64() orelse return error.Overflow;
        return initI64(n, d);
    }

    /// Initialize a Fraction from i64 values
    fn initI64(n: i64, d: i64) Fraction {
        const g = gcd(if (n < 0) -n else n, if (d < 0) -d else d);
        const sign: i64 = if ((n < 0) != (d < 0)) -1 else 1;
        return Fraction{
            .numerator = sign * @divTrunc(if (n < 0) -n else n, g),
            .denominator = @divTrunc(if (d < 0) -d else d, g),
        };
    }

    /// Initialize a Fraction from any numeric types
    /// Handles i64 directly and BigInt via toInt64() method
    pub fn init(num: anytype, den: anytype) Fraction {
        const n = toI64(num);
        const d = toI64(den);
        const g = gcd(if (n < 0) -n else n, if (d < 0) -d else d);
        const sign: i64 = if ((n < 0) != (d < 0)) -1 else 1;
        return Fraction{
            .numerator = sign * @divTrunc(if (n < 0) -n else n, g),
            .denominator = @divTrunc(if (d < 0) -d else d, g),
        };
    }

    /// Convert any numeric value to i64
    fn toI64(v: anytype) i64 {
        const T = @TypeOf(v);
        const info = @typeInfo(T);
        if (info == .int or info == .comptime_int) {
            return @as(i64, @intCast(v));
        }
        if (info == .@"struct" and @hasDecl(T, "toInt64")) {
            return v.toInt64() orelse 0;
        }
        return 0;
    }

    /// Greatest common divisor
    fn gcd(a: i64, b: i64) i64 {
        if (b == 0) return a;
        return gcd(b, @mod(a, b));
    }

    /// Addition
    pub fn add(self: Fraction, other: Fraction) Fraction {
        return Fraction.init(
            self.numerator * other.denominator + other.numerator * self.denominator,
            self.denominator * other.denominator,
        );
    }

    /// Subtraction
    pub fn sub(self: Fraction, other: Fraction) Fraction {
        return Fraction.init(
            self.numerator * other.denominator - other.numerator * self.denominator,
            self.denominator * other.denominator,
        );
    }

    /// Multiplication
    pub fn mul(self: Fraction, other: Fraction) Fraction {
        return Fraction.init(
            self.numerator * other.numerator,
            self.denominator * other.denominator,
        );
    }

    /// Division
    pub fn div(self: Fraction, other: Fraction) Fraction {
        return Fraction.init(
            self.numerator * other.denominator,
            self.denominator * other.numerator,
        );
    }

    /// Limit denominator to max_denominator
    pub fn limit_denominator(self: Fraction, max_denominator: i64) Fraction {
        if (self.denominator <= max_denominator) return self;
        return Fraction.init(
            @divTrunc(self.numerator * max_denominator, self.denominator),
            max_denominator,
        );
    }

    /// Convert to float
    pub fn toFloat(self: Fraction) f64 {
        return @as(f64, @floatFromInt(self.numerator)) / @as(f64, @floatFromInt(self.denominator));
    }

    /// Equality comparison
    pub fn eql(self: Fraction, other: Fraction) bool {
        return self.numerator == other.numerator and self.denominator == other.denominator;
    }

    /// Less than comparison
    pub fn lt(self: Fraction, other: Fraction) bool {
        return self.numerator * other.denominator < other.numerator * self.denominator;
    }

    /// Less than or equal comparison
    pub fn le(self: Fraction, other: Fraction) bool {
        return self.numerator * other.denominator <= other.numerator * self.denominator;
    }

    /// Negation
    pub fn neg(self: Fraction) Fraction {
        return Fraction{
            .numerator = -self.numerator,
            .denominator = self.denominator,
        };
    }

    /// Absolute value
    pub fn abs(self: Fraction) Fraction {
        return Fraction{
            .numerator = if (self.numerator < 0) -self.numerator else self.numerator,
            .denominator = self.denominator,
        };
    }

    /// String representation: "numerator/denominator" (like Python's Fraction)
    pub fn toStr(self: Fraction, allocator: std.mem.Allocator) ![]const u8 {
        if (self.denominator == 1) {
            return std.fmt.allocPrint(allocator, "{d}", .{self.numerator});
        }
        return std.fmt.allocPrint(allocator, "{d}/{d}", .{ self.numerator, self.denominator });
    }
};
