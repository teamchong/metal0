//! test.test_ctypes.test_complex - Tests for complex number types
//! Reference: cpython/Lib/test/test_ctypes/test_complex.py

const std = @import("std");

pub const c_float_complex = struct {
    real: f32 = 0,
    imag: f32 = 0,
    pub fn init(r: f32, i: f32) @This() { return .{ .real = r, .imag = i }; }
    pub fn add(self: @This(), other: @This()) @This() {
        return .{ .real = self.real + other.real, .imag = self.imag + other.imag };
    }
};

pub const c_double_complex = struct {
    real: f64 = 0,
    imag: f64 = 0,
    pub fn init(r: f64, i: f64) @This() { return .{ .real = r, .imag = i }; }
};

test "complex_add" {
    const a = c_float_complex.init(1, 2);
    const b = c_float_complex.init(3, 4);
    const c = a.add(b);
    try std.testing.expectApproxEqAbs(@as(f32, 4), c.real, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), c.imag, 0.001);
}
