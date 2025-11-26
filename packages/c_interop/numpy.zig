/// NumPy-compatible array operations with PyObject integration
/// Uses direct BLAS calls for performance while maintaining Python compatibility
///
/// This module wraps BLAS operations in PyObject for runtime integration
/// while keeping computational kernels at C speed.

const std = @import("std");

// Import runtime for PyObject and NumpyArray support
// This assumes runtime package is available in the import path
const runtime = struct {
    pub usingnamespace @import("runtime/src/runtime.zig");
    pub const NumpyArray = @import("runtime/src/numpy_array.zig").NumpyArray;
};

// BLAS C interface - Direct extern declarations
// Note: This requires linking with a BLAS implementation (OpenBLAS, Apple Accelerate, etc.)
// We declare functions directly instead of @cImport to avoid header path issues

// BLAS Level 1: cblas_ddot - dot product
extern "c" fn cblas_ddot(N: c_int, X: [*c]const f64, incX: c_int, Y: [*c]const f64, incY: c_int) f64;

// BLAS Level 3: cblas_dgemm - matrix multiplication
extern "c" fn cblas_dgemm(
    Order: c_int,
    TransA: c_int,
    TransB: c_int,
    M: c_int,
    N: c_int,
    K: c_int,
    alpha: f64,
    A: [*c]const f64,
    lda: c_int,
    B: [*c]const f64,
    ldb: c_int,
    beta: f64,
    C: [*c]f64,
    ldc: c_int,
) void;

// BLAS constants
const CblasRowMajor: c_int = 101;
const CblasNoTrans: c_int = 111;

/// Create NumPy array from integer slice (Python: np.array([1,2,3]))
/// Converts i64 → f64 and wraps in PyObject
pub fn array(data: []const i64, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Convert i64 to f64
    const float_data = try allocator.alloc(f64, data.len);
    for (data, 0..) |val, i| {
        float_data[i] = @floatFromInt(val);
    }

    // Create NumpyArray from float data
    const np_array = try runtime.NumpyArray.fromSlice(allocator, float_data);
    allocator.free(float_data); // NumpyArray makes its own copy

    // Wrap in PyObject
    return try runtime.numpy_array.createPyObject(allocator, np_array);
}

/// Create array from float slice (Python: np.array([1.0, 2.0, 3.0]))
/// Wraps in PyObject
pub fn arrayFloat(data: []const f64, allocator: std.mem.Allocator) !*runtime.PyObject {
    const np_array = try runtime.NumpyArray.fromSlice(allocator, data);
    return try runtime.numpy_array.createPyObject(allocator, np_array);
}

/// Create array of zeros (Python: np.zeros(shape))
pub fn zeros(shape_spec: []const usize, allocator: std.mem.Allocator) !*runtime.PyObject {
    const np_array = try runtime.NumpyArray.zeros(allocator, shape_spec);
    return try runtime.numpy_array.createPyObject(allocator, np_array);
}

/// Create array of ones (Python: np.ones(shape))
pub fn ones(shape_spec: []const usize, allocator: std.mem.Allocator) !*runtime.PyObject {
    const np_array = try runtime.NumpyArray.ones(allocator, shape_spec);
    return try runtime.numpy_array.createPyObject(allocator, np_array);
}

/// Vector dot product using BLAS Level 1 (Python: np.dot(a, b))
/// Computes: a · b = sum(a[i] * b[i])
/// Returns: PyObject wrapping float result
pub fn dot(a_obj: *runtime.PyObject, b_obj: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    // Extract NumPy arrays from PyObjects
    const a_arr = try runtime.numpy_array.extractArray(a_obj);
    const b_arr = try runtime.numpy_array.extractArray(b_obj);

    std.debug.assert(a_arr.size == b_arr.size);

    // Use BLAS ddot: double precision dot product
    const result = cblas_ddot(
        @intCast(a_arr.size),  // N: number of elements
        a_arr.data.ptr,        // X: pointer to first vector
        1,                     // incX: stride for X
        b_arr.data.ptr,        // Y: pointer to second vector
        1                      // incY: stride for Y
    );

    // Wrap result in PyFloat
    return try runtime.PyFloat.create(allocator, result);
}

/// Sum all elements in array (Python: np.sum(arr))
/// Returns: PyObject wrapping float result
pub fn sum(arr_obj: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    const arr = try runtime.numpy_array.extractArray(arr_obj);

    var total: f64 = 0.0;
    for (arr.data) |val| {
        total += val;
    }

    return try runtime.PyFloat.create(allocator, total);
}

/// Calculate mean (average) of array elements (Python: np.mean(arr))
/// Returns: PyObject wrapping float result
pub fn mean(arr_obj: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
    const arr = try runtime.numpy_array.extractArray(arr_obj);

    if (arr.size == 0) {
        return try runtime.PyFloat.create(allocator, 0.0);
    }

    var total: f64 = 0.0;
    for (arr.data) |val| {
        total += val;
    }

    const avg = total / @as(f64, @floatFromInt(arr.size));
    return try runtime.PyFloat.create(allocator, avg);
}

