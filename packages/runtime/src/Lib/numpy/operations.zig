//! NumPy Array Operations
//!
//! Element-wise operations, matrix operations, and unary functions.
//! Automatically dispatches to Metal GPU on macOS for large arrays.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ndarray_mod = @import("ndarray.zig");
const ndarray = ndarray_mod.ndarray;
const creation = @import("creation.zig");

// ============================================================================
// Comptime Platform Detection
// ============================================================================

/// Comptime constant - zero overhead on non-macOS platforms
pub const use_metal = builtin.os.tag == .macos;

/// GPU threshold - only use Metal for arrays larger than this (overhead not worth it for small)
const GPU_THRESHOLD: usize = 10000;

// Conditionally import Metal module
const metal = if (use_metal) @import("../../metal/metal.zig") else struct {};

// ============================================================================
// Element-wise Binary Operations
// ============================================================================

/// Element-wise addition: C = A + B
/// np.add(a, b) or a + b
pub fn add(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    if (!shapesMatch(a.shape, b.shape)) {
        return error.ShapeMismatch;
    }

    // Comptime branch - non-macOS builds don't compile Metal code
    if (comptime use_metal) {
        if (a.size > GPU_THRESHOLD) {
            return metalAdd(allocator, a, b);
        }
    }
    return cpuAdd(allocator, a, b);
}

/// Element-wise subtraction: C = A - B
/// np.subtract(a, b) or a - b
pub fn subtract(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    if (!shapesMatch(a.shape, b.shape)) {
        return error.ShapeMismatch;
    }

    if (comptime use_metal) {
        if (a.size > GPU_THRESHOLD) {
            return metalSubtract(allocator, a, b);
        }
    }
    return cpuSubtract(allocator, a, b);
}

/// Element-wise multiplication: C = A * B
/// np.multiply(a, b) or a * b
pub fn multiply(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    if (!shapesMatch(a.shape, b.shape)) {
        return error.ShapeMismatch;
    }

    if (comptime use_metal) {
        if (a.size > GPU_THRESHOLD) {
            return metalMultiply(allocator, a, b);
        }
    }
    return cpuMultiply(allocator, a, b);
}

/// Element-wise division: C = A / B
/// np.divide(a, b) or a / b
pub fn divide(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    if (!shapesMatch(a.shape, b.shape)) {
        return error.ShapeMismatch;
    }

    if (comptime use_metal) {
        if (a.size > GPU_THRESHOLD) {
            return metalDivide(allocator, a, b);
        }
    }
    return cpuDivide(allocator, a, b);
}

// ============================================================================
// Matrix Operations
// ============================================================================

/// Matrix multiplication: C = A @ B
/// np.matmul(a, b) or a @ b
pub fn matmul(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    // Validate shapes for matrix multiplication
    if (a.ndim != 2 or b.ndim != 2) {
        return error.InvalidDimensions;
    }
    if (a.shape[1] != b.shape[0]) {
        return error.ShapeMismatch;
    }

    const m = a.shape[0];
    const k = a.shape[1];
    const n = b.shape[1];

    // Use Metal for large matrices
    if (comptime use_metal) {
        if (m * k > GPU_THRESHOLD or k * n > GPU_THRESHOLD) {
            return metalMatmul(allocator, a, b, m, n, k);
        }
    }
    return cpuMatmul(allocator, a, b, m, n, k);
}

/// Dot product
/// np.dot(a, b)
pub fn dot(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    // For 1D arrays, dot is inner product
    if (a.ndim == 1 and b.ndim == 1) {
        if (a.size != b.size) return error.ShapeMismatch;

        var result: f64 = 0;
        for (0..a.size) |i| {
            result += a.data[i] * b.data[i];
        }

        const data = try allocator.alloc(f64, 1);
        data[0] = result;
        return ndarray.initWithData(allocator, data, &.{1}, .float64);
    }

    // For 2D arrays, dot is matmul
    if (a.ndim == 2 and b.ndim == 2) {
        return matmul(allocator, a, b);
    }

    return error.InvalidDimensions;
}

// ============================================================================
// Scalar Operations
// ============================================================================

/// Add scalar to array: C = A + scalar
pub fn addScalar(allocator: Allocator, a: ndarray, scalar: f64) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = a.data[i] + scalar;
    }
    return result;
}

/// Multiply array by scalar: C = A * scalar
pub fn multiplyScalar(allocator: Allocator, a: ndarray, scalar: f64) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = a.data[i] * scalar;
    }
    return result;
}

/// Subtract scalar from array: C = A - scalar
pub fn subtractScalar(allocator: Allocator, a: ndarray, scalar: f64) !ndarray {
    return addScalar(allocator, a, -scalar);
}

