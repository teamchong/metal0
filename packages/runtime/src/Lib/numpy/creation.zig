//! NumPy Array Creation Functions
//!
//! Functions for creating ndarrays: array, zeros, ones, empty, full, arange, linspace, etc.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ndarray_mod = @import("ndarray.zig");
const ndarray = ndarray_mod.ndarray;
const DType = ndarray_mod.DType;

// ============================================================================
// Basic Creation
// ============================================================================

/// Create array from slice of f64 values
/// np.array([1, 2, 3])
pub fn array(allocator: Allocator, data: []const f64) !ndarray {
    const owned_data = try allocator.alloc(f64, data.len);
    @memcpy(owned_data, data);
    return ndarray.initWithData(allocator, owned_data, &.{data.len}, .float64);
}

/// Create array from 2D slice
/// np.array([[1, 2], [3, 4]])
pub fn array2D(allocator: Allocator, data: []const []const f64) !ndarray {
    if (data.len == 0) return error.EmptyArray;

    const rows = data.len;
    const cols = data[0].len;
    const total = rows * cols;

    const owned_data = try allocator.alloc(f64, total);

    // Copy data in row-major order
    for (data, 0..) |row, i| {
        if (row.len != cols) return error.JaggedArray;
        @memcpy(owned_data[i * cols .. (i + 1) * cols], row);
    }

    return ndarray.initWithData(allocator, owned_data, &.{ rows, cols }, .float64);
}

/// Create array filled with zeros
/// np.zeros((3, 4))
pub fn zeros(allocator: Allocator, shape: []const usize) !ndarray {
    var arr = try ndarray.init(allocator, shape, .float64);
    arr.fill(0.0);
    return arr;
}

/// Create array filled with ones
/// np.ones((3, 4))
pub fn ones(allocator: Allocator, shape: []const usize) !ndarray {
    var arr = try ndarray.init(allocator, shape, .float64);
    arr.fill(1.0);
    return arr;
}

/// Create uninitialized array (for performance when you'll fill it immediately)
/// np.empty((3, 4))
pub fn empty(allocator: Allocator, shape: []const usize) !ndarray {
    return ndarray.init(allocator, shape, .float64);
}

/// Create array filled with a specific value
/// np.full((3, 4), 5.0)
pub fn full(allocator: Allocator, shape: []const usize, value: f64) !ndarray {
    var arr = try ndarray.init(allocator, shape, .float64);
    arr.fill(value);
    return arr;
}

// ============================================================================
// Range Creation
// ============================================================================

/// Create array with evenly spaced values within a given interval
/// np.arange(0, 10, 1) -> [0, 1, 2, ..., 9]
pub fn arange(allocator: Allocator, start: f64, stop: f64, step: f64) !ndarray {
    if (step == 0) return error.ZeroStep;

    // Calculate number of elements
    const diff = stop - start;
    if ((step > 0 and diff < 0) or (step < 0 and diff > 0)) {
        // Empty range
        const empty_data = try allocator.alloc(f64, 0);
        return ndarray.initWithData(allocator, empty_data, &.{0}, .float64);
    }

    const n: usize = @intFromFloat(@ceil(@abs(diff / step)));
    const data = try allocator.alloc(f64, n);

    var val = start;
    for (0..n) |i| {
        data[i] = val;
        val += step;
    }

    return ndarray.initWithData(allocator, data, &.{n}, .float64);
}

/// Create array with evenly spaced values over a specified interval
/// np.linspace(0, 1, 5) -> [0, 0.25, 0.5, 0.75, 1.0]
pub fn linspace(allocator: Allocator, start: f64, stop: f64, num: usize) !ndarray {
    if (num == 0) {
        const empty_data = try allocator.alloc(f64, 0);
        return ndarray.initWithData(allocator, empty_data, &.{0}, .float64);
    }

    const data = try allocator.alloc(f64, num);

    if (num == 1) {
        data[0] = start;
    } else {
        const step = (stop - start) / @as(f64, @floatFromInt(num - 1));
        for (0..num) |i| {
            data[i] = start + @as(f64, @floatFromInt(i)) * step;
        }
    }

    return ndarray.initWithData(allocator, data, &.{num}, .float64);
}

/// Create array with values evenly spaced on a log scale
/// np.logspace(0, 2, 3) -> [1, 10, 100] (base 10)
pub fn logspace(allocator: Allocator, start: f64, stop: f64, num: usize, base: f64) !ndarray {
    var arr = try linspace(allocator, start, stop, num);

    // Apply base^x to each element
    for (0..arr.size) |i| {
        arr.data[i] = std.math.pow(f64, base, arr.data[i]);
    }

    return arr;
}

// ============================================================================
// Special Matrices
// ============================================================================

/// Create identity matrix
/// np.eye(3) -> [[1,0,0],[0,1,0],[0,0,1]]
pub fn eye(allocator: Allocator, n: usize) !ndarray {
    var arr = try zeros(allocator, &.{ n, n });

    // Set diagonal to 1
    for (0..n) |i| {
        arr.set(&.{ i, i }, 1.0);
    }

    return arr;
}

