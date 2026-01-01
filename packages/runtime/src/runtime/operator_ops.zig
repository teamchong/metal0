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

/// Python floored modulo for integers: result has same sign as divisor
/// This is different from Zig's @mod which uses truncated semantics.
/// Examples:
///   Python: -10 % 3 = 2 (floored)
///   Zig:    @mod(-10, 3) = -1 (truncated)
pub fn pyFlooredModInt(a: i64, b: i64) i64 {
    const quotient = @divFloor(a, b);
    return a - quotient * b;
}

/// Modulo for i64 (Python floored semantics)
pub fn modI64(a: i64, b: i64) i64 {
    return pyFlooredModInt(a, b);
}

/// Modulo for f64 (Python floored semantics)
pub fn modF64(a: f64, b: f64) f64 {
    return float_ops.pyFloatMod(a, b);
}

/// Polymorphic numeric modulo - handles mixed types (int, float, anytype)
/// Used by generated code where types are not known at compile time.
/// Always returns f64 to handle all cases uniformly.
/// Uses Python floored semantics (result has same sign as divisor).
pub fn pyModNumeric(_: std.mem.Allocator, a: anytype, b: anytype) f64 {
    const AType = @TypeOf(a);
    const BType = @TypeOf(b);
    const a_info = @typeInfo(AType);
    const b_info = @typeInfo(BType);

    // Convert both operands to f64 and use Python floored mod
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
    return float_ops.pyFloatMod(af, bf);
}

/// Alias for codegen compatibility - used by aug_assign and comp_conditions
pub const moduloRuntime = pyModNumeric;

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

test "pyFlooredModInt" {
    // Python floored semantics: result has same sign as divisor
    try std.testing.expectEqual(@as(i64, 1), pyFlooredModInt(10, 3));
    try std.testing.expectEqual(@as(i64, 2), pyFlooredModInt(-10, 3)); // NOT -1
    try std.testing.expectEqual(@as(i64, -2), pyFlooredModInt(10, -3)); // NOT 1
    try std.testing.expectEqual(@as(i64, -1), pyFlooredModInt(-10, -3));
}

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
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result, 0.0001);
}

test "pyModNumeric float % float preserves fractional part" {
    // This was the bug: 5.5 % 2.0 should return 1.5, not 1
    const result = pyModNumeric(undefined, @as(f64, 5.5), @as(f64, 2.0));
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result, 0.0001);
}

test "pyModNumeric negative float uses Python floored semantics" {
    // -5.5 % 2.0 = 0.5 in Python (floored, result has same sign as divisor)
    // Not -1.5 as Zig's @mod would give (truncated)
    const result = pyModNumeric(undefined, @as(f64, -5.5), @as(f64, 2.0));
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result, 0.0001);
}

test "pyModNumeric negative int uses Python floored semantics" {
    // -10 % 3 = 2 in Python (floored)
    const result = pyModNumeric(undefined, @as(i64, -10), @as(i64, 3));
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result, 0.0001);
}

test "pyModNumeric int % float returns float" {
    const result = pyModNumeric(undefined, @as(i64, 5), @as(f64, 2.0));
    // 5 % 2.0 = 1.0
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result, 0.0001);
}

test "pyModNumeric float % int returns float" {
    const result = pyModNumeric(undefined, @as(f64, 5.5), @as(i64, 2));
    // 5.5 % 2 = 1.5
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result, 0.0001);
}