/// Divide array by scalar: C = A / scalar
pub fn divideScalar(allocator: Allocator, a: ndarray, scalar: f64) !ndarray {
    return multiplyScalar(allocator, a, 1.0 / scalar);
}

/// Power: C = A ** scalar
pub fn power(allocator: Allocator, a: ndarray, exponent: f64) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = std.math.pow(f64, a.data[i], exponent);
    }
    return result;
}

// ============================================================================
// Unary Operations
// ============================================================================

/// Negation: C = -A
/// np.negative(a) or -a
pub fn negative(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = -a.data[i];
    }
    return result;
}

/// Absolute value: C = |A|
/// np.abs(a)
pub fn abs(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = @abs(a.data[i]);
    }
    return result;
}

/// Square root: C = sqrt(A)
/// np.sqrt(a)
pub fn sqrt(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = @sqrt(a.data[i]);
    }
    return result;
}

/// Exponential: C = exp(A)
/// np.exp(a)
pub fn exp(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = @exp(a.data[i]);
    }
    return result;
}

/// Natural logarithm: C = log(A)
/// np.log(a)
pub fn log(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = @log(a.data[i]);
    }
    return result;
}

/// Base-10 logarithm: C = log10(A)
/// np.log10(a)
pub fn log10(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = std.math.log10(a.data[i]);
    }
    return result;
}

/// Sine: C = sin(A)
/// np.sin(a)
pub fn sin(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = @sin(a.data[i]);
    }
    return result;
}

/// Cosine: C = cos(A)
/// np.cos(a)
pub fn cos(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = @cos(a.data[i]);
    }
    return result;
}

/// Tangent: C = tan(A)
/// np.tan(a)
pub fn tan(allocator: Allocator, a: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = @tan(a.data[i]);
    }
    return result;
}

// ============================================================================
// CPU Implementations
// ============================================================================

fn cpuAdd(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = a.data[i] + b.data[i];
    }
    return result;
}

fn cpuSubtract(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = a.data[i] - b.data[i];
    }
    return result;
}

fn cpuMultiply(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = a.data[i] * b.data[i];
    }
    return result;
}

fn cpuDivide(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    var result = try ndarray.init(allocator, a.shape, a.dtype);
    for (0..a.size) |i| {
        result.data[i] = a.data[i] / b.data[i];
    }
    return result;
}

fn cpuMatmul(allocator: Allocator, a: ndarray, b: ndarray, m: usize, n: usize, k: usize) !ndarray {
    var result = try creation.zeros(allocator, &.{ m, n });

    // Simple triple-loop matmul
    for (0..m) |i| {
        for (0..n) |j| {
            var acc: f64 = 0;
            for (0..k) |kk| {
                acc += a.get(&.{ i, kk }) * b.get(&.{ kk, j });
            }
            result.set(&.{ i, j }, acc);
        }
    }

    return result;
}

// ============================================================================
// Metal GPU Implementations (macOS only - DCE'd on other platforms)
// ============================================================================

fn metalAdd(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    if (comptime !use_metal) unreachable;

    // Convert f64 to f32 for Metal
    const a_f32 = try convertToF32(allocator, a.data);
    defer allocator.free(a_f32);
    const b_f32 = try convertToF32(allocator, b.data);
    defer allocator.free(b_f32);

    // Call Metal kernel
    const result_f32 = try metal.add(allocator, a_f32, b_f32);
    defer allocator.free(result_f32);

    // Convert back to f64
    const result_data = try convertToF64(allocator, result_f32);
    return ndarray.initWithData(allocator, result_data, a.shape, a.dtype);
}

fn metalSubtract(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    if (comptime !use_metal) unreachable;

    const a_f32 = try convertToF32(allocator, a.data);
    defer allocator.free(a_f32);
    const b_f32 = try convertToF32(allocator, b.data);
    defer allocator.free(b_f32);

    const result_f32 = try metal.sub(allocator, a_f32, b_f32);
    defer allocator.free(result_f32);

    const result_data = try convertToF64(allocator, result_f32);
    return ndarray.initWithData(allocator, result_data, a.shape, a.dtype);
}

fn metalMultiply(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    if (comptime !use_metal) unreachable;

    const a_f32 = try convertToF32(allocator, a.data);
    defer allocator.free(a_f32);
    const b_f32 = try convertToF32(allocator, b.data);
    defer allocator.free(b_f32);

    const result_f32 = try metal.mul(allocator, a_f32, b_f32);
    defer allocator.free(result_f32);

    const result_data = try convertToF64(allocator, result_f32);
    return ndarray.initWithData(allocator, result_data, a.shape, a.dtype);
}