/// Create identity matrix (alias for eye)
/// np.identity(3)
pub fn identity(allocator: Allocator, n: usize) !ndarray {
    return eye(allocator, n);
}

/// Create a diagonal matrix or extract diagonal
/// np.diag([1, 2, 3]) -> [[1,0,0],[0,2,0],[0,0,3]]
pub fn diag(allocator: Allocator, v: []const f64) !ndarray {
    const n = v.len;
    var arr = try zeros(allocator, &.{ n, n });

    for (0..n) |i| {
        arr.set(&.{ i, i }, v[i]);
    }

    return arr;
}

/// Create a 2D array with ones on the diagonal and zeros elsewhere
/// np.tri(3, 4, k=0) -> lower triangular
pub fn tri(allocator: Allocator, n: usize, m: ?usize, k: isize) !ndarray {
    const cols = m orelse n;
    var arr = try zeros(allocator, &.{ n, cols });

    for (0..n) |i| {
        const signed_i: isize = @intCast(i);
        for (0..cols) |j| {
            const signed_j: isize = @intCast(j);
            if (signed_j <= signed_i + k) {
                arr.set(&.{ i, j }, 1.0);
            }
        }
    }

    return arr;
}

// ============================================================================
// Zeros/Ones Like
// ============================================================================

/// Create array of zeros with same shape as input
/// np.zeros_like(arr)
pub fn zeros_like(allocator: Allocator, arr: ndarray) !ndarray {
    return zeros(allocator, arr.shape);
}

/// Create array of ones with same shape as input
/// np.ones_like(arr)
pub fn ones_like(allocator: Allocator, arr: ndarray) !ndarray {
    return ones(allocator, arr.shape);
}

/// Create empty array with same shape as input
/// np.empty_like(arr)
pub fn empty_like(allocator: Allocator, arr: ndarray) !ndarray {
    return empty(allocator, arr.shape);
}

/// Create array filled with value, same shape as input
/// np.full_like(arr, 5.0)
pub fn full_like(allocator: Allocator, arr: ndarray, value: f64) !ndarray {
    return full(allocator, arr.shape, value);
}

// ============================================================================
// Tests
// ============================================================================

test "array creation" {
    const allocator = std.testing.allocator;

    var arr = try array(allocator, &.{ 1.0, 2.0, 3.0, 4.0, 5.0 });
    defer arr.deinit();

    try std.testing.expectEqual(@as(usize, 5), arr.size);
    try std.testing.expectEqual(@as(f64, 1.0), arr.get(&.{0}));
    try std.testing.expectEqual(@as(f64, 5.0), arr.get(&.{4}));
}

test "zeros" {
    const allocator = std.testing.allocator;

    var arr = try zeros(allocator, &.{ 2, 3 });
    defer arr.deinit();

    try std.testing.expectEqual(@as(usize, 6), arr.size);
    for (0..2) |i| {
        for (0..3) |j| {
            try std.testing.expectEqual(@as(f64, 0.0), arr.get(&.{ i, j }));
        }
    }
}

test "ones" {
    const allocator = std.testing.allocator;

    var arr = try ones(allocator, &.{4});
    defer arr.deinit();

    for (0..4) |i| {
        try std.testing.expectEqual(@as(f64, 1.0), arr.get(&.{i}));
    }
}

test "arange" {
    const allocator = std.testing.allocator;

    var arr = try arange(allocator, 0, 5, 1);
    defer arr.deinit();

    try std.testing.expectEqual(@as(usize, 5), arr.size);
    try std.testing.expectEqual(@as(f64, 0.0), arr.get(&.{0}));
    try std.testing.expectEqual(@as(f64, 4.0), arr.get(&.{4}));
}

test "linspace" {
    const allocator = std.testing.allocator;

    var arr = try linspace(allocator, 0, 1, 5);
    defer arr.deinit();

    try std.testing.expectEqual(@as(usize, 5), arr.size);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), arr.get(&.{0}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), arr.get(&.{1}), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), arr.get(&.{4}), 0.001);
}

test "eye" {
    const allocator = std.testing.allocator;

    var arr = try eye(allocator, 3);
    defer arr.deinit();

    try std.testing.expectEqual(@as(f64, 1.0), arr.get(&.{ 0, 0 }));
    try std.testing.expectEqual(@as(f64, 1.0), arr.get(&.{ 1, 1 }));
    try std.testing.expectEqual(@as(f64, 1.0), arr.get(&.{ 2, 2 }));
    try std.testing.expectEqual(@as(f64, 0.0), arr.get(&.{ 0, 1 }));
}

test "diag" {
    const allocator = std.testing.allocator;

    var arr = try diag(allocator, &.{ 1.0, 2.0, 3.0 });
    defer arr.deinit();

    try std.testing.expectEqual(@as(f64, 1.0), arr.get(&.{ 0, 0 }));
    try std.testing.expectEqual(@as(f64, 2.0), arr.get(&.{ 1, 1 }));
    try std.testing.expectEqual(@as(f64, 3.0), arr.get(&.{ 2, 2 }));
    try std.testing.expectEqual(@as(f64, 0.0), arr.get(&.{ 0, 1 }));
}
