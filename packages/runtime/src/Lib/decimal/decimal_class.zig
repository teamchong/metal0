//! Decimal number representation with arithmetic operations
//! Uses coefficient * 10^exponent representation

const std = @import("std");
const types = @import("types.zig");
const context_mod = @import("context.zig");

pub const Special = types.Special;
pub const getcontext = context_mod.getcontext;

/// Decimal number representation
/// Uses coefficient * 10^exponent representation
pub const Decimal = struct {
    const Self = @This();

    sign: bool = false, // true = negative
    coefficient: u128 = 0, // The significant digits
    exponent: i32 = 0, // Power of 10
    special: Special = .Normal,

    /// Create from an integer
    pub fn fromInt(value: i64) Self {
        if (value == 0) {
            return .{ .coefficient = 0, .exponent = 0 };
        }

        const abs_val: u64 = if (value < 0) @intCast(-value) else @intCast(value);
        return .{
            .sign = value < 0,
            .coefficient = abs_val,
            .exponent = 0,
        };
    }

    /// Create from a float
    pub fn fromFloat(value: f64) Self {
        if (std.math.isNan(value)) {
            return .{ .special = .NaN };
        }
        if (std.math.isInf(value)) {
            return .{ .sign = value < 0, .special = .Infinity };
        }
        if (value == 0) {
            return .{ .sign = std.math.signbit(value), .coefficient = 0, .exponent = 0 };
        }

        // Convert float to decimal representation
        const abs_val = @abs(value);
        var coef: u128 = 0;
        var exp: i32 = 0;

        // Find appropriate scale
        var scaled = abs_val;
        while (scaled < 1e15 and exp > -100) {
            scaled *= 10;
            exp -= 1;
        }
        while (scaled >= 1e16 and exp < 100) {
            scaled /= 10;
            exp += 1;
        }

        coef = @intFromFloat(scaled);

        return .{
            .sign = value < 0,
            .coefficient = coef,
            .exponent = exp,
        };
    }

    /// Create from a string
    pub fn fromString(s: []const u8) !Self {
        if (s.len == 0) return error.InvalidDecimal;

        var idx: usize = 0;
        var sign = false;

        // Parse sign
        if (idx < s.len and (s[idx] == '-' or s[idx] == '+')) {
            sign = s[idx] == '-';
            idx += 1;
        }

        // Check for special values
        if (idx < s.len) {
            const rest = s[idx..];
            if (std.ascii.eqlIgnoreCase(rest, "inf") or std.ascii.eqlIgnoreCase(rest, "infinity")) {
                return .{ .sign = sign, .special = .Infinity };
            }
            if (std.ascii.eqlIgnoreCase(rest, "nan")) {
                return .{ .sign = sign, .special = .NaN };
            }
            if (std.ascii.eqlIgnoreCase(rest, "snan")) {
                return .{ .sign = sign, .special = .sNaN };
            }
        }

        // Parse digits and decimal point
        var coef: u128 = 0;
        var exp: i32 = 0;
        var seen_dot = false;
        var digits_after_dot: i32 = 0;

        while (idx < s.len) {
            const c = s[idx];
            if (c >= '0' and c <= '9') {
                coef = coef * 10 + (c - '0');
                if (seen_dot) {
                    digits_after_dot += 1;
                }
            } else if (c == '.') {
                if (seen_dot) return error.InvalidDecimal;
                seen_dot = true;
            } else if (c == 'e' or c == 'E') {
                idx += 1;
                break;
            } else if (c == '_') {
                // Python allows underscores in numbers
            } else {
                return error.InvalidDecimal;
            }
            idx += 1;
        }

        exp = -digits_after_dot;

        // Parse exponent
        if (idx < s.len) {
            var exp_sign: i32 = 1;
            if (s[idx] == '-') {
                exp_sign = -1;
                idx += 1;
            } else if (s[idx] == '+') {
                idx += 1;
            }

            var exp_val: i32 = 0;
            while (idx < s.len) {
                const c = s[idx];
                if (c >= '0' and c <= '9') {
                    exp_val = exp_val * 10 + @as(i32, c - '0');
                } else if (c != '_') {
                    return error.InvalidDecimal;
                }
                idx += 1;
            }
            exp += exp_sign * exp_val;
        }

        return .{
            .sign = sign,
            .coefficient = coef,
            .exponent = exp,
        };
    }

    /// Convert to float
    pub fn toFloat(self: Self) f64 {
        switch (self.special) {
            .Infinity => return if (self.sign) -std.math.inf(f64) else std.math.inf(f64),
            .NaN, .sNaN => return std.math.nan(f64),
            .Normal => {},
        }

        var result: f64 = @floatFromInt(self.coefficient);

        if (self.exponent > 0) {
            var i: i32 = 0;
            while (i < self.exponent) : (i += 1) {
                result *= 10.0;
            }
        } else if (self.exponent < 0) {
            var i: i32 = 0;
            while (i < -self.exponent) : (i += 1) {
                result /= 10.0;
            }
        }

        return if (self.sign) -result else result;
    }

    /// Convert to integer (truncating)
    pub fn toInt(self: Self) !i64 {
        if (self.special != .Normal) return error.InvalidOperation;

        var value: i128 = self.coefficient;

        if (self.exponent > 0) {
            var i: i32 = 0;
            while (i < self.exponent) : (i += 1) {
                value *= 10;
            }
        } else if (self.exponent < 0) {
            var i: i32 = 0;
            while (i < -self.exponent) : (i += 1) {
                value = @divTrunc(value, 10);
            }
        }

        if (value > std.math.maxInt(i64) or value < std.math.minInt(i64)) {
            return error.Overflow;
        }

        const result: i64 = @intCast(value);
        return if (self.sign) -result else result;
    }

    /// Format to string
    pub fn toString(self: Self, buf: []u8) ![]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        switch (self.special) {
            .Infinity => {
                if (self.sign) try writer.writeByte('-');
                try writer.writeAll("Infinity");
                return stream.getWritten();
            },
            .NaN => {
                if (self.sign) try writer.writeByte('-');
                try writer.writeAll("NaN");
                return stream.getWritten();
            },
            .sNaN => {
                if (self.sign) try writer.writeByte('-');
                try writer.writeAll("sNaN");
                return stream.getWritten();
            },
            .Normal => {},
        }

        if (self.sign) try writer.writeByte('-');

        // Format coefficient
        var coef_buf: [40]u8 = undefined;
        const coef_str = std.fmt.bufPrint(&coef_buf, "{d}", .{self.coefficient}) catch return error.BufferTooSmall;

        if (self.exponent == 0) {
            try writer.writeAll(coef_str);
        } else if (self.exponent < 0) {
            const abs_exp: usize = @intCast(-self.exponent);
            if (abs_exp < coef_str.len) {
                const dot_pos = coef_str.len - abs_exp;
                try writer.writeAll(coef_str[0..dot_pos]);
                try writer.writeByte('.');
                try writer.writeAll(coef_str[dot_pos..]);
            } else {
                try writer.writeAll("0.");
                var zeros = abs_exp - coef_str.len;
                while (zeros > 0) : (zeros -= 1) {
                    try writer.writeByte('0');
                }
                try writer.writeAll(coef_str);
            }
        } else {
            try writer.writeAll(coef_str);
            try writer.writeByte('E');
            try writer.writeByte('+');
            try writer.print("{d}", .{self.exponent});
        }

        return stream.getWritten();
    }

    // ========================================================================
    // Arithmetic Operations
    // ========================================================================

    /// Add two decimals
    pub fn add(self: Self, other: Self) Self {
        // Handle special values
        if (self.special == .NaN or other.special == .NaN) return .{ .special = .NaN };
        if (self.special == .sNaN or other.special == .sNaN) return .{ .special = .NaN };

        if (self.special == .Infinity) {
            if (other.special == .Infinity and self.sign != other.sign) {
                return .{ .special = .NaN }; // Inf + (-Inf) = NaN
            }
            return self;
        }
        if (other.special == .Infinity) return other;

        // Align exponents
        var a = self;
        var b = other;

        if (a.exponent < b.exponent) {
            const diff: u32 = @intCast(b.exponent - a.exponent);
            var i: u32 = 0;
            while (i < diff) : (i += 1) {
                b.coefficient *= 10;
            }
            b.exponent = a.exponent;
        } else if (b.exponent < a.exponent) {
            const diff: u32 = @intCast(a.exponent - b.exponent);
            var i: u32 = 0;
            while (i < diff) : (i += 1) {
                a.coefficient *= 10;
            }
            a.exponent = b.exponent;
        }

        // Perform addition considering signs
        var result: Self = .{ .exponent = a.exponent };

        if (a.sign == b.sign) {
            result.sign = a.sign;
            result.coefficient = a.coefficient + b.coefficient;
        } else {
            if (a.coefficient >= b.coefficient) {
                result.sign = a.sign;
                result.coefficient = a.coefficient - b.coefficient;
            } else {
                result.sign = b.sign;
                result.coefficient = b.coefficient - a.coefficient;
            }
        }

        return result.normalize();
    }

    /// Subtract two decimals
    pub fn sub(self: Self, other: Self) Self {
        var neg_other = other;
        neg_other.sign = !other.sign;
        return self.add(neg_other);
    }

    /// Multiply two decimals
    pub fn mul(self: Self, other: Self) Self {
        // Handle special values
        if (self.special == .NaN or other.special == .NaN) return .{ .special = .NaN };
        if (self.special == .sNaN or other.special == .sNaN) return .{ .special = .NaN };

        if (self.special == .Infinity or other.special == .Infinity) {
            if (self.coefficient == 0 or other.coefficient == 0) {
                return .{ .special = .NaN }; // Inf * 0 = NaN
            }
            return .{ .sign = self.sign != other.sign, .special = .Infinity };
        }

        return (Self{
            .sign = self.sign != other.sign,
            .coefficient = self.coefficient * other.coefficient,
            .exponent = self.exponent + other.exponent,
        }).normalize();
    }

    /// Divide two decimals
    pub fn div(self: Self, other: Self) Self {
        // Handle special values
        if (self.special == .NaN or other.special == .NaN) return .{ .special = .NaN };
        if (self.special == .sNaN or other.special == .sNaN) return .{ .special = .NaN };

        if (other.coefficient == 0 and other.special == .Normal) {
            getcontext().setFlag(.DivisionByZero);
            return .{ .sign = self.sign != other.sign, .special = .Infinity };
        }

        if (self.special == .Infinity) {
            if (other.special == .Infinity) return .{ .special = .NaN };
            return .{ .sign = self.sign != other.sign, .special = .Infinity };
        }
        if (other.special == .Infinity) {
            return .{ .sign = self.sign != other.sign, .coefficient = 0, .exponent = 0 };
        }

        // Scale numerator for precision
        const ctx = getcontext();
        var num = self.coefficient;
        var scale: i32 = 0;
        var i: u32 = 0;
        while (i < ctx.prec + 1) : (i += 1) {
            num *= 10;
            scale += 1;
        }

        return (Self{
            .sign = self.sign != other.sign,
            .coefficient = num / other.coefficient,
            .exponent = self.exponent - other.exponent - scale,
        }).normalize();
    }

    /// Negate
    pub fn neg(self: Self) Self {
        var result = self;
        result.sign = !self.sign;
        return result;
    }

    /// Absolute value
    pub fn abs(self: Self) Self {
        var result = self;
        result.sign = false;
        return result;
    }

    /// Normalize (remove trailing zeros)
    pub fn normalize(self: Self) Self {
        if (self.special != .Normal or self.coefficient == 0) return self;

        var result = self;
        while (result.coefficient % 10 == 0 and result.coefficient > 0) {
            result.coefficient /= 10;
            result.exponent += 1;
        }
        return result;
    }

    /// Compare two decimals
    pub fn compare(self: Self, other: Self) std.math.Order {
        // Handle special values
        if (self.special == .NaN or other.special == .NaN) return .eq; // NaN comparisons are problematic

        if (self.special == .Infinity and other.special == .Infinity) {
            if (self.sign == other.sign) return .eq;
            return if (self.sign) .lt else .gt;
        }
        if (self.special == .Infinity) return if (self.sign) .lt else .gt;
        if (other.special == .Infinity) return if (other.sign) .gt else .lt;

        // Compare signs
        if (self.sign != other.sign) {
            return if (self.sign) .lt else .gt;
        }

        // Compare values (same sign)
        const self_val = self.toFloat();
        const other_val = other.toFloat();

        if (self_val < other_val) return if (self.sign) .gt else .lt;
        if (self_val > other_val) return if (self.sign) .lt else .gt;
        return .eq;
    }

    /// Check equality
    pub fn eql(self: Self, other: Self) bool {
        return self.compare(other) == .eq;
    }

    /// Check if zero
    pub fn isZero(self: Self) bool {
        return self.special == .Normal and self.coefficient == 0;
    }

    /// Check if finite
    pub fn isFinite(self: Self) bool {
        return self.special == .Normal;
    }

    /// Check if infinite
    pub fn isInfinite(self: Self) bool {
        return self.special == .Infinity;
    }

    /// Check if NaN
    pub fn isNaN(self: Self) bool {
        return self.special == .NaN or self.special == .sNaN;
    }

    /// Check if negative
    pub fn isNegative(self: Self) bool {
        return self.sign and !self.isZero();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Decimal.fromInt" {
    const d = Decimal.fromInt(42);
    try std.testing.expectEqual(@as(u128, 42), d.coefficient);
    try std.testing.expectEqual(@as(i32, 0), d.exponent);
    try std.testing.expect(!d.sign);

    const neg = Decimal.fromInt(-100);
    try std.testing.expectEqual(@as(u128, 100), neg.coefficient);
    try std.testing.expect(neg.sign);
}

