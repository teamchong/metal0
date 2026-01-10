//! test.test_future_stmt.test_division - Tests for `from __future__ import division`
//!
//! PEP 238 introduced true division by default in Python 3.
//! In Python 2, `/` was floor division for integers. With this future import
//! (or in Python 3), `/` always performs true division.
//!
//! This module tests division semantics to ensure proper behavior.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html
//! PEP 238: https://peps.python.org/pep-0238/

const std = @import("std");
const testing = std.testing;
const math = std.math;

// ============================================================================
// Division Operation Types
// ============================================================================

/// Represents the type of division operation
pub const DivisionMode = enum {
    /// True division: always returns float (Python 3 default, `/` operator)
    true_division,
    /// Floor division: returns integer floor (`//` operator)
    floor_division,
    /// Classic division: int/int = int, float involved = float (Python 2 default)
    classic_division,

    /// Get the mode name as a string
    pub fn name(self: DivisionMode) []const u8 {
        return switch (self) {
            .true_division => "true division",
            .floor_division => "floor division",
            .classic_division => "classic division",
        };
    }
};

/// Division result that can be either integer or float
pub const DivisionResult = union(enum) {
    int_result: i64,
    float_result: f64,

    const Self = @This();

    /// Create an integer result
    pub fn fromInt(value: i64) Self {
        return .{ .int_result = value };
    }

    /// Create a float result
    pub fn fromFloat(value: f64) Self {
        return .{ .float_result = value };
    }

    /// Convert to float regardless of internal type
    pub fn toFloat(self: Self) f64 {
        return switch (self) {
            .int_result => |i| @floatFromInt(i),
            .float_result => |f| f,
        };
    }

    /// Check if result is an integer type
    pub fn isInt(self: Self) bool {
        return self == .int_result;
    }

    /// Check if result is a float type
    pub fn isFloat(self: Self) bool {
        return self == .float_result;
    }

    /// Check approximate equality with tolerance
    pub fn approxEql(self: Self, expected: f64, tolerance: f64) bool {
        const actual = self.toFloat();
        return @abs(actual - expected) <= tolerance;
    }
};

// ============================================================================
// Division Operations
// ============================================================================

/// Perform true division (always returns float)
/// This is the Python 3 behavior for the `/` operator
pub fn trueDivide(numerator: anytype, denominator: anytype) !f64 {
    const T = @TypeOf(numerator);
    const U = @TypeOf(denominator);

    const num: f64 = switch (@typeInfo(T)) {
        .int, .comptime_int => @floatFromInt(numerator),
        .float, .comptime_float => @floatCast(numerator),
        else => @compileError("unsupported type for division"),
    };

    const den: f64 = switch (@typeInfo(U)) {
        .int, .comptime_int => @floatFromInt(denominator),
        .float, .comptime_float => @floatCast(denominator),
        else => @compileError("unsupported type for division"),
    };

    if (den == 0) {
        return error.DivisionByZero;
    }

    return num / den;
}

/// Perform floor division (returns integer floor)
/// This is the Python behavior for the `//` operator
pub fn floorDivide(numerator: anytype, denominator: anytype) !i64 {
    const T = @TypeOf(numerator);
    const U = @TypeOf(denominator);

    const num: f64 = switch (@typeInfo(T)) {
        .int, .comptime_int => @floatFromInt(numerator),
        .float, .comptime_float => @floatCast(numerator),
        else => @compileError("unsupported type for division"),
    };

    const den: f64 = switch (@typeInfo(U)) {
        .int, .comptime_int => @floatFromInt(denominator),
        .float, .comptime_float => @floatCast(denominator),
        else => @compileError("unsupported type for division"),
    };

    if (den == 0) {
        return error.DivisionByZero;
    }

    return @intFromFloat(@floor(num / den));
}

/// Perform modulo operation (Python semantics)
/// Python's modulo always has the same sign as the divisor
pub fn modulo(numerator: anytype, denominator: anytype) !i64 {
    const T = @TypeOf(numerator);
    const U = @TypeOf(denominator);

    const num: i64 = switch (@typeInfo(T)) {
        .int, .comptime_int => @intCast(numerator),
        .float, .comptime_float => @intFromFloat(numerator),
        else => @compileError("unsupported type for modulo"),
    };

    const den: i64 = switch (@typeInfo(U)) {
        .int, .comptime_int => @intCast(denominator),
        .float, .comptime_float => @intFromFloat(denominator),
        else => @compileError("unsupported type for modulo"),
    };

    if (den == 0) {
        return error.DivisionByZero;
    }

    // Python semantics: result has same sign as divisor
    const result = @mod(num, den);
    return result;
}

