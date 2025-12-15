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

/// Modulo for i64 (Python semantics: floored)
pub fn modI64(a: i64, b: i64) i64 {
    return @mod(a, b);
}

/// Modulo for f64 (Python floored semantics)
pub fn modF64(a: f64, b: f64) f64 {
    return float_ops.pyFloatMod(a, b);
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