fn metalDivide(allocator: Allocator, a: ndarray, b: ndarray) !ndarray {
    if (comptime !use_metal) unreachable;

    const a_f32 = try convertToF32(allocator, a.data);
    defer allocator.free(a_f32);
    const b_f32 = try convertToF32(allocator, b.data);
    defer allocator.free(b_f32);

    const result_f32 = try metal.div(allocator, a_f32, b_f32);
    defer allocator.free(result_f32);

    const result_data = try convertToF64(allocator, result_f32);
    return ndarray.initWithData(allocator, result_data, a.shape, a.dtype);
}

fn metalMatmul(allocator: Allocator, a: ndarray, b: ndarray, m: usize, n: usize, k: usize) !ndarray {
    if (comptime !use_metal) unreachable;

    const a_f32 = try convertToF32(allocator, a.data);
    defer allocator.free(a_f32);
    const b_f32 = try convertToF32(allocator, b.data);
    defer allocator.free(b_f32);

    const result_f32 = try metal.matmul(allocator, a_f32, b_f32, m, n, k);
    defer allocator.free(result_f32);

    const result_data = try convertToF64(allocator, result_f32);
    return ndarray.initWithData(allocator, result_data, &.{ m, n }, .float64);
}

// ============================================================================
// Utility Functions
// ============================================================================

fn shapesMatch(a: []const usize, b: []const usize) bool {
    if (a.len != b.len) return false;
    for (a, b) |dim_a, dim_b| {
        if (dim_a != dim_b) return false;
    }
    return true;
}

fn convertToF32(allocator: Allocator, data: []const f64) ![]f32 {
    const result = try allocator.alloc(f32, data.len);
    for (data, 0..) |val, i| {
        result[i] = @floatCast(val);
    }
    return result;
}

fn convertToF64(allocator: Allocator, data: []const f32) ![]f64 {
    const result = try allocator.alloc(f64, data.len);
    for (data, 0..) |val, i| {
        result[i] = @floatCast(val);
    }
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "add" {
    const allocator = std.testing.allocator;

    var a = try creation.array(allocator, &.{ 1.0, 2.0, 3.0 });
    defer a.deinit();
    var b = try creation.array(allocator, &.{ 4.0, 5.0, 6.0 });
    defer b.deinit();

    var c = try add(allocator, a, b);
    defer c.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 5.0), c.get(&.{0}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), c.get(&.{1}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), c.get(&.{2}), 0.001);
}

test "multiply" {
    const allocator = std.testing.allocator;

    var a = try creation.array(allocator, &.{ 1.0, 2.0, 3.0 });
    defer a.deinit();
    var b = try creation.array(allocator, &.{ 4.0, 5.0, 6.0 });
    defer b.deinit();

    var c = try multiply(allocator, a, b);
    defer c.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 4.0), c.get(&.{0}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), c.get(&.{1}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 18.0), c.get(&.{2}), 0.001);
}

test "matmul" {
    const allocator = std.testing.allocator;

    // 2x2 @ 2x2
    var a = try creation.zeros(allocator, &.{ 2, 2 });
    defer a.deinit();
    a.set(&.{ 0, 0 }, 1.0);
    a.set(&.{ 0, 1 }, 2.0);
    a.set(&.{ 1, 0 }, 3.0);
    a.set(&.{ 1, 1 }, 4.0);

    var b = try creation.zeros(allocator, &.{ 2, 2 });
    defer b.deinit();
    b.set(&.{ 0, 0 }, 5.0);
    b.set(&.{ 0, 1 }, 6.0);
    b.set(&.{ 1, 0 }, 7.0);
    b.set(&.{ 1, 1 }, 8.0);

    var c = try matmul(allocator, a, b);
    defer c.deinit();

    // [[1,2],[3,4]] @ [[5,6],[7,8]] = [[19,22],[43,50]]
    try std.testing.expectApproxEqAbs(@as(f64, 19.0), c.get(&.{ 0, 0 }), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 22.0), c.get(&.{ 0, 1 }), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 43.0), c.get(&.{ 1, 0 }), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), c.get(&.{ 1, 1 }), 0.001);
}

test "sqrt" {
    const allocator = std.testing.allocator;

    var a = try creation.array(allocator, &.{ 1.0, 4.0, 9.0, 16.0 });
    defer a.deinit();

    var b = try sqrt(allocator, a);
    defer b.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 1.0), b.get(&.{0}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), b.get(&.{1}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), b.get(&.{2}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), b.get(&.{3}), 0.001);
}
