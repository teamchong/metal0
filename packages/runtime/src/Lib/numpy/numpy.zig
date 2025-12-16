//! NumPy-compatible Array Module for metal0
//!
//! Provides NumPy-compatible N-dimensional arrays with automatic Metal GPU
//! acceleration on macOS. On other platforms, uses efficient CPU fallbacks.
//!
//! Usage in Python:
//!   import numpy as np
//!   a = np.array([1, 2, 3])
//!   b = np.zeros((3, 4))
//!   c = a @ b  # Uses Metal on macOS for large arrays
//!
//! Compiles to:
//!   const np = runtime.Lib.numpy;
//!   const a = np.array(allocator, &.{1, 2, 3});
//!   const b = np.zeros(allocator, &.{3, 4});
//!   const c = np.matmul(allocator, a, b);

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Core Types
// ============================================================================

pub const ndarray_mod = @import("ndarray.zig");
pub const dtype_mod = @import("dtype.zig");

/// N-dimensional array type
pub const ndarray = ndarray_mod.ndarray;

/// Data type enum
pub const DType = dtype_mod.DType;

/// Slice type for indexing
pub const Slice = ndarray_mod.Slice;

// ============================================================================
// Array Creation (np.array, np.zeros, np.ones, etc.)
// ============================================================================

pub const creation = @import("creation.zig");

/// Create array from data: np.array([1, 2, 3])
pub const array = creation.array;

/// Create 2D array: np.array([[1, 2], [3, 4]])
pub const array2D = creation.array2D;

/// Create array of zeros: np.zeros((3, 4))
pub const zeros = creation.zeros;

/// Create array of ones: np.ones((3, 4))
pub const ones = creation.ones;

/// Create uninitialized array: np.empty((3, 4))
pub const empty = creation.empty;

/// Create array filled with value: np.full((3, 4), 5.0)
pub const full = creation.full;

/// Create range array: np.arange(0, 10, 1)
pub const arange = creation.arange;

/// Create linearly spaced array: np.linspace(0, 1, 100)
pub const linspace = creation.linspace;

/// Create log-spaced array: np.logspace(0, 2, 3)
pub const logspace = creation.logspace;

/// Create identity matrix: np.eye(3)
pub const eye = creation.eye;

/// Create identity matrix: np.identity(3)
pub const identity = creation.identity;

/// Create diagonal matrix: np.diag([1, 2, 3])
pub const diag = creation.diag;

/// Create triangular matrix: np.tri(3, 4, k=0)
pub const tri = creation.tri;

/// Create zeros with same shape: np.zeros_like(arr)
pub const zeros_like = creation.zeros_like;

/// Create ones with same shape: np.ones_like(arr)
pub const ones_like = creation.ones_like;

/// Create empty with same shape: np.empty_like(arr)
pub const empty_like = creation.empty_like;

/// Create filled with same shape: np.full_like(arr, 5.0)
pub const full_like = creation.full_like;

// ============================================================================
// Array Operations (np.add, np.matmul, etc.) - Metal accelerated on macOS
// ============================================================================

pub const operations = @import("operations.zig");

/// Whether Metal GPU is available (comptime constant)
pub const use_metal = operations.use_metal;

/// Element-wise add: np.add(a, b) or a + b
pub const add = operations.add;

/// Element-wise subtract: np.subtract(a, b) or a - b
pub const subtract = operations.subtract;

/// Element-wise multiply: np.multiply(a, b) or a * b
pub const multiply = operations.multiply;

/// Element-wise divide: np.divide(a, b) or a / b
pub const divide = operations.divide;

/// Matrix multiply: np.matmul(a, b) or a @ b
pub const matmul = operations.matmul;

/// Dot product: np.dot(a, b)
pub const dot = operations.dot;

/// Scalar add: a + scalar
pub const addScalar = operations.addScalar;

/// Scalar multiply: a * scalar
pub const multiplyScalar = operations.multiplyScalar;

/// Scalar subtract: a - scalar
pub const subtractScalar = operations.subtractScalar;

/// Scalar divide: a / scalar
pub const divideScalar = operations.divideScalar;

/// Power: a ** n
pub const power = operations.power;

/// Negation: -a
pub const negative = operations.negative;

/// Absolute value: np.abs(a)
pub const abs = operations.abs;

/// Square root: np.sqrt(a)
pub const sqrt = operations.sqrt;

/// Exponential: np.exp(a)
pub const exp = operations.exp;

/// Natural log: np.log(a)
pub const log = operations.log;

/// Base-10 log: np.log10(a)
pub const log10 = operations.log10;

/// Sine: np.sin(a)
pub const sin = operations.sin;

/// Cosine: np.cos(a)
pub const cos = operations.cos;

/// Tangent: np.tan(a)
pub const tan = operations.tan;

// ============================================================================
// Reduction Operations (np.sum, np.mean, etc.)
// ============================================================================

pub const reduction = @import("reduction.zig");

/// Sum: np.sum(a) or np.sum(a, axis=0)
pub const sum = reduction.sum;

/// Mean: np.mean(a)
pub const mean = reduction.mean;

/// Standard deviation: np.std(a)
pub const std_dev = reduction.std_dev;

/// Variance: np.var(a)
pub const variance = reduction.variance;

/// Product: np.prod(a)
pub const prod = reduction.prod;

/// Maximum: np.max(a)
pub const max = reduction.max;

/// Minimum: np.min(a)
pub const min = reduction.min;

/// Index of max: np.argmax(a)
pub const argmax = reduction.argmax;

/// Index of min: np.argmin(a)
pub const argmin = reduction.argmin;

/// All true: np.all(a)
pub const all = reduction.all;

/// Any true: np.any(a)
pub const any = reduction.any;

/// Cumulative sum: np.cumsum(a)
pub const cumsum = reduction.cumsum;

/// Cumulative product: np.cumprod(a)
pub const cumprod = reduction.cumprod;

// ============================================================================
// Aliases for NumPy compatibility
// ============================================================================

/// Alias for max
pub const amax = max;

/// Alias for min
pub const amin = min;

// ============================================================================
// Constants
// ============================================================================

/// Mathematical constant pi
pub const pi: f64 = std.math.pi;

/// Mathematical constant e
pub const e: f64 = std.math.e;

/// Positive infinity
pub const inf: f64 = std.math.inf(f64);

/// Not a number
pub const nan: f64 = std.math.nan(f64);

// ============================================================================
// Module Info
// ============================================================================

/// Get numpy version string
pub fn version() []const u8 {
    return "1.0.0-metal0";
}

/// Check if Metal GPU acceleration is available
pub fn hasGPU() bool {
    return use_metal;
}

// ============================================================================
// Tests
// ============================================================================

test "numpy module exports" {
    const allocator = std.testing.allocator;

    // Test array creation
    var a = try array(allocator, &.{ 1.0, 2.0, 3.0 });
    defer a.deinit();

    // Test operations
    var b = try multiplyScalar(allocator, a, 2.0);
    defer b.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 2.0), b.get(&.{0}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), b.get(&.{1}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), b.get(&.{2}), 0.001);

    // Test reduction
    var s = try sum(allocator, a, null);
    defer s.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 6.0), s.data[0], 0.001);
}

test "metal detection" {
    // This is a comptime test - just verify the constant exists
    if (comptime use_metal) {
        // On macOS
        try std.testing.expect(true);
    } else {
        // On other platforms
        try std.testing.expect(true);
    }
}