/// Perform divmod operation (returns both quotient and remainder)
/// Python's divmod(a, b) returns (a // b, a % b)
pub fn divmod(numerator: anytype, denominator: anytype) !struct { quotient: i64, remainder: i64 } {
    const q = try floorDivide(numerator, denominator);
    const r = try modulo(numerator, denominator);
    return .{ .quotient = q, .remainder = r };
}

// ============================================================================
// Division Context Manager
// ============================================================================

/// Context manager for temporarily changing division behavior
/// In Python 2, this would simulate `from __future__ import division`
pub const DivisionContext = struct {
    mode: DivisionMode,
    previous_mode: DivisionMode = .true_division,

    /// Current global division mode
    var current_mode: DivisionMode = .true_division;

    const Self = @This();

    pub fn init(mode: DivisionMode) Self {
        return .{ .mode = mode };
    }

    pub fn __enter__(self: *Self) *Self {
        self.previous_mode = current_mode;
        current_mode = self.mode;
        return self;
    }

    pub fn __exit__(self: *Self) void {
        current_mode = self.previous_mode;
    }

    /// Get the current division mode
    pub fn getCurrentMode() DivisionMode {
        return current_mode;
    }
};

// ============================================================================
// Special Division Cases
// ============================================================================

/// Handle division of negative numbers with floor semantics
/// Python: -7 // 2 = -4 (not -3 as with truncation)
pub fn handleNegativeFloorDivision(a: i64, b: i64) !i64 {
    if (b == 0) return error.DivisionByZero;

    // Python floor division rounds toward negative infinity
    const q = @divFloor(a, b);
    return q;
}

/// Check if division result is exact (no remainder)
pub fn isExactDivision(a: i64, b: i64) bool {
    if (b == 0) return false;
    return @rem(a, b) == 0;
}

/// Calculate greatest common divisor using Euclidean algorithm
pub fn gcd(a: i64, b: i64) i64 {
    var x = if (a < 0) -a else a;
    var y = if (b < 0) -b else b;

    while (y != 0) {
        const temp = @rem(x, y);
        x = y;
        y = temp;
    }
    return x;
}

/// Reduce fraction to lowest terms
pub fn reduceFraction(numerator: i64, denominator: i64) struct { num: i64, den: i64 } {
    if (denominator == 0) return .{ .num = numerator, .den = 0 };

    const g = gcd(numerator, denominator);
    var num = @divExact(numerator, g);
    var den = @divExact(denominator, g);

    // Ensure denominator is positive
    if (den < 0) {
        num = -num;
        den = -den;
    }

    return .{ .num = num, .den = den };
}

// ============================================================================
// Float Division Edge Cases
// ============================================================================

/// Handle division that might result in infinity
pub fn safeDivide(a: f64, b: f64) DivisionResult {
    if (b == 0) {
        if (a > 0) return .{ .float_result = math.inf(f64) };
        if (a < 0) return .{ .float_result = -math.inf(f64) };
        return .{ .float_result = math.nan(f64) };
    }
    return .{ .float_result = a / b };
}

/// Check if a float division would overflow
pub fn wouldOverflow(a: f64, b: f64) bool {
    if (b == 0) return true;
    const result = a / b;
    return math.isInf(result);
}

/// Round division result to specified decimal places
pub fn roundedDivide(a: f64, b: f64, decimals: u32) !f64 {
    if (b == 0) return error.DivisionByZero;

    const result = a / b;
    const multiplier = math.pow(f64, 10.0, @floatFromInt(decimals));
    return @round(result * multiplier) / multiplier;
}

// ============================================================================
// Tests
// ============================================================================

test "true_division_integers" {
    const result = try trueDivide(7, 2);
    try testing.expectApproxEqAbs(@as(f64, 3.5), result, 0.0001);
}

test "true_division_negative" {
    const result = try trueDivide(-7, 2);
    try testing.expectApproxEqAbs(@as(f64, -3.5), result, 0.0001);
}

