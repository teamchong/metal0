/// Operator operations with concrete types to reduce monomorphization
/// These functions are called by operator structs (OperatorMod, OperatorPow, etc.)
/// instead of doing inline type checks, which would cause O(n²) monomorphization.
///
/// Pattern: O(n²) anytype → O(n) concrete functions + O(1) dispatch
const std = @import("std");
const float_ops = @import("float_ops/arithmetic.zig");

// =============================================================================
// Modulo Operations
// =============================================================================

/// Result of polymorphic modulo operation - preserves int/float distinction
pub const ModResult = union(enum) {
    int: i64,
    float: f64,

    /// Convert to f64 for consistent handling
    pub fn toFloat(self: ModResult) f64 {
        return switch (self) {
            .int => |i| @floatFromInt(i),
            .float => |f| f,
        };
    }

    /// Convert to i64 (truncates floats - use only when certain result is int)
    pub fn toInt(self: ModResult) i64 {
        return switch (self) {
            .int => |i| i,
            .float => |f| @intFromFloat(f),
        };
    }
};

/// Modulo for i64 (Python semantics: floored)
pub fn modI64(a: i64, b: i64) i64 {
    return @mod(a, b);
}

/// Modulo for f64 (Python floored semantics)
pub fn modF64(a: f64, b: f64) f64 {
    return float_ops.pyFloatMod(a, b);
}

/// Polymorphic numeric modulo - handles mixed types (int, float, anytype)
/// Used by generated class methods where types are not known at compile time
/// Returns ModResult tagged union to preserve type information:
///   int % int → ModResult.int
///   float % any → ModResult.float
///   any % float → ModResult.float
pub fn pyModNumeric(_: std.mem.Allocator, a: anytype, b: anytype) ModResult {
    const AType = @TypeOf(a);
    const BType = @TypeOf(b);
    const a_info = @typeInfo(AType);
    const b_info = @typeInfo(BType);

    // Both integers - use native @mod, return int
    if ((a_info == .int or a_info == .comptime_int) and (b_info == .int or b_info == .comptime_int)) {
        return .{ .int = @intCast(@mod(@as(i64, @intCast(a)), @as(i64, @intCast(b)))) };
    }

    // At least one float - use Python floored mod, return float
    const af: f64 = switch (a_info) {
        .int, .comptime_int => @floatFromInt(a),
        .float, .comptime_float => @floatCast(a),
        else => @as(f64, 0),
    };
    const bf: f64 = switch (b_info) {
        .int, .comptime_int => @floatFromInt(b),
        .float, .comptime_float => @floatCast(b),
        else => @as(f64, 1),
    };
    return .{ .float = float_ops.pyFloatMod(af, bf) };
}

// =============================================================================
// Power Operations
// =============================================================================

/// Power for i64 - converts to f64 internally
pub fn powI64(base: i64, exp: i64) !i64 {
    const base_f: f64 = @floatFromInt(base);
    const exp_f: f64 = @floatFromInt(exp);
    const result = std.math.pow(f64, base_f, exp_f);
    return @intFromFloat(result);
}

/// Power for f64
pub fn powF64(base: f64, exp: f64) !f64 {
    // Python raises ZeroDivisionError for 0.0 ** negative
    if (base == 0.0 and exp < 0.0) {
        return error.ZeroDivisionError;
    }
    return std.math.pow(f64, base, exp);
}

// =============================================================================
// True Division Operations (always returns f64)
// =============================================================================

/// True division for i64 operands (returns f64)
pub fn truedivI64(a: i64, b: i64) f64 {
    const a_f: f64 = @floatFromInt(a);
    const b_f: f64 = @floatFromInt(b);
    return a_f / b_f;
}

/// True division for f64 operands
pub fn truedivF64(a: f64, b: f64) f64 {
    return a / b;
}

// =============================================================================
// Floor Division Operations
// =============================================================================

/// Floor division for i64
pub fn floordivI64(a: i64, b: i64) i64 {
    return @divFloor(a, b);
}

/// Floor division for f64
pub fn floordivF64(a: f64, b: f64) f64 {
    return @floor(a / b);
}

// =============================================================================
// Tests
// =============================================================================

test "modI64" {
    try std.testing.expectEqual(@as(i64, 1), modI64(10, 3));
    try std.testing.expectEqual(@as(i64, 2), modI64(-10, 3)); // Python floored semantics
    try std.testing.expectEqual(@as(i64, -2), modI64(10, -3));
}

test "modF64" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), modF64(10.0, 3.0), 0.0001);
}

test "powI64" {
    try std.testing.expectEqual(@as(i64, 8), try powI64(2, 3));
    try std.testing.expectEqual(@as(i64, 1), try powI64(5, 0));
}

test "powF64" {
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), try powF64(2.0, 3.0), 0.0001);
    // Zero to negative power should error
    try std.testing.expectError(error.ZeroDivisionError, powF64(0.0, -1.0));
}

test "truedivI64" {
    try std.testing.expectApproxEqAbs(@as(f64, 3.333333), truedivI64(10, 3), 0.0001);
}

test "truedivF64" {
    try std.testing.expectApproxEqAbs(@as(f64, 3.333333), truedivF64(10.0, 3.0), 0.0001);
}

test "floordivI64" {
    try std.testing.expectEqual(@as(i64, 3), floordivI64(10, 3));
    try std.testing.expectEqual(@as(i64, -4), floordivI64(-10, 3)); // Python floored semantics
}

test "floordivF64" {
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), floordivF64(10.0, 3.0), 0.0001);
}

test "pyModNumeric int % int" {
    const result = pyModNumeric(undefined, @as(i64, 10), @as(i64, 3));
    try std.testing.expectEqual(ModResult{ .int = 1 }, result);
}

test "pyModNumeric float % float preserves fractional part" {
    // This was the bug: 5.5 % 2.0 should return 1.5, not 1
    const result = pyModNumeric(undefined, @as(f64, 5.5), @as(f64, 2.0));
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.float, 0.0001);
}

test "pyModNumeric negative float uses Python floored semantics" {
    // -5.5 % 2.0 = 0.5 in Python (floored, result has same sign as divisor)
    // Not -1.5 as Zig's @mod would give (truncated)
    const result = pyModNumeric(undefined, @as(f64, -5.5), @as(f64, 2.0));
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result.float, 0.0001);
}

test "pyModNumeric int % float returns float" {
    const result = pyModNumeric(undefined, @as(i64, 5), @as(f64, 2.0));
    // 5 % 2.0 = 1.0
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.float, 0.0001);
}

test "pyModNumeric float % int returns float" {
    const result = pyModNumeric(undefined, @as(f64, 5.5), @as(i64, 2));
    // 5.5 % 2 = 1.5
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.float, 0.0001);
}

test "ModResult.toFloat works" {
    const int_result = ModResult{ .int = 42 };
    try std.testing.expectEqual(@as(f64, 42.0), int_result.toFloat());

    const float_result = ModResult{ .float = 3.14 };
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), float_result.toFloat(), 0.0001);
}
