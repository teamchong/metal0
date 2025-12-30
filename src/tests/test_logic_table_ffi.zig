/// Test calling metal0-compiled @logic_table functions via C FFI
///
/// The simple_logic_table.a exports:
/// - MathOps_add(x: f64, y: f64) -> f64
/// - MathOps_multiply(x: f64, y: f64) -> f64
/// - MathOps_subtract(x: f64, y: f64) -> f64
/// - ScoreOps_weighted_score(a: f64, b: f64, w: f64) -> f64
const std = @import("std");

// C function declarations for the exported @logic_table functions
extern fn MathOps_add(x: f64, y: f64) callconv(.c) f64;
extern fn MathOps_multiply(x: f64, y: f64) callconv(.c) f64;
extern fn MathOps_subtract(x: f64, y: f64) callconv(.c) f64;
extern fn ScoreOps_weighted_score(a: f64, b: f64, w: f64) callconv(.c) f64;

test "MathOps_add" {
    const result = MathOps_add(3.0, 4.0);
    try std.testing.expectApproxEqAbs(7.0, result, 0.0001);
}

test "MathOps_multiply" {
    const result = MathOps_multiply(3.0, 4.0);
    try std.testing.expectApproxEqAbs(12.0, result, 0.0001);
}

test "MathOps_subtract" {
    const result = MathOps_subtract(10.0, 4.0);
    try std.testing.expectApproxEqAbs(6.0, result, 0.0001);
}

test "ScoreOps_weighted_score" {
    // weighted_score(a, b, w) = a * w + b * (1.0 - w)
    // weighted_score(10.0, 2.0, 0.5) = 10*0.5 + 2*0.5 = 5 + 1 = 6
    const result = ScoreOps_weighted_score(10.0, 2.0, 0.5);
    try std.testing.expectApproxEqAbs(6.0, result, 0.0001);
}

test "weighted_score with w=1.0" {
    // weighted_score(10.0, 2.0, 1.0) = 10*1 + 2*0 = 10
    const result = ScoreOps_weighted_score(10.0, 2.0, 1.0);
    try std.testing.expectApproxEqAbs(10.0, result, 0.0001);
}

test "weighted_score with w=0.0" {
    // weighted_score(10.0, 2.0, 0.0) = 10*0 + 2*1 = 2
    const result = ScoreOps_weighted_score(10.0, 2.0, 0.0);
    try std.testing.expectApproxEqAbs(2.0, result, 0.0001);
}