test "floor_division_positive" {
    const result = try floorDivide(7, 2);
    try testing.expectEqual(@as(i64, 3), result);
}

test "floor_division_negative" {
    // Python: -7 // 2 = -4 (floor toward negative infinity)
    const result = try floorDivide(-7, 2);
    try testing.expectEqual(@as(i64, -4), result);
}

test "floor_division_negative_divisor" {
    // Python: 7 // -2 = -4
    const result = try floorDivide(7, -2);
    try testing.expectEqual(@as(i64, -4), result);
}

test "modulo_positive" {
    const result = try modulo(7, 3);
    try testing.expectEqual(@as(i64, 1), result);
}

test "modulo_negative_dividend" {
    // Python: -7 % 3 = 2 (same sign as divisor)
    const result = try modulo(-7, 3);
    try testing.expectEqual(@as(i64, 2), result);
}

test "divmod_operation" {
    const result = try divmod(17, 5);
    try testing.expectEqual(@as(i64, 3), result.quotient);
    try testing.expectEqual(@as(i64, 2), result.remainder);
}

test "division_by_zero_error" {
    try testing.expectError(error.DivisionByZero, trueDivide(1, 0));
    try testing.expectError(error.DivisionByZero, floorDivide(1, 0));
}

test "division_context_manager" {
    try testing.expectEqual(DivisionMode.true_division, DivisionContext.getCurrentMode());

    var ctx = DivisionContext.init(.floor_division);
    _ = ctx.__enter__();
    try testing.expectEqual(DivisionMode.floor_division, DivisionContext.getCurrentMode());
    ctx.__exit__();

    try testing.expectEqual(DivisionMode.true_division, DivisionContext.getCurrentMode());
}

test "is_exact_division" {
    try testing.expect(isExactDivision(10, 2));
    try testing.expect(isExactDivision(15, 3));
    try testing.expect(!isExactDivision(7, 3));
}

test "gcd_calculation" {
    try testing.expectEqual(@as(i64, 6), gcd(12, 18));
    try testing.expectEqual(@as(i64, 1), gcd(17, 23));
    try testing.expectEqual(@as(i64, 5), gcd(0, 5));
}

test "reduce_fraction" {
    const result = reduceFraction(12, 18);
    try testing.expectEqual(@as(i64, 2), result.num);
    try testing.expectEqual(@as(i64, 3), result.den);
}

test "reduce_fraction_negative" {
    const result = reduceFraction(-6, 9);
    try testing.expectEqual(@as(i64, -2), result.num);
    try testing.expectEqual(@as(i64, 3), result.den);
}

test "safe_divide_by_zero_positive" {
    const result = safeDivide(1.0, 0.0);
    try testing.expect(result.isFloat());
    try testing.expect(math.isPositiveInf(result.float_result));
}

test "safe_divide_by_zero_negative" {
    const result = safeDivide(-1.0, 0.0);
    try testing.expect(math.isNegativeInf(result.float_result));
}

test "safe_divide_zero_by_zero" {
    const result = safeDivide(0.0, 0.0);
    try testing.expect(math.isNan(result.float_result));
}

test "rounded_divide" {
    const result = try roundedDivide(10.0, 3.0, 2);
    try testing.expectApproxEqAbs(@as(f64, 3.33), result, 0.01);
}

test "division_result_type" {
    const int_result = DivisionResult.fromInt(42);
    const float_result = DivisionResult.fromFloat(3.14);

    try testing.expect(int_result.isInt());
    try testing.expect(!int_result.isFloat());
    try testing.expect(float_result.isFloat());
    try testing.expect(!float_result.isInt());
}

test "division_result_approx_eql" {
    const result = DivisionResult.fromFloat(3.14159);
    try testing.expect(result.approxEql(3.14, 0.01));
    try testing.expect(!result.approxEql(3.0, 0.01));
}

test "negative_floor_division_helper" {
    try testing.expectEqual(@as(i64, -4), try handleNegativeFloorDivision(-7, 2));
    try testing.expectEqual(@as(i64, 3), try handleNegativeFloorDivision(7, 2));
}

test "division_mode_names" {
    try testing.expectEqualStrings("true division", DivisionMode.true_division.name());
    try testing.expectEqualStrings("floor division", DivisionMode.floor_division.name());
    try testing.expectEqualStrings("classic division", DivisionMode.classic_division.name());
}