/// Transpose matrix (in-place for square matrices, allocates for non-square)
/// For MVP, we'll just support square matrices in-place
/// rows: number of rows in original matrix
/// cols: number of columns in original matrix
pub fn transpose(matrix: []f64, rows: usize, cols: usize, allocator: std.mem.Allocator) ![]f64 {
    // Allocate result matrix with swapped dimensions
    const result = try allocator.alloc(f64, rows * cols);

    // Transpose: result[j][i] = matrix[i][j]
    // In row-major layout: result[j*rows + i] = matrix[i*cols + j]
    for (0..rows) |i| {
        for (0..cols) |j| {
            result[j * rows + i] = matrix[i * cols + j];
        }
    }

    return result;
}

/// Matrix-matrix multiplication using BLAS Level 3
/// Computes: C = alpha*A*B + beta*C
/// For basic matmul: C = A*B, we use alpha=1, beta=0
pub fn matmul(a: []const f64, b: []const f64, m: usize, n: usize, k: usize, allocator: std.mem.Allocator) ![]f64 {
    // A: m x k matrix
    // B: k x n matrix
    // C: m x n matrix (result)

    const result = try allocator.alloc(f64, m * n);
    @memset(result, 0.0);

    // Use BLAS dgemm: double precision general matrix multiply
    cblas_dgemm(
        CblasRowMajor,          // Row-major layout
        CblasNoTrans,           // Don't transpose A
        CblasNoTrans,           // Don't transpose B
        @intCast(m),            // M: rows of A
        @intCast(n),            // N: cols of B
        @intCast(k),            // K: cols of A, rows of B
        1.0,                    // alpha: scalar for A*B
        a.ptr,                  // A matrix
        @intCast(k),            // lda: leading dimension of A
        b.ptr,                  // B matrix
        @intCast(n),            // ldb: leading dimension of B
        0.0,                    // beta: scalar for C
        result.ptr,             // C matrix (result)
        @intCast(n)             // ldc: leading dimension of C
    );

    return result;
}

/// Get array length
pub fn len(arr: []const f64) usize {
    return arr.len;
}

test "array creation from integers" {
    const allocator = std.testing.allocator;

    const data = [_]i64{1, 2, 3, 4, 5};
    const arr_obj = try array(&data, allocator);
    defer {
        const arr = runtime.numpy_array.extractArray(arr_obj) catch unreachable;
        arr.deinit();
        allocator.destroy(arr_obj);
    }

    const arr = try runtime.numpy_array.extractArray(arr_obj);
    try std.testing.expectEqual(@as(usize, 5), arr.size);
    try std.testing.expectEqual(@as(f64, 1.0), arr.data[0]);
    try std.testing.expectEqual(@as(f64, 5.0), arr.data[4]);
}

test "dot product with PyObject" {
    const allocator = std.testing.allocator;

    const a_data = [_]f64{1.0, 2.0, 3.0};
    const b_data = [_]f64{4.0, 5.0, 6.0};

    const a_obj = try arrayFloat(&a_data, allocator);
    const b_obj = try arrayFloat(&b_data, allocator);
    defer {
        const a = runtime.numpy_array.extractArray(a_obj) catch unreachable;
        const b = runtime.numpy_array.extractArray(b_obj) catch unreachable;
        a.deinit();
        b.deinit();
        allocator.destroy(a_obj);
        allocator.destroy(b_obj);
    }

    const result_obj = try dot(a_obj, b_obj, allocator);
    defer allocator.destroy(result_obj);

    const result_float = @as(*runtime.PyFloat, @ptrCast(@alignCast(result_obj.data)));
    // Expected: 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
    try std.testing.expectEqual(@as(f64, 32.0), result_float.value);
}

test "sum with PyObject" {
    const allocator = std.testing.allocator;

    const arr_data = [_]f64{1.0, 2.0, 3.0, 4.0, 5.0};
    const arr_obj = try arrayFloat(&arr_data, allocator);
    defer {
        const arr = runtime.numpy_array.extractArray(arr_obj) catch unreachable;
        arr.deinit();
        allocator.destroy(arr_obj);
    }

    const result_obj = try sum(arr_obj, allocator);
    defer allocator.destroy(result_obj);

    const result_float = @as(*runtime.PyFloat, @ptrCast(@alignCast(result_obj.data)));
    // Expected: 1 + 2 + 3 + 4 + 5 = 15
    try std.testing.expectEqual(@as(f64, 15.0), result_float.value);
}

test "mean with PyObject" {
    const allocator = std.testing.allocator;

    const arr_data = [_]f64{1.0, 2.0, 3.0, 4.0, 5.0};
    const arr_obj = try arrayFloat(&arr_data, allocator);
    defer {
        const arr = runtime.numpy_array.extractArray(arr_obj) catch unreachable;
        arr.deinit();
        allocator.destroy(arr_obj);
    }

    const result_obj = try mean(arr_obj, allocator);
    defer allocator.destroy(result_obj);

    const result_float = @as(*runtime.PyFloat, @ptrCast(@alignCast(result_obj.data)));
    // Expected: 15 / 5 = 3.0
    try std.testing.expectEqual(@as(f64, 3.0), result_float.value);
}