test "Decimal.fromString" {
    const d1 = try Decimal.fromString("123.45");
    try std.testing.expectEqual(@as(u128, 12345), d1.coefficient);
    try std.testing.expectEqual(@as(i32, -2), d1.exponent);

    const d2 = try Decimal.fromString("-0.001");
    try std.testing.expect(d2.sign);
    try std.testing.expectEqual(@as(i32, -3), d2.exponent);

    const d3 = try Decimal.fromString("1e10");
    try std.testing.expectEqual(@as(i32, 10), d3.exponent);

    const inf = try Decimal.fromString("Infinity");
    try std.testing.expect(inf.special == .Infinity);

    const nan = try Decimal.fromString("NaN");
    try std.testing.expect(nan.special == .NaN);
}

test "Decimal.toFloat" {
    const d = Decimal.fromInt(42);
    try std.testing.expectEqual(@as(f64, 42.0), d.toFloat());

    const d2 = try Decimal.fromString("3.14");
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), d2.toFloat(), 0.001);
}

test "Decimal.add" {
    const a = Decimal.fromInt(10);
    const b = Decimal.fromInt(20);
    const result = a.add(b);
    try std.testing.expectEqual(@as(u128, 30), result.coefficient);
}

test "Decimal.sub" {
    const a = Decimal.fromInt(30);
    const b = Decimal.fromInt(20);
    const result = a.sub(b);
    try std.testing.expectEqual(@as(u128, 10), result.coefficient);
}

test "Decimal.mul" {
    const a = Decimal.fromInt(6);
    const b = Decimal.fromInt(7);
    const result = a.mul(b);
    try std.testing.expectEqual(@as(u128, 42), result.coefficient);
}

test "Decimal.compare" {
    const a = Decimal.fromInt(10);
    const b = Decimal.fromInt(20);
    try std.testing.expectEqual(std.math.Order.lt, a.compare(b));
    try std.testing.expectEqual(std.math.Order.gt, b.compare(a));
    try std.testing.expectEqual(std.math.Order.eq, a.compare(a));
}

test "Decimal.normalize" {
    var d = Decimal{ .coefficient = 12300, .exponent = -2 };
    d = d.normalize();
    try std.testing.expectEqual(@as(u128, 123), d.coefficient);
    try std.testing.expectEqual(@as(i32, 0), d.exponent);
}
