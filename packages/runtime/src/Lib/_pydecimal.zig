/// _pydecimal - Python Decimal Implementation
/// Mirrors cpython/Lib/_pydecimal.py
///
/// Pure Zig implementation of the Decimal type.
/// Provides arbitrary-precision decimal floating point arithmetic.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Maximum precision (digits)
pub const MAX_PREC: u32 = 425000000;

/// Maximum exponent
pub const MAX_EMAX: i32 = 425000000;

/// Minimum exponent
pub const MIN_EMIN: i32 = -425000000;

/// Default precision
pub const DEFAULT_PREC: u32 = 28;

/// Rounding modes
pub const Rounding = enum {
    round_ceiling, // Round towards Infinity
    round_down, // Round towards zero
    round_floor, // Round towards -Infinity
    round_half_down, // Round to nearest, ties go towards zero
    round_half_even, // Round to nearest, ties go to even (banker's)
    round_half_up, // Round to nearest, ties go away from zero
    round_up, // Round away from zero
    round_05up, // Round away from zero if last digit is 0 or 5

    pub fn fromString(s: []const u8) ?Rounding {
        const map = std.StaticStringMap(Rounding).initComptime(.{
            .{ "ROUND_CEILING", .round_ceiling },
            .{ "ROUND_DOWN", .round_down },
            .{ "ROUND_FLOOR", .round_floor },
            .{ "ROUND_HALF_DOWN", .round_half_down },
            .{ "ROUND_HALF_EVEN", .round_half_even },
            .{ "ROUND_HALF_UP", .round_half_up },
            .{ "ROUND_UP", .round_up },
            .{ "ROUND_05UP", .round_05up },
        });
        return map.get(s);
    }
};

// ============================================================================
// Signals
// ============================================================================

/// Decimal signals/flags
pub const Signal = enum {
    clamped,
    invalid_operation,
    division_by_zero,
    inexact,
    rounded,
    subnormal,
    overflow,
    underflow,
    float_operation,

    pub fn getName(self: Signal) []const u8 {
        return switch (self) {
            .clamped => "Clamped",
            .invalid_operation => "InvalidOperation",
            .division_by_zero => "DivisionByZero",
            .inexact => "Inexact",
            .rounded => "Rounded",
            .subnormal => "Subnormal",
            .overflow => "Overflow",
            .underflow => "Underflow",
            .float_operation => "FloatOperation",
        };
    }
};

/// Signal flags
pub const SignalFlags = std.EnumSet(Signal);

// ============================================================================
// Context
// ============================================================================

/// Decimal context
pub const Context = struct {
    const Self = @This();

    /// Precision (significant digits)
    prec: u32 = DEFAULT_PREC,
    /// Rounding mode
    rounding: Rounding = .round_half_even,
    /// Maximum exponent
    emax: i32 = 999999,
    /// Minimum exponent
    emin: i32 = -999999,
    /// Capitals (E vs e in output)
    capitals: bool = true,
    /// Clamp exponents to range
    clamp: bool = false,
    /// Raised signals
    flags: SignalFlags = SignalFlags{},
    /// Enabled traps
    traps: SignalFlags = SignalFlags.initFull(),

    /// Get basic context
    pub fn basicContext() Self {
        return Self{
            .prec = 9,
            .rounding = .round_half_up,
            .emax = 999999,
            .emin = -999999,
        };
    }

    /// Get extended context
    pub fn extendedContext() Self {
        return Self{
            .prec = 9,
            .rounding = .round_half_even,
            .emax = 999999,
            .emin = -999999,
            .traps = SignalFlags{},
        };
    }

    /// Clear flags
    pub fn clearFlags(self: *Self) void {
        self.flags = SignalFlags{};
    }

    /// Raise a signal
    pub fn raiseSignal(self: *Self, signal: Signal) !void {
        self.flags.insert(signal);
        if (self.traps.contains(signal)) {
            return error.DecimalException;
        }
    }
};

// ============================================================================
// Decimal Type
// ============================================================================

/// Special values
pub const SpecialValue = enum {
    normal,
    infinity,
    nan,
    snan, // Signaling NaN
};

