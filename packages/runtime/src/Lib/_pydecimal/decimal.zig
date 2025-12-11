/// _pydecimal.decimal - Decimal number type and operations
/// Core arbitrary-precision decimal floating point representation

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub const SpecialValue = types.SpecialValue;

// ============================================================================
// Decimal Type
// ============================================================================

/// Decimal number representation
/// Stores numbers as sign + coefficient + exponent
/// For example: 1.23 = sign:0, coefficient:"123", exponent:-2
pub const Decimal = struct {
    const Self = @This();

    /// Sign (0 = positive, 1 = negative)
    sign: u1 = 0,
    /// Coefficient digits (stored as string for precision)
    coefficient: []const u8 = "0",
    /// Exponent (actual value = coefficient * 10^exponent)
    exponent: i32 = 0,
    /// Special value (infinity, NaN, etc.)
    special: SpecialValue = .normal,
    /// Allocator for memory management
    allocator: ?Allocator = null,

    // ========================================================================
    // Static Constants
    // ========================================================================

    /// Zero decimal
    pub const zero = Self{ .coefficient = "0" };
    /// One decimal
    pub const one = Self{ .coefficient = "1" };
    /// Negative one decimal
    pub const negative_one = Self{ .sign = 1, .coefficient = "1" };
    /// Positive infinity
    pub const infinity = Self{ .special = .infinity };
    /// Negative infinity
    pub const negative_infinity = Self{ .sign = 1, .special = .infinity };
    /// NaN (not a number)
    pub const nan_value = Self{ .special = .nan };

    // ========================================================================
    // Constructors
    // ========================================================================

    /// Create decimal from integer
    pub fn fromInt(value: i64) Self {
        if (value == 0) return zero;
        const sign: u1 = if (value < 0) 1 else 0;
        const abs_val = if (value < 0) -value else value;
        var buf: [20]u8 = undefined;
        const coeff = std.fmt.bufPrint(&buf, "{d}", .{abs_val}) catch return zero;
        return Self{
            .sign = sign,
            .coefficient = coeff,
        };
    }

    /// Create decimal from float
    /// Converts a float to Decimal by determining coefficient and exponent
    pub fn fromFloat(value: f64) Self {
        if (std.math.isNan(value)) return nan_value;
        if (std.math.isInf(value)) {
            return if (value < 0) negative_infinity else infinity;
        }
        if (value == 0) {
            return Self{ .sign = if (std.math.signbit(value)) 1 else 0 };
        }

        const sign: u1 = if (value < 0) 1 else 0;
        const abs_val = if (value < 0) -value else value;

        // Determine magnitude using log10
        const log_val = @log10(abs_val);
        const exp_part: i32 = @intFromFloat(@floor(log_val));

        // Scale to get coefficient as integer
        // Aim for ~17 significant digits (f64 precision)
        const scale_exp: i32 = 17 - exp_part - 1;
        const scale: f64 = std.math.pow(f64, 10.0, @floatFromInt(scale_exp));
        const scaled = abs_val * scale;

        // Get coefficient digits
        const coeff_int: u64 = @intFromFloat(@round(scaled));

        // Find actual exponent (trim trailing zeros)
        var coeff = coeff_int;
        var actual_exp: i32 = -scale_exp;
        while (coeff > 0 and coeff % 10 == 0) {
            coeff = coeff / 10;
            actual_exp += 1;
        }

        // Convert coefficient to digit array
        var digits: [20]u8 = undefined;
        var digit_count: usize = 0;
        var temp_coeff = coeff;
        while (temp_coeff > 0) {
            digits[digit_count] = @intCast(temp_coeff % 10);
            temp_coeff = temp_coeff / 10;
            digit_count += 1;
        }

        // Reverse digits into final order
        var result = Self{
            .sign = sign,
            .exponent = actual_exp,
        };

        // Store digits in reverse order (most significant first)
        for (0..digit_count) |i| {
            result.coefficient[i] = digits[digit_count - 1 - i];
        }

        return result;
    }

    /// Parse decimal from string
    /// Supports formats: "123", "-45.6", "1e-10", "1.23E+5", "Infinity", "NaN"
    pub fn parse(allocator: Allocator, s: []const u8) !Self {
        if (s.len == 0) return error.InvalidDecimal;

        var result = Self{ .allocator = allocator };
        var pos: usize = 0;

        // Parse optional sign
        if (s[pos] == '-') {
            result.sign = 1;
            pos += 1;
        } else if (s[pos] == '+') {
            pos += 1;
        }

        // Check for special values
        if (pos < s.len) {
            const remaining = s[pos..];
            if (std.ascii.eqlIgnoreCase(remaining, "inf") or
                std.ascii.eqlIgnoreCase(remaining, "infinity"))
            {
                result.special = .infinity;
                return result;
            }
            if (std.ascii.eqlIgnoreCase(remaining, "nan")) {
                result.special = .nan;
                return result;
            }
            if (std.ascii.eqlIgnoreCase(remaining, "snan")) {
                result.special = .snan;
                return result;
            }
        }

        // Parse coefficient and exponent
        var coeff = std.ArrayList(u8).init(allocator);
        defer coeff.deinit();
        var exp: i32 = 0;
        var decimal_pos: ?usize = null;

        while (pos < s.len) {
            const c = s[pos];
            if (c >= '0' and c <= '9') {
                try coeff.append(c);
            } else if (c == '.') {
                if (decimal_pos != null) return error.InvalidDecimal;
                decimal_pos = coeff.items.len;
            } else if (c == 'e' or c == 'E') {
                pos += 1;
                // Parse exponent part
                var exp_sign: i32 = 1;
                if (pos < s.len and s[pos] == '-') {
                    exp_sign = -1;
                    pos += 1;
                } else if (pos < s.len and s[pos] == '+') {
                    pos += 1;
                }
                while (pos < s.len and s[pos] >= '0' and s[pos] <= '9') {
                    exp = exp * 10 + @as(i32, @intCast(s[pos] - '0'));
                    pos += 1;
                }
                exp *= exp_sign;
                break;
            } else {
                return error.InvalidDecimal;
            }
            pos += 1;
        }

        // Adjust exponent for decimal point position
        if (decimal_pos) |dp| {
            exp -= @as(i32, @intCast(coeff.items.len - dp));
        }

        // Remove leading zeros
        var start: usize = 0;
        while (start < coeff.items.len - 1 and coeff.items[start] == '0') {
            start += 1;
        }

        result.coefficient = try allocator.dupe(u8, coeff.items[start..]);
        result.exponent = exp;

        return result;
    }

    // ========================================================================
    // Predicates
    // ========================================================================

    /// Check if value is zero
    pub fn isZero(self: *const Self) bool {
        if (self.special != .normal) return false;
        for (self.coefficient) |c| {
            if (c != '0') return false;
        }
        return true;
    }

    /// Check if value is negative
    pub fn isNegative(self: *const Self) bool {
        return self.sign == 1;
    }

    /// Check if value is NaN (quiet or signaling)
    pub fn isNan(self: *const Self) bool {
        return self.special == .nan or self.special == .snan;
    }

    /// Check if value is infinite
    pub fn isInfinite(self: *const Self) bool {
        return self.special == .infinity;
    }

    /// Check if value is finite (not infinity or NaN)
    pub fn isFinite(self: *const Self) bool {
        return self.special == .normal;
    }

    // ========================================================================
    // Unary Operations
    // ========================================================================

    /// Negate the value (flip sign)
    pub fn negate(self: Self) Self {
        var result = self;
        result.sign = if (self.sign == 0) 1 else 0;
        return result;
    }

    /// Return absolute value (remove sign)
    pub fn abs(self: Self) Self {
        var result = self;
        result.sign = 0;
        return result;
    }

    // ========================================================================
    // Formatting
    // ========================================================================

    /// Format decimal as string representation
    /// Output format:
    ///   - Normal: "123", "12.3", "0.123", "123E+10"
    ///   - Infinity: "Infinity" or "-Infinity"
    ///   - NaN: "NaN" or "sNaN"
    pub fn format(self: *const Self, allocator: Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);

        // Add sign
        if (self.sign == 1) try result.append('-');

        // Handle special values
        switch (self.special) {
            .infinity => {
                try result.appendSlice("Infinity");
                return result.toOwnedSlice();
            },
            .nan => {
                try result.appendSlice("NaN");
                return result.toOwnedSlice();
            },
            .snan => {
                try result.appendSlice("sNaN");
                return result.toOwnedSlice();
            },
            .normal => {},
        }

        // Format normal number
        const coeff = self.coefficient;
        const exp = self.exponent;

        if (exp >= 0) {
            // Integer or needs trailing zeros (e.g., 123 with exp=2 -> 12300)
            try result.appendSlice(coeff);
            for (0..@intCast(exp)) |_| {
                try result.append('0');
            }
        } else {
            // Negative exponent (decimal point)
            const neg_exp: usize = @intCast(-exp);
            if (neg_exp >= coeff.len) {
                // Need leading "0." with zeros (e.g., 0.00123)
                try result.appendSlice("0.");
                for (0..neg_exp - coeff.len) |_| {
                    try result.append('0');
                }
                try result.appendSlice(coeff);
            } else {
                // Decimal point in middle (e.g., 12.3)
                const decimal_pos = coeff.len - neg_exp;
                try result.appendSlice(coeff[0..decimal_pos]);
                try result.append('.');
                try result.appendSlice(coeff[decimal_pos..]);
            }
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "decimal zero" {
    const z = Decimal.zero;
    try std.testing.expect(z.isZero());
    try std.testing.expect(!z.isNegative());
    try std.testing.expect(z.isFinite());
}

test "decimal one" {
    const one = Decimal.one;
    try std.testing.expect(!one.isZero());
    try std.testing.expectEqualStrings("1", one.coefficient);
}

test "decimal special values" {
    const inf = Decimal.infinity;
    try std.testing.expect(inf.isInfinite());
    try std.testing.expect(!inf.isFinite());

    const nan_v = Decimal.nan_value;
    try std.testing.expect(nan_v.isNan());
}

test "decimal parse" {
    const allocator = std.testing.allocator;

    const d1 = try Decimal.parse(allocator, "123.45");
    defer allocator.free(d1.coefficient);
    try std.testing.expectEqualStrings("12345", d1.coefficient);
    try std.testing.expectEqual(@as(i32, -2), d1.exponent);

    const d2 = try Decimal.parse(allocator, "-42");
    defer allocator.free(d2.coefficient);
    try std.testing.expectEqual(@as(u1, 1), d2.sign);
}

test "decimal format" {
    const allocator = std.testing.allocator;

    const inf_str = try Decimal.infinity.format(allocator);
    defer allocator.free(inf_str);
    try std.testing.expectEqualStrings("Infinity", inf_str);

    const neg_inf_str = try Decimal.negative_infinity.format(allocator);
    defer allocator.free(neg_inf_str);
    try std.testing.expectEqualStrings("-Infinity", neg_inf_str);
}

test "decimal negate" {
    const one = Decimal.one;
    const neg = one.negate();
    try std.testing.expectEqual(@as(u1, 1), neg.sign);

    const back = neg.negate();
    try std.testing.expectEqual(@as(u1, 0), back.sign);
}