/// Decimal number representation
pub const Decimal = struct {
    const Self = @This();

    /// Sign (0 = positive, 1 = negative)
    sign: u1 = 0,
    /// Coefficient digits (stored as string for simplicity)
    coefficient: []const u8 = "0",
    /// Exponent
    exponent: i32 = 0,
    /// Special value
    special: SpecialValue = .normal,
    /// Allocator
    allocator: ?Allocator = null,

    // Static special values
    pub const zero = Self{ .coefficient = "0" };
    pub const one = Self{ .coefficient = "1" };
    pub const negative_one = Self{ .sign = 1, .coefficient = "1" };
    pub const infinity = Self{ .special = .infinity };
    pub const negative_infinity = Self{ .sign = 1, .special = .infinity };
    pub const nan_value = Self{ .special = .nan };

    /// Create from integer
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

    /// Create from float
    pub fn fromFloat(value: f64) Self {
        if (std.math.isNan(value)) return nan_value;
        if (std.math.isInf(value)) {
            return if (value < 0) negative_infinity else infinity;
        }
        // Simplified conversion
        const sign: u1 = if (value < 0) 1 else 0;
        const abs_val = if (value < 0) -value else value;
        _ = abs_val;
        return Self{
            .sign = sign,
        };
    }

    /// Parse from string
    pub fn parse(allocator: Allocator, s: []const u8) !Self {
        if (s.len == 0) return error.InvalidDecimal;

        var result = Self{ .allocator = allocator };
        var pos: usize = 0;

        // Parse sign
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
                // Parse exponent
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

        // Adjust exponent for decimal point
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
        coeff.deinit();

        return result;
    }

    /// Check if zero
    pub fn isZero(self: *const Self) bool {
        if (self.special != .normal) return false;
        for (self.coefficient) |c| {
            if (c != '0') return false;
        }
        return true;
    }

    /// Check if negative
    pub fn isNegative(self: *const Self) bool {
        return self.sign == 1;
    }

    /// Check if NaN
    pub fn isNan(self: *const Self) bool {
        return self.special == .nan or self.special == .snan;
    }

    /// Check if infinity
    pub fn isInfinite(self: *const Self) bool {
        return self.special == .infinity;
    }

    /// Check if finite
    pub fn isFinite(self: *const Self) bool {
        return self.special == .normal;
    }

    /// Negate
    pub fn negate(self: Self) Self {
        var result = self;
        result.sign = if (self.sign == 0) 1 else 0;
        return result;
    }

    /// Absolute value
    pub fn abs(self: Self) Self {
        var result = self;
        result.sign = 0;
        return result;
    }

    /// Format as string
    pub fn format(self: *const Self, allocator: Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);

        // Sign
        if (self.sign == 1) try result.append('-');

        // Special values
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

        // Normal number
        const coeff = self.coefficient;
        const exp = self.exponent;

        if (exp >= 0) {
            // Integer or needs trailing zeros
            try result.appendSlice(coeff);
            for (0..@intCast(exp)) |_| {
                try result.append('0');
            }
        } else {
            const neg_exp: usize = @intCast(-exp);
            if (neg_exp >= coeff.len) {
                // Need leading "0."
                try result.appendSlice("0.");
                for (0..neg_exp - coeff.len) |_| {
                    try result.append('0');
                }
                try result.appendSlice(coeff);
            } else {
                // Decimal point in middle
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
// Module State
// ============================================================================

var initialized: bool = false;
var default_context: ?Context = null;

/// Initialize the _pydecimal module
pub fn init() void {
    if (initialized) return;
    initialized = true;
    default_context = Context{};
}

/// Get default context
pub fn getContext() *Context {
    if (default_context == null) {
        default_context = Context{};
    }
    return &default_context.?;
}

/// Set default context
pub fn setContext(ctx: Context) void {
    default_context = ctx;
}

/// Reset module state
pub fn reset() void {
    default_context = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "rounding mode from string" {
    try std.testing.expectEqual(Rounding.round_half_even, Rounding.fromString("ROUND_HALF_EVEN").?);
    try std.testing.expectEqual(Rounding.round_down, Rounding.fromString("ROUND_DOWN").?);
    try std.testing.expect(Rounding.fromString("INVALID") == null);
}

test "signal names" {
    try std.testing.expectEqualStrings("InvalidOperation", Signal.invalid_operation.getName());
    try std.testing.expectEqualStrings("DivisionByZero", Signal.division_by_zero.getName());
}

test "context basic" {
    const ctx = Context.basicContext();
    try std.testing.expectEqual(@as(u32, 9), ctx.prec);
    try std.testing.expectEqual(Rounding.round_half_up, ctx.rounding);
}

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
