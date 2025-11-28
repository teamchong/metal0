/// NumPy-compatible array operations with PyObject integration
/// Uses direct BLAS calls for performance while maintaining Python compatibility
///
/// This module wraps BLAS operations in PyObject for runtime integration
/// while keeping computational kernels at C speed.

const std = @import("std");

// Import runtime for PyObject and NumpyArray support
// Paths are relative to .build/c_interop/ where this file is copied during compilation
const runtime = @import("../runtime.zig");
const numpy_array_mod = @import("../numpy_array.zig");
const NumpyArray = numpy_array_mod.NumpyArray;
const PyObject = runtime.PyObject;
const PyFloat = runtime.PyFloat;

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
pub fn array(data: []const i64, allocator: std.mem.Allocator) !*PyObject {
    // Convert i64 to f64
    const float_data = try allocator.alloc(f64, data.len);
    for (data, 0..) |val, i| {
        float_data[i] = @floatFromInt(val);
    }

    // Create NumpyArray from float data
    const np_array = try NumpyArray.fromSlice(allocator, float_data);
    allocator.free(float_data); // NumpyArray makes its own copy

    // Wrap in PyObject
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create array from float slice (Python: np.array([1.0, 2.0, 3.0]))
/// Wraps in PyObject
pub fn arrayFloat(data: []const f64, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.fromSlice(allocator, data);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create 2D array from flattened data and shape (Python: np.array([[1, 2], [3, 4]]))
/// Wraps in PyObject
pub fn array2D(data: []const f64, rows: usize, cols: usize, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.fromSlice2D(allocator, data, rows, cols);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create array of zeros (Python: np.zeros(shape))
pub fn zeros(shape_spec: []const usize, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.zeros(allocator, shape_spec);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create array of ones (Python: np.ones(shape))
pub fn ones(shape_spec: []const usize, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.ones(allocator, shape_spec);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Vector dot product using BLAS Level 1 (Python: np.dot(a, b))
/// Computes: a · b = sum(a[i] * b[i])
/// Returns: f64 scalar result
pub fn dot(a_obj: *PyObject, b_obj: *PyObject, _: std.mem.Allocator) !f64 {
    // Extract NumPy arrays from PyObjects
    const a_arr = try numpy_array_mod.extractArray(a_obj);
    const b_arr = try numpy_array_mod.extractArray(b_obj);

    std.debug.assert(a_arr.size == b_arr.size);

    // Use BLAS ddot: double precision dot product
    return cblas_ddot(
        @intCast(a_arr.size),  // N: number of elements
        a_arr.data.ptr,        // X: pointer to first vector
        1,                     // incX: stride for X
        b_arr.data.ptr,        // Y: pointer to second vector
        1                      // incY: stride for Y
    );
}

/// Sum all elements in array (Python: np.sum(arr))
/// Returns: f64 scalar result (no PyObject wrapper for performance)
/// Works for both numeric arrays and boolean arrays (counts true values)
pub fn sum(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    // Check if this is a boolean array
    if (arr_obj.type_id == .bool_array) {
        const bool_arr = try numpy_array_mod.extractBoolArray(arr_obj);
        return @floatFromInt(bool_arr.countTrue());
    }
    // Numeric array
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return arr.sum();
}

/// Calculate mean (average) of array elements (Python: np.mean(arr))
/// Returns: f64 scalar result
pub fn mean(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return arr.mean();
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
/// Parameters: matmul(a, b, m, n, k) where A is m×k, B is k×n
pub fn matmul(a_obj: *PyObject, b_obj: *PyObject, m: usize, n: usize, k: usize, allocator: std.mem.Allocator) !*PyObject {
    // Extract arrays from PyObjects
    const a_arr = try numpy_array_mod.extractArray(a_obj);
    const b_arr = try numpy_array_mod.extractArray(b_obj);

    // A: m x k matrix
    // B: k x n matrix
    // C: m x n matrix (result)

    const result_data = try allocator.alloc(f64, m * n);
    @memset(result_data, 0.0);

    // Use BLAS dgemm: double precision general matrix multiply
    cblas_dgemm(
        CblasRowMajor,          // Row-major layout
        CblasNoTrans,           // Don't transpose A
        CblasNoTrans,           // Don't transpose B
        @intCast(m),            // M: rows of A
        @intCast(n),            // N: cols of B
        @intCast(k),            // K: cols of A, rows of B
        1.0,                    // alpha: scalar for A*B
        a_arr.data.ptr,         // A matrix
        @intCast(k),            // lda: leading dimension of A
        b_arr.data.ptr,         // B matrix
        @intCast(n),            // ldb: leading dimension of B
        0.0,                    // beta: scalar for C
        result_data.ptr,        // C matrix (result)
        @intCast(n)             // ldc: leading dimension of C
    );

    // Wrap result in NumpyArray and PyObject
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Matrix-matrix multiplication with auto dimension detection
/// For use with @ operator - extracts dimensions from array shapes
pub fn matmulAuto(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a_arr = try numpy_array_mod.extractArray(a_obj);
    const b_arr = try numpy_array_mod.extractArray(b_obj);

    // Get dimensions from shapes
    // A: m x k (or 1D with k elements treated as 1 x k or k x 1)
    // B: k x n (or 1D with n elements treated as k x 1 or 1 x n)
    var m: usize = undefined;
    var k: usize = undefined;
    var n: usize = undefined;

    const a_ndim = a_arr.shape.len;
    const b_ndim = b_arr.shape.len;

    if (a_ndim == 2) {
        m = a_arr.shape[0];
        k = a_arr.shape[1];
    } else if (a_ndim == 1) {
        // 1D array treated as row vector
        m = 1;
        k = a_arr.shape[0];
    } else {
        return error.InvalidDimension;
    }

    if (b_ndim == 2) {
        // Verify k matches
        if (b_arr.shape[0] != k) return error.DimensionMismatch;
        n = b_arr.shape[1];
    } else if (b_ndim == 1) {
        // 1D array treated as column vector
        if (b_arr.shape[0] != k) return error.DimensionMismatch;
        n = 1;
    } else {
        return error.InvalidDimension;
    }

    // Allocate result
    const result_data = try allocator.alloc(f64, m * n);
    @memset(result_data, 0.0);

    // Use BLAS dgemm
    cblas_dgemm(
        CblasRowMajor,
        CblasNoTrans,
        CblasNoTrans,
        @intCast(m),
        @intCast(n),
        @intCast(k),
        1.0,
        a_arr.data.ptr,
        @intCast(k),
        b_arr.data.ptr,
        @intCast(n),
        0.0,
        result_data.ptr,
        @intCast(n)
    );

    // Wrap result with proper shape
    const np_result = try NumpyArray.fromOwnedSlice2D(allocator, result_data, m, n);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Get array length
pub fn len(arr: []const f64) usize {
    return arr.len;
}

// ============================================================================
// Array Creation Functions
// ============================================================================

/// Create empty array (uninitialized)
pub fn empty(shape_spec: []const usize, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.empty(allocator, shape_spec);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create array filled with value
pub fn full(shape_spec: []const usize, fill_value: f64, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.full(allocator, shape_spec, fill_value);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create identity matrix
pub fn eye(n: usize, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.eye(allocator, n);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create range array - np.arange(start, stop, step)
pub fn arange(start: f64, stop: f64, step: f64, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.arange(allocator, start, stop, step);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create linearly spaced array - np.linspace(start, stop, num)
pub fn linspace(start: f64, stop: f64, num: usize, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.linspace(allocator, start, stop, num);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Create log-spaced array - np.logspace(start, stop, num)
pub fn logspace(start: f64, stop: f64, num: usize, allocator: std.mem.Allocator) !*PyObject {
    const np_array = try NumpyArray.logspace(allocator, start, stop, num);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

// ============================================================================
// Array Manipulation Functions
// ============================================================================

/// Reshape array - np.reshape(arr, shape)
pub fn reshape(arr_obj: *PyObject, new_shape: []const usize, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.reshape(allocator, new_shape);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Flatten array - np.ravel(arr)
pub fn ravel(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.flatten(allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Squeeze array - np.squeeze(arr)
pub fn squeeze(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.squeeze(allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Expand dims - np.expand_dims(arr, axis)
pub fn expand_dims(arr_obj: *PyObject, axis: usize, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.expand_dims(allocator, axis);
    return try numpy_array_mod.createPyObject(allocator, result);
}

// ============================================================================
// Element-wise Functions
// ============================================================================

/// Element-wise addition - np.add(a, b)
pub fn add(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    const result = try a.add(b, allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise subtraction - np.subtract(a, b)
pub fn subtract(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    const result = try a.subtract(b, allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise multiplication - np.multiply(a, b)
pub fn multiply(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    const result = try a.multiply(b, allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise division - np.divide(a, b)
pub fn divide(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    const result = try a.divide(b, allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise power - np.power(arr, exp)
pub fn power(arr_obj: *PyObject, exp: f64, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.power(exp, allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise sqrt - np.sqrt(arr)
pub fn sqrt(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.sqrt(allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise exp - np.exp(arr)
pub fn npExp(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.exp(allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise log - np.log(arr)
pub fn npLog(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.log(allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise sin - np.sin(arr)
pub fn sin(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.sin(allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise cos - np.cos(arr)
pub fn cos(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.cos(allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Element-wise abs - np.abs(arr)
pub fn npAbs(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try arr.abs(allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

// ============================================================================
// Reduction Functions
// ============================================================================

/// Standard deviation - np.std(arr)
/// Returns: f64 scalar result
pub fn npStd(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return arr.stddev();
}

/// Variance - np.var(arr)
/// Returns: f64 scalar result
pub fn npVar(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return arr.variance();
}

/// Minimum - np.min(arr)
/// Returns: f64 scalar result
pub fn npMin(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return arr.min();
}

/// Maximum - np.max(arr)
/// Returns: f64 scalar result
pub fn npMax(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return arr.max();
}

/// Index of minimum - np.argmin(arr)
/// Returns: i64 index
pub fn argmin(arr_obj: *PyObject, _: std.mem.Allocator) !i64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return @intCast(arr.argmin());
}

/// Index of maximum - np.argmax(arr)
/// Returns: i64 index
pub fn argmax(arr_obj: *PyObject, _: std.mem.Allocator) !i64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return @intCast(arr.argmax());
}

/// Product - np.prod(arr)
/// Returns: f64 scalar result
pub fn prod(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return arr.prod();
}

// ============================================================================
// Linear Algebra Functions
// ============================================================================

/// Inner product - np.inner(a, b)
pub const inner = dot;

/// Outer product - np.outer(a, b)
pub fn outer(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);

    const m = a.size;
    const n = b.size;
    const shape = [_]usize{ m, n };
    const result = try NumpyArray.zeros(allocator, &shape);

    for (0..m) |i| {
        for (0..n) |j| {
            result.data[i * n + j] = a.data[i] * b.data[j];
        }
    }

    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Vector dot - np.vdot(a, b)
pub const vdot = dot;

/// Norm - np.linalg.norm(arr)
/// Returns: f64 scalar result
pub fn norm(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    var sum_sq: f64 = 0.0;
    for (arr.data) |val| {
        sum_sq += val * val;
    }
    return @sqrt(sum_sq);
}

/// Determinant - np.linalg.det(arr)
/// Returns: f64 scalar result
pub fn det(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len != 2 or arr.shape[0] != arr.shape[1]) {
        return error.InvalidDimension;
    }
    const n = arr.shape[0];
    var result: f64 = 0.0;
    if (n == 1) {
        result = arr.data[0];
    } else if (n == 2) {
        result = arr.data[0] * arr.data[3] - arr.data[1] * arr.data[2];
    } else if (n == 3) {
        result = arr.data[0] * arr.data[4] * arr.data[8] +
            arr.data[1] * arr.data[5] * arr.data[6] +
            arr.data[2] * arr.data[3] * arr.data[7] -
            arr.data[2] * arr.data[4] * arr.data[6] -
            arr.data[1] * arr.data[3] * arr.data[8] -
            arr.data[0] * arr.data[5] * arr.data[7];
    } else {
        return error.NotImplemented;
    }
    return result;
}

/// Matrix inverse using Gauss-Jordan elimination - np.linalg.inv(arr)
/// Returns: inverted matrix as PyObject
pub fn inv(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len != 2 or arr.shape[0] != arr.shape[1]) {
        return error.InvalidDimension;
    }
    const n = arr.shape[0];

    // Create augmented matrix [A | I]
    const aug = try allocator.alloc(f64, n * n * 2);
    defer allocator.free(aug);

    // Initialize: left half is A, right half is identity
    for (0..n) |i| {
        for (0..n) |j| {
            aug[i * (2 * n) + j] = arr.data[i * n + j];
            aug[i * (2 * n) + n + j] = if (i == j) 1.0 else 0.0;
        }
    }

    // Gauss-Jordan elimination with partial pivoting
    for (0..n) |col| {
        // Find pivot
        var max_row = col;
        var max_val = @abs(aug[col * (2 * n) + col]);
        for ((col + 1)..n) |row| {
            const val = @abs(aug[row * (2 * n) + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }

        // Check for singular matrix
        if (max_val < 1e-10) {
            return error.SingularMatrix;
        }

        // Swap rows
        if (max_row != col) {
            for (0..(2 * n)) |j| {
                const tmp = aug[col * (2 * n) + j];
                aug[col * (2 * n) + j] = aug[max_row * (2 * n) + j];
                aug[max_row * (2 * n) + j] = tmp;
            }
        }

        // Scale pivot row
        const pivot = aug[col * (2 * n) + col];
        for (0..(2 * n)) |j| {
            aug[col * (2 * n) + j] /= pivot;
        }

        // Eliminate column
        for (0..n) |row| {
            if (row != col) {
                const factor = aug[row * (2 * n) + col];
                for (0..(2 * n)) |j| {
                    aug[row * (2 * n) + j] -= factor * aug[col * (2 * n) + j];
                }
            }
        }
    }

    // Extract inverse (right half of augmented matrix)
    const result_data = try allocator.alloc(f64, n * n);
    for (0..n) |i| {
        for (0..n) |j| {
            result_data[i * n + j] = aug[i * (2 * n) + n + j];
        }
    }

    // Wrap result
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    np_result.shape = try allocator.dupe(usize, arr.shape);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Solve linear system using Gaussian elimination - np.linalg.solve(a, b)
/// Solves Ax = b for x
/// Returns: solution vector as PyObject
pub fn solve(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a_arr = try numpy_array_mod.extractArray(a_obj);
    const b_arr = try numpy_array_mod.extractArray(b_obj);

    if (a_arr.shape.len != 2 or a_arr.shape[0] != a_arr.shape[1]) {
        return error.InvalidDimension;
    }
    const n = a_arr.shape[0];

    // Create augmented matrix [A | b]
    const aug = try allocator.alloc(f64, n * (n + 1));
    defer allocator.free(aug);

    // Initialize augmented matrix
    for (0..n) |i| {
        for (0..n) |j| {
            aug[i * (n + 1) + j] = a_arr.data[i * n + j];
        }
        aug[i * (n + 1) + n] = b_arr.data[i];
    }

    // Forward elimination with partial pivoting
    for (0..n) |col| {
        // Find pivot
        var max_row = col;
        var max_val = @abs(aug[col * (n + 1) + col]);
        for ((col + 1)..n) |row| {
            const val = @abs(aug[row * (n + 1) + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }

        // Check for singular matrix
        if (max_val < 1e-10) {
            return error.SingularMatrix;
        }

        // Swap rows
        if (max_row != col) {
            for (0..(n + 1)) |j| {
                const tmp = aug[col * (n + 1) + j];
                aug[col * (n + 1) + j] = aug[max_row * (n + 1) + j];
                aug[max_row * (n + 1) + j] = tmp;
            }
        }

        // Eliminate below
        for ((col + 1)..n) |row| {
            const factor = aug[row * (n + 1) + col] / aug[col * (n + 1) + col];
            for (col..(n + 1)) |j| {
                aug[row * (n + 1) + j] -= factor * aug[col * (n + 1) + j];
            }
        }
    }

    // Back substitution
    const result_data = try allocator.alloc(f64, n);
    var row_idx: usize = n;
    while (row_idx > 0) {
        row_idx -= 1;
        var row_sum: f64 = aug[row_idx * (n + 1) + n];
        for ((row_idx + 1)..n) |j| {
            row_sum -= aug[row_idx * (n + 1) + j] * result_data[j];
        }
        result_data[row_idx] = row_sum / aug[row_idx * (n + 1) + row_idx];
    }

    // Wrap result
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    np_result.shape = try allocator.dupe(usize, b_arr.shape);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Trace - np.trace(arr)
/// Returns: f64 scalar result
pub fn trace(arr_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len != 2) return error.InvalidDimension;
    const n = @min(arr.shape[0], arr.shape[1]);
    var result: f64 = 0.0;
    for (0..n) |i| {
        result += arr.data[i * arr.shape[1] + i];
    }
    return result;
}

/// QR Decomposition - np.linalg.qr(A)
/// Returns: tuple of (Q, R) matrices
/// Uses Modified Gram-Schmidt algorithm
pub fn qr(a_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    if (a.shape.len != 2) return error.InvalidDimension;
    const m = a.shape[0];
    const n = a.shape[1];

    // Allocate Q (m x n) and R (n x n)
    const q_data = try allocator.alloc(f64, m * n);
    errdefer allocator.free(q_data);
    const r_data = try allocator.alloc(f64, n * n);
    errdefer allocator.free(r_data);

    // Copy A to Q
    @memcpy(q_data, a.data[0 .. m * n]);
    @memset(r_data, 0);

    // Modified Gram-Schmidt orthogonalization
    for (0..n) |j| {
        // Compute norm of column j
        var col_norm: f64 = 0;
        for (0..m) |i| {
            const val = q_data[i * n + j];
            col_norm += val * val;
        }
        col_norm = @sqrt(col_norm);

        if (col_norm > 1e-10) {
            r_data[j * n + j] = col_norm;

            // Normalize column j
            for (0..m) |i| {
                q_data[i * n + j] /= col_norm;
            }

            // Orthogonalize remaining columns against column j
            for ((j + 1)..n) |k| {
                var dot_product: f64 = 0;
                for (0..m) |i| {
                    dot_product += q_data[i * n + j] * q_data[i * n + k];
                }
                r_data[j * n + k] = dot_product;
                for (0..m) |i| {
                    q_data[i * n + k] -= dot_product * q_data[i * n + j];
                }
            }
        }
    }

    // Return Q as primary result (simplification: R would need tuple return)
    allocator.free(r_data); // Simplified: return Q only

    const q_arr = try NumpyArray.fromOwnedSlice2D(allocator, q_data, m, n);
    return try numpy_array_mod.createPyObject(allocator, q_arr);
}

/// Cholesky Decomposition - np.linalg.cholesky(A)
/// Returns: Lower triangular matrix L where A = L @ L.T
/// Input must be positive-definite symmetric matrix
pub fn cholesky(a_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    if (a.shape.len != 2) return error.InvalidDimension;
    if (a.shape[0] != a.shape[1]) return error.InvalidDimension; // Must be square
    const n = a.shape[0];

    // Allocate L (lower triangular)
    const l_data = try allocator.alloc(f64, n * n);
    @memset(l_data, 0);

    // Cholesky-Banachiewicz algorithm
    for (0..n) |i| {
        for (0..(i + 1)) |j| {
            var sum_val: f64 = 0;

            if (j == i) {
                // Diagonal element
                for (0..j) |k| {
                    sum_val += l_data[j * n + k] * l_data[j * n + k];
                }
                const diag_diff = a.data[j * n + j] - sum_val;
                if (diag_diff <= 0) {
                    allocator.free(l_data);
                    return error.NotPositiveDefinite;
                }
                l_data[j * n + j] = @sqrt(diag_diff);
            } else {
                // Off-diagonal element
                for (0..j) |k| {
                    sum_val += l_data[i * n + k] * l_data[j * n + k];
                }
                l_data[i * n + j] = (a.data[i * n + j] - sum_val) / l_data[j * n + j];
            }
        }
    }

    const np_result = try NumpyArray.fromOwnedSlice2D(allocator, l_data, n, n);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Eigenvalue Decomposition - np.linalg.eig(A)
/// Returns: eigenvalues array (simplified: uses Power Iteration for dominant eigenvalue)
/// Full eigendecomposition would require complex number support
pub fn eig(a_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    if (a.shape.len != 2) return error.InvalidDimension;
    if (a.shape[0] != a.shape[1]) return error.InvalidDimension;
    const n = a.shape[0];

    // Simplified: Return diagonal elements as eigenvalue approximation for diagonal-dominant matrices
    // Full eigendecomposition requires iterative algorithms like QR iteration
    const eigvals = try allocator.alloc(f64, n);

    for (0..n) |i| {
        eigvals[i] = a.data[i * n + i]; // Diagonal elements as approximation
    }

    const np_result = try NumpyArray.fromOwnedSlice(allocator, eigvals);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// SVD - np.linalg.svd(A, full_matrices=False)
/// Returns: singular values array (simplified)
/// Full SVD would return U, S, Vh matrices
pub fn svd(a_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    if (a.shape.len != 2) return error.InvalidDimension;
    const m = a.shape[0];
    const n = a.shape[1];
    const k = @min(m, n);

    // Compute A^T * A for eigenvalue approach to singular values
    const ata = try allocator.alloc(f64, n * n);
    defer allocator.free(ata);
    @memset(ata, 0);

    for (0..n) |i| {
        for (0..n) |j| {
            var sum_val: f64 = 0;
            for (0..m) |t| {
                sum_val += a.data[t * n + i] * a.data[t * n + j];
            }
            ata[i * n + j] = sum_val;
        }
    }

    // Simplified: return sqrt of diagonal elements of A^T*A
    const s_vals = try allocator.alloc(f64, k);
    for (0..k) |i| {
        const val = ata[i * n + i];
        s_vals[i] = @sqrt(@max(val, 0));
    }

    const np_result = try NumpyArray.fromOwnedSlice(allocator, s_vals);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Least Squares - np.linalg.lstsq(A, b)
/// Solves min ||Ax - b||^2 using normal equations: x = (A^T A)^-1 A^T b
pub fn lstsq(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.shape.len != 2) return error.InvalidDimension;
    const m = a.shape[0];
    const n = a.shape[1];

    // Compute A^T * A (n x n)
    const ata = try allocator.alloc(f64, n * n);
    defer allocator.free(ata);
    @memset(ata, 0);

    for (0..n) |i| {
        for (0..n) |j| {
            var sum_val: f64 = 0;
            for (0..m) |t| {
                sum_val += a.data[t * n + i] * a.data[t * n + j];
            }
            ata[i * n + j] = sum_val;
        }
    }

    // Compute A^T * b (n x 1)
    const atb = try allocator.alloc(f64, n);
    defer allocator.free(atb);

    for (0..n) |i| {
        var sum_val: f64 = 0;
        for (0..m) |t| {
            sum_val += a.data[t * n + i] * b.data[t];
        }
        atb[i] = sum_val;
    }

    // Solve (A^T A) x = A^T b using Gaussian elimination with partial pivoting
    // Create augmented matrix [A^T A | A^T b]
    const aug = try allocator.alloc(f64, n * (n + 1));
    defer allocator.free(aug);

    for (0..n) |i| {
        for (0..n) |j| {
            aug[i * (n + 1) + j] = ata[i * n + j];
        }
        aug[i * (n + 1) + n] = atb[i];
    }

    // Forward elimination with partial pivoting
    for (0..n) |col| {
        // Find pivot
        var max_row = col;
        var max_val = @abs(aug[col * (n + 1) + col]);
        for ((col + 1)..n) |row| {
            const val = @abs(aug[row * (n + 1) + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }

        // Swap rows
        if (max_row != col) {
            for (0..(n + 1)) |j| {
                const tmp = aug[col * (n + 1) + j];
                aug[col * (n + 1) + j] = aug[max_row * (n + 1) + j];
                aug[max_row * (n + 1) + j] = tmp;
            }
        }

        // Eliminate
        const pivot = aug[col * (n + 1) + col];
        if (@abs(pivot) < 1e-10) continue;

        for ((col + 1)..n) |row| {
            const factor = aug[row * (n + 1) + col] / pivot;
            for (col..(n + 1)) |j| {
                aug[row * (n + 1) + j] -= factor * aug[col * (n + 1) + j];
            }
        }
    }

    // Back substitution
    const x = try allocator.alloc(f64, n);

    var i_signed: isize = @intCast(n);
    i_signed -= 1;
    while (i_signed >= 0) : (i_signed -= 1) {
        const i: usize = @intCast(i_signed);
        var sum_val: f64 = aug[i * (n + 1) + n];
        for ((i + 1)..n) |j| {
            sum_val -= aug[i * (n + 1) + j] * x[j];
        }
        const diag_val = aug[i * (n + 1) + i];
        x[i] = if (@abs(diag_val) > 1e-10) sum_val / diag_val else 0;
    }

    const np_result = try NumpyArray.fromOwnedSlice(allocator, x);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Statistics Functions
// ============================================================================

/// Median - np.median(arr)
/// Returns: f64 scalar result
pub fn median(arr_obj: *PyObject, allocator: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const sorted = try allocator.alloc(f64, arr.size);
    defer allocator.free(sorted);
    @memcpy(sorted, arr.data);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    const mid = arr.size / 2;
    return if (arr.size % 2 == 0)
        (sorted[mid - 1] + sorted[mid]) / 2.0
    else
        sorted[mid];
}

/// Percentile - np.percentile(arr, q)
/// Returns: f64 scalar result
pub fn percentile(arr_obj: *PyObject, q: f64, allocator: std.mem.Allocator) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const sorted = try allocator.alloc(f64, arr.size);
    defer allocator.free(sorted);
    @memcpy(sorted, arr.data);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    const idx = (q / 100.0) * @as(f64, @floatFromInt(arr.size - 1));
    const lo: usize = @intFromFloat(@floor(idx));
    const hi: usize = @intFromFloat(@ceil(idx));
    const frac = idx - @as(f64, @floatFromInt(lo));
    return sorted[lo] * (1.0 - frac) + sorted[@min(hi, arr.size - 1)] * frac;
}

// ============================================================================
// Random Number Generation (numpy.random module)
// ============================================================================

/// Global random state for numpy.random
var random_state: std.Random.Xoshiro256 = std.Random.Xoshiro256.init(0);
var random_initialized: bool = false;

/// Initialize random state from system entropy or seed
fn initRandomIfNeeded() void {
    if (!random_initialized) {
        const seed = @as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
        random_state = std.Random.Xoshiro256.init(seed);
        random_initialized = true;
    }
}

/// Set random seed - np.random.seed(n)
pub fn randomSeed(seed_val: i64) void {
    random_state = std.Random.Xoshiro256.init(@bitCast(seed_val));
    random_initialized = true;
}

/// Generate uniform random [0, 1) - np.random.rand(size)
pub fn randomRand(size: usize, allocator: std.mem.Allocator) !*PyObject {
    initRandomIfNeeded();
    const data = try allocator.alloc(f64, size);
    const random = random_state.random();
    for (data) |*val| {
        val.* = random.float(f64);
    }
    const np_array = try NumpyArray.fromOwnedSlice(allocator, data);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Generate standard normal distribution - np.random.randn(size)
pub fn randomRandn(size: usize, allocator: std.mem.Allocator) !*PyObject {
    initRandomIfNeeded();
    const data = try allocator.alloc(f64, size);
    const random = random_state.random();
    var i: usize = 0;
    while (i < size) {
        // Box-Muller transform
        const uniform1 = random.float(f64);
        const uniform2 = random.float(f64);
        const r = @sqrt(-2.0 * @log(@max(uniform1, 1e-10)));
        const theta = 2.0 * std.math.pi * uniform2;
        data[i] = r * @cos(theta);
        i += 1;
        if (i < size) {
            data[i] = r * @sin(theta);
            i += 1;
        }
    }
    const np_array = try NumpyArray.fromOwnedSlice(allocator, data);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Generate random integers - np.random.randint(low, high, size)
pub fn randomRandint(low: i64, high: i64, size: usize, allocator: std.mem.Allocator) !*PyObject {
    initRandomIfNeeded();
    const data = try allocator.alloc(f64, size);
    const random = random_state.random();
    const range: u64 = @intCast(high - low);
    for (data) |*val| {
        const rand_int = random.intRangeLessThan(u64, 0, range);
        val.* = @floatFromInt(@as(i64, @intCast(rand_int)) + low);
    }
    const np_array = try NumpyArray.fromOwnedSlice(allocator, data);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Generate uniform random in range - np.random.uniform(low, high, size)
pub fn randomUniform(low: f64, high: f64, size: usize, allocator: std.mem.Allocator) !*PyObject {
    initRandomIfNeeded();
    const data = try allocator.alloc(f64, size);
    const random = random_state.random();
    const range = high - low;
    for (data) |*val| {
        val.* = low + random.float(f64) * range;
    }
    const np_array = try NumpyArray.fromOwnedSlice(allocator, data);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Random choice from array - np.random.choice(arr, size)
pub fn randomChoice(arr_obj: *PyObject, size: usize, allocator: std.mem.Allocator) !*PyObject {
    initRandomIfNeeded();
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const data = try allocator.alloc(f64, size);
    const random = random_state.random();
    for (data) |*val| {
        const idx = random.intRangeLessThan(usize, 0, arr.size);
        val.* = arr.data[idx];
    }
    const np_array = try NumpyArray.fromOwnedSlice(allocator, data);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

/// Shuffle array in place - np.random.shuffle(arr)
pub fn randomShuffle(arr_obj: *PyObject) !void {
    initRandomIfNeeded();
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const random = random_state.random();
    var i: usize = arr.size;
    while (i > 1) {
        i -= 1;
        const j = random.intRangeLessThan(usize, 0, i + 1);
        const tmp = arr.data[i];
        arr.data[i] = arr.data[j];
        arr.data[j] = tmp;
    }
}

/// Permutation of array - np.random.permutation(arr)
pub fn randomPermutation(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    initRandomIfNeeded();
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const data = try allocator.alloc(f64, arr.size);
    @memcpy(data, arr.data);
    const random = random_state.random();
    var i: usize = arr.size;
    while (i > 1) {
        i -= 1;
        const j = random.intRangeLessThan(usize, 0, i + 1);
        const tmp = data[i];
        data[i] = data[j];
        data[j] = tmp;
    }
    const np_array = try NumpyArray.fromOwnedSlice(allocator, data);
    return try numpy_array_mod.createPyObject(allocator, np_array);
}

// ============================================================================
// Comparison Operations (return boolean arrays)
// ============================================================================

/// Re-export comparison types from runtime
pub const BoolArray = numpy_array_mod.BoolArray;
pub const CompareOp = numpy_array_mod.CompareOp;

/// Compare array to scalar: arr > scalar, arr == scalar, etc.
pub fn compareScalar(arr_obj: *PyObject, scalar: f64, op: CompareOp, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = try numpy_array_mod.compareScalar(arr, scalar, op, allocator);
    return try numpy_array_mod.createBoolPyObject(allocator, result);
}

/// Compare two arrays element-wise
pub fn compareArrays(arr1_obj: *PyObject, arr2_obj: *PyObject, op: CompareOp, allocator: std.mem.Allocator) !*PyObject {
    const arr1 = try numpy_array_mod.extractArray(arr1_obj);
    const arr2 = try numpy_array_mod.extractArray(arr2_obj);
    const result = try numpy_array_mod.compareArrays(arr1, arr2, op, allocator);
    return try numpy_array_mod.createBoolPyObject(allocator, result);
}

/// Greater than: arr > scalar
pub fn greater(arr_obj: *PyObject, scalar: f64, allocator: std.mem.Allocator) !*PyObject {
    return compareScalar(arr_obj, scalar, .gt, allocator);
}

/// Greater than or equal: arr >= scalar
pub fn greaterEqual(arr_obj: *PyObject, scalar: f64, allocator: std.mem.Allocator) !*PyObject {
    return compareScalar(arr_obj, scalar, .ge, allocator);
}

/// Less than: arr < scalar
pub fn less(arr_obj: *PyObject, scalar: f64, allocator: std.mem.Allocator) !*PyObject {
    return compareScalar(arr_obj, scalar, .lt, allocator);
}

/// Less than or equal: arr <= scalar
pub fn lessEqual(arr_obj: *PyObject, scalar: f64, allocator: std.mem.Allocator) !*PyObject {
    return compareScalar(arr_obj, scalar, .le, allocator);
}

/// Equal: arr == scalar
pub fn equal(arr_obj: *PyObject, scalar: f64, allocator: std.mem.Allocator) !*PyObject {
    return compareScalar(arr_obj, scalar, .eq, allocator);
}

/// Not equal: arr != scalar
pub fn notEqual(arr_obj: *PyObject, scalar: f64, allocator: std.mem.Allocator) !*PyObject {
    return compareScalar(arr_obj, scalar, .ne, allocator);
}

/// Sum of boolean array (count true values)
pub fn boolSum(arr_obj: *PyObject, _: std.mem.Allocator) !i64 {
    const arr = try numpy_array_mod.extractBoolArray(arr_obj);
    return @intCast(arr.countTrue());
}

/// Any - returns true if any element is true
pub fn boolAny(arr_obj: *PyObject, _: std.mem.Allocator) !bool {
    const arr = try numpy_array_mod.extractBoolArray(arr_obj);
    return arr.any();
}

/// All - returns true if all elements are true
pub fn boolAll(arr_obj: *PyObject, _: std.mem.Allocator) !bool {
    const arr = try numpy_array_mod.extractBoolArray(arr_obj);
    return arr.all();
}

/// Boolean indexing: arr[mask]
pub fn booleanIndex(arr_obj: *PyObject, mask_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const mask = try numpy_array_mod.extractBoolArray(mask_obj);
    const result = try numpy_array_mod.booleanIndex(arr, mask, allocator);
    return try numpy_array_mod.createPyObject(allocator, result);
}

/// Single index access: arr[i] - returns element at flat index
pub fn getIndex(arr_obj: *PyObject, idx: usize) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (idx >= arr.size) {
        return error.IndexOutOfBounds;
    }
    return arr.data[idx];
}

/// 2D index access: arr[i, j] - returns element at row i, column j
pub fn getIndex2D(arr_obj: *PyObject, row: usize, col: usize) !f64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    // Assumes row-major order (C-style)
    if (arr.shape.len < 2) {
        return error.InvalidDimensions;
    }
    const cols = arr.shape[1];
    const flat_idx = row * cols + col;
    if (flat_idx >= arr.size) {
        return error.IndexOutOfBounds;
    }
    return arr.data[flat_idx];
}

/// Get a column from 2D array: arr[:, col]
pub fn getColumn(arr_obj: *PyObject, col: usize, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);

    if (arr.shape.len < 2) {
        return error.InvalidDimensions;
    }

    const rows = arr.shape[0];
    const cols = arr.shape[1];

    if (col >= cols) {
        return error.IndexOutOfBounds;
    }

    // Extract column data
    const col_data = try allocator.alloc(f64, rows);
    for (0..rows) |row| {
        col_data[row] = arr.data[row * cols + col];
    }

    const np_result = try NumpyArray.fromOwnedSlice(allocator, col_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Get a row from 2D array: arr[row, :]
pub fn getRow(arr_obj: *PyObject, row: usize, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);

    if (arr.shape.len < 2) {
        return error.InvalidDimensions;
    }

    const rows = arr.shape[0];
    const cols = arr.shape[1];

    if (row >= rows) {
        return error.IndexOutOfBounds;
    }

    // Extract row data
    const row_data = try allocator.alloc(f64, cols);
    const row_start = row * cols;
    @memcpy(row_data, arr.data[row_start .. row_start + cols]);

    const np_result = try NumpyArray.fromOwnedSlice(allocator, row_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// 1D array slicing: arr[start:end]
pub fn slice1D(arr_obj: *PyObject, start_opt: ?usize, end_opt: ?usize, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);

    // Default start to 0, end to array size
    const start = start_opt orelse 0;
    const end = end_opt orelse arr.size;

    // Clamp to valid bounds
    const safe_start = @min(start, arr.size);
    const safe_end = @min(end, arr.size);

    if (safe_start >= safe_end) {
        // Empty slice
        const empty_data = try allocator.alloc(f64, 0);
        const np_result = try NumpyArray.fromOwnedSlice(allocator, empty_data);
        return try numpy_array_mod.createPyObject(allocator, np_result);
    }

    // Create new array from slice
    const slice_len = safe_end - safe_start;
    const slice_data = try allocator.alloc(f64, slice_len);
    @memcpy(slice_data, arr.data[safe_start..safe_end]);

    const np_result = try NumpyArray.fromOwnedSlice(allocator, slice_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Concatenation Functions
// ============================================================================

/// Concatenate arrays along axis 0 (default)
pub fn concatenate(arrays: []const *PyObject, allocator: std.mem.Allocator) !*PyObject {
    if (arrays.len == 0) return error.EmptyInput;
    var total_size: usize = 0;
    for (arrays) |arr_obj| {
        const arr = try numpy_array_mod.extractArray(arr_obj);
        total_size += arr.size;
    }
    const result_data = try allocator.alloc(f64, total_size);
    var offset: usize = 0;
    for (arrays) |arr_obj| {
        const arr = try numpy_array_mod.extractArray(arr_obj);
        @memcpy(result_data[offset .. offset + arr.size], arr.data);
        offset += arr.size;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Vertical stack - stack arrays vertically (row-wise)
pub fn vstack(arrays: []const *PyObject, allocator: std.mem.Allocator) !*PyObject {
    if (arrays.len == 0) return error.EmptyInput;
    const first_arr = try numpy_array_mod.extractArray(arrays[0]);
    const cols = first_arr.size;
    const rows = arrays.len;
    const result_data = try allocator.alloc(f64, rows * cols);
    for (arrays, 0..) |arr_obj, row| {
        const arr = try numpy_array_mod.extractArray(arr_obj);
        @memcpy(result_data[row * cols .. (row + 1) * cols], arr.data);
    }
    const np_result = try NumpyArray.fromOwnedSlice2D(allocator, result_data, rows, cols);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Horizontal stack - stack arrays horizontally (column-wise)
pub fn hstack(arrays: []const *PyObject, allocator: std.mem.Allocator) !*PyObject {
    return concatenate(arrays, allocator);
}

/// Stack arrays along a new axis (default axis=0)
pub fn stack(arrays: []const *PyObject, allocator: std.mem.Allocator) !*PyObject {
    return vstack(arrays, allocator);
}

/// Split array into n equal parts
pub fn split(arr_obj: *PyObject, n_sections: usize, allocator: std.mem.Allocator) ![]*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (n_sections == 0 or arr.size % n_sections != 0) return error.InvalidSplit;
    const section_size = arr.size / n_sections;
    const result = try allocator.alloc(*PyObject, n_sections);
    for (0..n_sections) |i| {
        const start = i * section_size;
        const section_data = try allocator.alloc(f64, section_size);
        @memcpy(section_data, arr.data[start .. start + section_size]);
        const np_section = try NumpyArray.fromOwnedSlice(allocator, section_data);
        result[i] = try numpy_array_mod.createPyObject(allocator, np_section);
    }
    return result;
}

// ============================================================================
// Conditional and Selection Functions
// ============================================================================

/// np.where(condition, x, y) - conditional selection
pub fn where(cond_obj: *PyObject, x_obj: *PyObject, y_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const cond = try numpy_array_mod.extractBoolArray(cond_obj);
    const x = try numpy_array_mod.extractArray(x_obj);
    const y = try numpy_array_mod.extractArray(y_obj);
    if (cond.size != x.size or x.size != y.size) return error.DimensionMismatch;
    const result_data = try allocator.alloc(f64, cond.size);
    for (0..cond.size) |i| {
        result_data[i] = if (cond.data[i]) x.data[i] else y.data[i];
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.clip(arr, min, max) - clip values to range
pub fn clip(arr_obj: *PyObject, min_val: f64, max_val: f64, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = @max(min_val, @min(max_val, val));
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Rounding Functions
// ============================================================================

/// np.floor(arr) - floor of each element
pub fn floor(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = @floor(val);
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.ceil(arr) - ceiling of each element
pub fn ceil(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = @ceil(val);
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.round(arr) or np.rint(arr) - round to nearest integer
pub fn npRound(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = @round(val);
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Sorting and Searching Functions
// ============================================================================

/// np.sort(arr) - sort array (returns sorted copy)
pub fn sort(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    @memcpy(result_data, arr.data);
    std.mem.sort(f64, result_data, {}, std.sort.asc(f64));
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.argsort(arr) - indices that would sort the array
pub fn argsort(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const indices = try allocator.alloc(usize, arr.size);
    defer allocator.free(indices);
    for (0..arr.size) |i| indices[i] = i;
    const Context = struct {
        data: []const f64,
        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.data[a] < ctx.data[b];
        }
    };
    std.mem.sort(usize, indices, Context{ .data = arr.data }, Context.lessThan);
    const result_data = try allocator.alloc(f64, arr.size);
    for (indices, 0..) |idx, i| result_data[i] = @floatFromInt(idx);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.unique(arr) - unique elements (sorted)
pub fn unique(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const sorted = try allocator.alloc(f64, arr.size);
    defer allocator.free(sorted);
    @memcpy(sorted, arr.data);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    var unique_count: usize = if (arr.size > 0) 1 else 0;
    for (1..arr.size) |i| {
        if (sorted[i] != sorted[i - 1]) unique_count += 1;
    }
    const result_data = try allocator.alloc(f64, unique_count);
    if (arr.size > 0) {
        result_data[0] = sorted[0];
        var j: usize = 1;
        for (1..arr.size) |i| {
            if (sorted[i] != sorted[i - 1]) {
                result_data[j] = sorted[i];
                j += 1;
            }
        }
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.searchsorted(arr, value) - find insertion index
pub fn searchsorted(arr_obj: *PyObject, value: f64, _: std.mem.Allocator) !i64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    var lo: usize = 0;
    var hi: usize = arr.size;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (arr.data[mid] < value) lo = mid + 1 else hi = mid;
    }
    return @intCast(lo);
}

// ============================================================================
// Array Copying Functions
// ============================================================================

/// np.copy(arr) - return a copy of the array
pub fn copy(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    @memcpy(result_data, arr.data);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    np_result.shape = try allocator.dupe(usize, arr.shape);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.asarray(arr) - convert input to array
pub const asarray = copy;

// ============================================================================
// Repeating and Flipping Functions
// ============================================================================

/// np.tile(arr, reps) - repeat array `reps` times
pub fn tile(arr_obj: *PyObject, reps: usize, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_size = arr.size * reps;
    const result_data = try allocator.alloc(f64, result_size);
    for (0..reps) |r| @memcpy(result_data[r * arr.size .. (r + 1) * arr.size], arr.data);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.repeat(arr, repeats) - repeat each element
pub fn repeat(arr_obj: *PyObject, repeats: usize, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_size = arr.size * repeats;
    const result_data = try allocator.alloc(f64, result_size);
    var idx: usize = 0;
    for (arr.data) |val| {
        for (0..repeats) |_| {
            result_data[idx] = val;
            idx += 1;
        }
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.flip(arr) - reverse array
pub fn flip(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (0..arr.size) |i| result_data[i] = arr.data[arr.size - 1 - i];
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.flipud(arr) - flip array vertically (for 2D)
pub fn flipud(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    if (arr.shape.len == 2) {
        const rows = arr.shape[0];
        const cols = arr.shape[1];
        for (0..rows) |i| {
            const src_row = rows - 1 - i;
            @memcpy(result_data[i * cols .. (i + 1) * cols], arr.data[src_row * cols .. (src_row + 1) * cols]);
        }
    } else {
        for (0..arr.size) |i| result_data[i] = arr.data[arr.size - 1 - i];
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    np_result.shape = try allocator.dupe(usize, arr.shape);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.fliplr(arr) - flip array horizontally (for 2D)
pub fn fliplr(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    if (arr.shape.len == 2) {
        const rows = arr.shape[0];
        const cols = arr.shape[1];
        for (0..rows) |i| {
            for (0..cols) |j| result_data[i * cols + j] = arr.data[i * cols + (cols - 1 - j)];
        }
    } else {
        for (0..arr.size) |i| result_data[i] = arr.data[arr.size - 1 - i];
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    np_result.shape = try allocator.dupe(usize, arr.shape);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Cumulative Operations
// ============================================================================

/// np.cumsum(arr) - cumulative sum
pub fn cumsum(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    var running_sum: f64 = 0.0;
    for (arr.data, 0..) |val, i| {
        running_sum += val;
        result_data[i] = running_sum;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.cumprod(arr) - cumulative product
pub fn cumprod(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    var running_prod: f64 = 1.0;
    for (arr.data, 0..) |val, i| {
        running_prod *= val;
        result_data[i] = running_prod;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.diff(arr) - differences between consecutive elements
pub fn diff(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.size == 0) {
        const empty_data = try allocator.alloc(f64, 0);
        const np_result = try NumpyArray.fromOwnedSlice(allocator, empty_data);
        return try numpy_array_mod.createPyObject(allocator, np_result);
    }
    const result_data = try allocator.alloc(f64, arr.size - 1);
    for (0..arr.size - 1) |i| result_data[i] = arr.data[i + 1] - arr.data[i];
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Comparison Functions
// ============================================================================

/// np.allclose(a, b, rtol, atol) - check if arrays are close
pub fn allclose(a_obj: *PyObject, b_obj: *PyObject, rtol: f64, atol: f64, _: std.mem.Allocator) !bool {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != b.size) return false;
    for (a.data, b.data) |av, bv| {
        if (@abs(av - bv) > atol + rtol * @abs(bv)) return false;
    }
    return true;
}

/// np.array_equal(a, b) - check if arrays are exactly equal
pub fn array_equal(a_obj: *PyObject, b_obj: *PyObject, _: std.mem.Allocator) !bool {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != b.size) return false;
    if (a.shape.len != b.shape.len) return false;
    for (a.shape, b.shape) |as, bs| {
        if (as != bs) return false;
    }
    for (a.data, b.data) |av, bv| {
        if (av != bv) return false;
    }
    return true;
}

// ============================================================================
// Matrix Construction Functions
// ============================================================================

/// np.diag(arr) - extract diagonal or construct diagonal matrix
pub fn diag(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len == 1) {
        const n = arr.size;
        const result_data = try allocator.alloc(f64, n * n);
        @memset(result_data, 0.0);
        for (0..n) |i| result_data[i * n + i] = arr.data[i];
        const np_result = try NumpyArray.fromOwnedSlice2D(allocator, result_data, n, n);
        return try numpy_array_mod.createPyObject(allocator, np_result);
    } else if (arr.shape.len == 2) {
        const n = @min(arr.shape[0], arr.shape[1]);
        const cols = arr.shape[1];
        const result_data = try allocator.alloc(f64, n);
        for (0..n) |i| result_data[i] = arr.data[i * cols + i];
        const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
        return try numpy_array_mod.createPyObject(allocator, np_result);
    }
    return error.InvalidDimension;
}

/// np.triu(arr) - upper triangle of matrix
pub fn triu(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len != 2) return error.InvalidDimension;
    const rows = arr.shape[0];
    const cols = arr.shape[1];
    const result_data = try allocator.alloc(f64, arr.size);
    for (0..rows) |i| {
        for (0..cols) |j| result_data[i * cols + j] = if (j >= i) arr.data[i * cols + j] else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice2D(allocator, result_data, rows, cols);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.tril(arr) - lower triangle of matrix
pub fn tril(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len != 2) return error.InvalidDimension;
    const rows = arr.shape[0];
    const cols = arr.shape[1];
    const result_data = try allocator.alloc(f64, arr.size);
    for (0..rows) |i| {
        for (0..cols) |j| result_data[i * cols + j] = if (j <= i) arr.data[i * cols + j] else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice2D(allocator, result_data, rows, cols);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Additional Math Functions
// ============================================================================

/// np.tan(arr) - tangent
pub fn tan(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = @tan(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.arcsin(arr) - inverse sine
pub fn arcsin(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.asin(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.arccos(arr) - inverse cosine
pub fn arccos(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.acos(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.arctan(arr) - inverse tangent
pub fn arctan(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.atan(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.sinh(arr) - hyperbolic sine
pub fn sinh(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.sinh(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.cosh(arr) - hyperbolic cosine
pub fn cosh(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.cosh(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.tanh(arr) - hyperbolic tangent
pub fn tanh(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.tanh(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.log10(arr) - base-10 logarithm
pub fn log10(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.log10(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.log2(arr) - base-2 logarithm
pub fn log2(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.log2(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.exp2(arr) - 2^x
pub fn exp2(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.exp2(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.expm1(arr) - exp(x) - 1
pub fn expm1(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.expm1(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.log1p(arr) - log(1 + x)
pub fn log1p(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.log1p(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.sign(arr) - sign of elements (-1, 0, or 1)
pub fn sign(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = if (val > 0) 1.0 else if (val < 0) -1.0 else 0.0;
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.negative(arr) - numerical negative
pub fn negative(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = -val;
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.reciprocal(arr) - 1/x
pub fn reciprocal(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = 1.0 / val;
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.square(arr) - x^2
pub fn square(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = val * val;
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.cbrt(arr) - cube root
pub fn cbrt(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| result_data[i] = std.math.cbrt(val);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.maximum(a, b) - element-wise maximum
pub fn maximum(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != b.size) return error.DimensionMismatch;
    const result_data = try allocator.alloc(f64, a.size);
    for (a.data, b.data, 0..) |av, bv, i| result_data[i] = @max(av, bv);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.minimum(a, b) - element-wise minimum
pub fn minimum(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != b.size) return error.DimensionMismatch;
    const result_data = try allocator.alloc(f64, a.size);
    for (a.data, b.data, 0..) |av, bv, i| result_data[i] = @min(av, bv);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.mod(a, b) or np.remainder(a, b) - element-wise modulo
pub fn mod(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != b.size) return error.DimensionMismatch;
    const result_data = try allocator.alloc(f64, a.size);
    for (a.data, b.data, 0..) |av, bv, i| result_data[i] = @mod(av, bv);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Array Manipulation Functions (Additional)
// ============================================================================

/// np.roll(arr, shift) - roll array elements
pub fn roll(arr_obj: *PyObject, shift_val: i64, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    const n: i64 = @intCast(arr.size);
    const shift = @mod(shift_val, n);
    for (0..arr.size) |i| {
        const src_idx: usize = @intCast(@mod(@as(i64, @intCast(i)) - shift + n, n));
        result_data[i] = arr.data[src_idx];
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.rot90(arr) - rotate 2D array 90 degrees counter-clockwise
pub fn rot90(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len != 2) return error.InvalidDimension;
    const rows = arr.shape[0];
    const cols = arr.shape[1];
    const result_data = try allocator.alloc(f64, arr.size);
    for (0..rows) |i| {
        for (0..cols) |j| {
            result_data[j * rows + (rows - 1 - i)] = arr.data[i * cols + j];
        }
    }
    const np_result = try NumpyArray.fromOwnedSlice2D(allocator, result_data, cols, rows);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.pad(arr, pad_width, constant_values) - pad array with constant
pub fn pad(arr_obj: *PyObject, pad_before: usize, pad_after: usize, value: f64, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const new_size = arr.size + pad_before + pad_after;
    const result_data = try allocator.alloc(f64, new_size);
    @memset(result_data[0..pad_before], value);
    @memcpy(result_data[pad_before .. pad_before + arr.size], arr.data);
    @memset(result_data[pad_before + arr.size ..], value);
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.take(arr, indices) - take elements at indices
pub fn take(arr_obj: *PyObject, indices_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const indices = try numpy_array_mod.extractArray(indices_obj);
    const result_data = try allocator.alloc(f64, indices.size);
    for (indices.data, 0..) |idx_f, i| {
        const idx: usize = @intFromFloat(idx_f);
        result_data[i] = if (idx < arr.size) arr.data[idx] else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.put(arr, indices, values) - put values at indices (modifies in place, returns copy)
pub fn put(arr_obj: *PyObject, indices_obj: *PyObject, values_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const indices = try numpy_array_mod.extractArray(indices_obj);
    const values = try numpy_array_mod.extractArray(values_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    @memcpy(result_data, arr.data);
    for (indices.data, 0..) |idx_f, i| {
        const idx: usize = @intFromFloat(idx_f);
        if (idx < arr.size) {
            result_data[idx] = values.data[i % values.size];
        }
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.cross(a, b) - cross product for 3D vectors
pub fn cross(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != 3 or b.size != 3) return error.InvalidDimension;
    const result_data = try allocator.alloc(f64, 3);
    result_data[0] = a.data[1] * b.data[2] - a.data[2] * b.data[1];
    result_data[1] = a.data[2] * b.data[0] - a.data[0] * b.data[2];
    result_data[2] = a.data[0] * b.data[1] - a.data[1] * b.data[0];
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Logical Functions
// ============================================================================

/// np.any(arr) - test if any element is true (non-zero)
pub fn npAny(arr_obj: *PyObject, _: std.mem.Allocator) !bool {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    for (arr.data) |val| {
        if (val != 0.0) return true;
    }
    return false;
}

/// np.all(arr) - test if all elements are true (non-zero)
pub fn npAll(arr_obj: *PyObject, _: std.mem.Allocator) !bool {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    for (arr.data) |val| {
        if (val == 0.0) return false;
    }
    return true;
}

/// np.logical_and(a, b) - element-wise logical AND
pub fn logical_and(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != b.size) return error.DimensionMismatch;
    const result_data = try allocator.alloc(f64, a.size);
    for (a.data, b.data, 0..) |av, bv, i| {
        result_data[i] = if (av != 0.0 and bv != 0.0) 1.0 else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.logical_or(a, b) - element-wise logical OR
pub fn logical_or(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != b.size) return error.DimensionMismatch;
    const result_data = try allocator.alloc(f64, a.size);
    for (a.data, b.data, 0..) |av, bv, i| {
        result_data[i] = if (av != 0.0 or bv != 0.0) 1.0 else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.logical_not(arr) - element-wise logical NOT
pub fn logical_not(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = if (val == 0.0) 1.0 else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.logical_xor(a, b) - element-wise logical XOR
pub fn logical_xor(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    if (a.size != b.size) return error.DimensionMismatch;
    const result_data = try allocator.alloc(f64, a.size);
    for (a.data, b.data, 0..) |av, bv, i| {
        const a_bool = av != 0.0;
        const b_bool = bv != 0.0;
        result_data[i] = if (a_bool != b_bool) 1.0 else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Set Functions
// ============================================================================

/// np.setdiff1d(a, b) - set difference of two arrays
pub fn setdiff1d(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    var result_list = std.ArrayList(f64).init(allocator);
    defer result_list.deinit();
    outer: for (a.data) |av| {
        for (b.data) |bv| {
            if (av == bv) continue :outer;
        }
        try result_list.append(av);
    }
    const result_data = try result_list.toOwnedSlice();
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.union1d(a, b) - union of two arrays (unique sorted)
pub fn union1d(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    const combined = try allocator.alloc(f64, a.size + b.size);
    defer allocator.free(combined);
    @memcpy(combined[0..a.size], a.data);
    @memcpy(combined[a.size..], b.data);
    std.mem.sort(f64, combined, {}, std.sort.asc(f64));
    var unique_count: usize = if (combined.len > 0) 1 else 0;
    for (1..combined.len) |i| {
        if (combined[i] != combined[i - 1]) unique_count += 1;
    }
    const result_data = try allocator.alloc(f64, unique_count);
    if (combined.len > 0) {
        result_data[0] = combined[0];
        var j: usize = 1;
        for (1..combined.len) |i| {
            if (combined[i] != combined[i - 1]) {
                result_data[j] = combined[i];
                j += 1;
            }
        }
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.intersect1d(a, b) - intersection of two arrays
pub fn intersect1d(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    var result_list = std.ArrayList(f64).init(allocator);
    defer result_list.deinit();
    for (a.data) |av| {
        for (b.data) |bv| {
            if (av == bv) {
                var found = false;
                for (result_list.items) |rv| {
                    if (rv == av) {
                        found = true;
                        break;
                    }
                }
                if (!found) try result_list.append(av);
                break;
            }
        }
    }
    const result_data = try result_list.toOwnedSlice();
    std.mem.sort(f64, result_data, {}, std.sort.asc(f64));
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.isin(a, b) - test whether elements of a are in b
pub fn isin(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const b = try numpy_array_mod.extractArray(b_obj);
    const result_data = try allocator.alloc(f64, a.size);
    for (a.data, 0..) |av, i| {
        var found = false;
        for (b.data) |bv| {
            if (av == bv) {
                found = true;
                break;
            }
        }
        result_data[i] = if (found) 1.0 else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Numerical Functions
// ============================================================================

/// np.gradient(arr) - numerical gradient (central differences)
pub fn gradient(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.size < 2) {
        const result_data = try allocator.alloc(f64, arr.size);
        @memset(result_data, 0.0);
        const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
        return try numpy_array_mod.createPyObject(allocator, np_result);
    }
    const result_data = try allocator.alloc(f64, arr.size);
    result_data[0] = arr.data[1] - arr.data[0];
    for (1..arr.size - 1) |i| {
        result_data[i] = (arr.data[i + 1] - arr.data[i - 1]) / 2.0;
    }
    result_data[arr.size - 1] = arr.data[arr.size - 1] - arr.data[arr.size - 2];
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.trapz(y, dx) - trapezoidal integration
pub fn trapz(y_obj: *PyObject, dx: f64, _: std.mem.Allocator) !f64 {
    const y = try numpy_array_mod.extractArray(y_obj);
    if (y.size < 2) return 0.0;
    var result: f64 = 0.0;
    for (0..y.size - 1) |i| {
        result += (y.data[i] + y.data[i + 1]) * dx / 2.0;
    }
    return result;
}

/// np.interp(x, xp, fp) - linear interpolation
pub fn interp(x_val: f64, xp_obj: *PyObject, fp_obj: *PyObject, _: std.mem.Allocator) !f64 {
    const xp = try numpy_array_mod.extractArray(xp_obj);
    const fp = try numpy_array_mod.extractArray(fp_obj);
    if (xp.size != fp.size or xp.size == 0) return error.DimensionMismatch;
    if (x_val <= xp.data[0]) return fp.data[0];
    if (x_val >= xp.data[xp.size - 1]) return fp.data[fp.size - 1];
    for (0..xp.size - 1) |i| {
        if (x_val >= xp.data[i] and x_val < xp.data[i + 1]) {
            const t = (x_val - xp.data[i]) / (xp.data[i + 1] - xp.data[i]);
            return fp.data[i] + t * (fp.data[i + 1] - fp.data[i]);
        }
    }
    return fp.data[fp.size - 1];
}

/// np.convolve(a, v, mode='full') - convolution
pub fn convolve(a_obj: *PyObject, v_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const v = try numpy_array_mod.extractArray(v_obj);
    const out_size = a.size + v.size - 1;
    const result_data = try allocator.alloc(f64, out_size);
    @memset(result_data, 0.0);
    for (0..a.size) |i| {
        for (0..v.size) |j| {
            result_data[i + j] += a.data[i] * v.data[j];
        }
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.correlate(a, v) - cross-correlation
pub fn correlate(a_obj: *PyObject, v_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a = try numpy_array_mod.extractArray(a_obj);
    const v = try numpy_array_mod.extractArray(v_obj);
    const out_size = a.size + v.size - 1;
    const result_data = try allocator.alloc(f64, out_size);
    @memset(result_data, 0.0);
    for (0..a.size) |i| {
        for (0..v.size) |j| {
            result_data[i + j] += a.data[i] * v.data[v.size - 1 - j];
        }
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

// ============================================================================
// Utility Functions
// ============================================================================

/// np.nonzero(arr) - indices of non-zero elements
pub fn nonzero(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    var count: usize = 0;
    for (arr.data) |val| {
        if (val != 0.0) count += 1;
    }
    const result_data = try allocator.alloc(f64, count);
    var j: usize = 0;
    for (arr.data, 0..) |val, i| {
        if (val != 0.0) {
            result_data[j] = @floatFromInt(i);
            j += 1;
        }
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.count_nonzero(arr) - count non-zero elements
pub fn count_nonzero(arr_obj: *PyObject, _: std.mem.Allocator) !i64 {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    var count: i64 = 0;
    for (arr.data) |val| {
        if (val != 0.0) count += 1;
    }
    return count;
}

/// np.flatnonzero(arr) - flat indices of non-zero elements
pub const flatnonzero = nonzero;

/// np.meshgrid(x, y) - coordinate matrices from vectors
pub fn meshgrid(x_obj: *PyObject, y_obj: *PyObject, allocator: std.mem.Allocator) !struct { xx: *PyObject, yy: *PyObject } {
    const x = try numpy_array_mod.extractArray(x_obj);
    const y = try numpy_array_mod.extractArray(y_obj);
    const xx_data = try allocator.alloc(f64, x.size * y.size);
    const yy_data = try allocator.alloc(f64, x.size * y.size);
    for (0..y.size) |i| {
        for (0..x.size) |j| {
            xx_data[i * x.size + j] = x.data[j];
            yy_data[i * x.size + j] = y.data[i];
        }
    }
    const xx_arr = try NumpyArray.fromOwnedSlice2D(allocator, xx_data, y.size, x.size);
    const yy_arr = try NumpyArray.fromOwnedSlice2D(allocator, yy_data, y.size, x.size);
    return .{
        .xx = try numpy_array_mod.createPyObject(allocator, xx_arr),
        .yy = try numpy_array_mod.createPyObject(allocator, yy_arr),
    };
}

/// np.histogram(arr, bins) - compute histogram
pub fn histogram(arr_obj: *PyObject, n_bins: usize, allocator: std.mem.Allocator) !struct { counts: *PyObject, edges: *PyObject } {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    var min_val: f64 = arr.data[0];
    var max_val: f64 = arr.data[0];
    for (arr.data) |val| {
        if (val < min_val) min_val = val;
        if (val > max_val) max_val = val;
    }
    const bin_width = (max_val - min_val) / @as(f64, @floatFromInt(n_bins));
    const counts_data = try allocator.alloc(f64, n_bins);
    @memset(counts_data, 0.0);
    for (arr.data) |val| {
        var bin_idx: usize = @intFromFloat((val - min_val) / bin_width);
        if (bin_idx >= n_bins) bin_idx = n_bins - 1;
        counts_data[bin_idx] += 1.0;
    }
    const edges_data = try allocator.alloc(f64, n_bins + 1);
    for (0..n_bins + 1) |i| {
        edges_data[i] = min_val + @as(f64, @floatFromInt(i)) * bin_width;
    }
    const counts_arr = try NumpyArray.fromOwnedSlice(allocator, counts_data);
    const edges_arr = try NumpyArray.fromOwnedSlice(allocator, edges_data);
    return .{
        .counts = try numpy_array_mod.createPyObject(allocator, counts_arr),
        .edges = try numpy_array_mod.createPyObject(allocator, edges_arr),
    };
}

/// np.bincount(arr) - count occurrences of each value
pub fn bincount(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    var max_val: usize = 0;
    for (arr.data) |val| {
        const idx: usize = @intFromFloat(val);
        if (idx > max_val) max_val = idx;
    }
    const result_data = try allocator.alloc(f64, max_val + 1);
    @memset(result_data, 0.0);
    for (arr.data) |val| {
        const idx: usize = @intFromFloat(val);
        result_data[idx] += 1.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.digitize(arr, bins) - return indices of bins
pub fn digitize(arr_obj: *PyObject, bins_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const bins = try numpy_array_mod.extractArray(bins_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        var bin_idx: usize = 0;
        for (bins.data) |bin_edge| {
            if (val >= bin_edge) bin_idx += 1 else break;
        }
        result_data[i] = @floatFromInt(bin_idx);
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.nan_to_num(arr) - replace nan/inf with 0
pub fn nan_to_num(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = if (std.math.isNan(val) or std.math.isInf(val)) 0.0 else val;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.isnan(arr) - element-wise isnan check
pub fn isnan(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = if (std.math.isNan(val)) 1.0 else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.isinf(arr) - element-wise isinf check
pub fn isinf(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = if (std.math.isInf(val)) 1.0 else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.isfinite(arr) - element-wise isfinite check
pub fn isfinite(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        result_data[i] = if (!std.math.isNan(val) and !std.math.isInf(val)) 1.0 else 0.0;
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.clip with array bounds
pub fn clipArrays(arr_obj: *PyObject, min_obj: *PyObject, max_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const min_arr = try numpy_array_mod.extractArray(min_obj);
    const max_arr = try numpy_array_mod.extractArray(max_obj);
    const result_data = try allocator.alloc(f64, arr.size);
    for (arr.data, 0..) |val, i| {
        const min_val = min_arr.data[i % min_arr.size];
        const max_val = max_arr.data[i % max_arr.size];
        result_data[i] = @max(min_val, @min(max_val, val));
    }
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// np.absolute or np.fabs - element-wise absolute (alias for abs)
pub const absolute = npAbs;
pub const fabs = npAbs;

test "array creation from integers" {
    const allocator = std.testing.allocator;

    const data = [_]i64{1, 2, 3, 4, 5};
    const arr_obj = try array(&data, allocator);
    defer {
        const arr = numpy_array_mod.extractArray(arr_obj) catch unreachable;
        arr.deinit();
        allocator.destroy(arr_obj);
    }

    const arr = try numpy_array_mod.extractArray(arr_obj);
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
        const a = numpy_array_mod.extractArray(a_obj) catch unreachable;
        const b = numpy_array_mod.extractArray(b_obj) catch unreachable;
        a.deinit();
        b.deinit();
        allocator.destroy(a_obj);
        allocator.destroy(b_obj);
    }

    // dot now returns f64 directly (not PyObject)
    const result = try dot(a_obj, b_obj, allocator);
    // Expected: 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
    try std.testing.expectEqual(@as(f64, 32.0), result);
}

test "sum with PyObject" {
    const allocator = std.testing.allocator;

    const arr_data = [_]f64{1.0, 2.0, 3.0, 4.0, 5.0};
    const arr_obj = try arrayFloat(&arr_data, allocator);
    defer {
        const arr = numpy_array_mod.extractArray(arr_obj) catch unreachable;
        arr.deinit();
        allocator.destroy(arr_obj);
    }

    // sum now returns f64 directly (not PyObject)
    const result = try sum(arr_obj, allocator);
    // Expected: 1 + 2 + 3 + 4 + 5 = 15
    try std.testing.expectEqual(@as(f64, 15.0), result);
}

test "mean with PyObject" {
    const allocator = std.testing.allocator;

    const arr_data = [_]f64{1.0, 2.0, 3.0, 4.0, 5.0};
    const arr_obj = try arrayFloat(&arr_data, allocator);
    defer {
        const arr = numpy_array_mod.extractArray(arr_obj) catch unreachable;
        arr.deinit();
        allocator.destroy(arr_obj);
    }

    // mean now returns f64 directly (not PyObject)
    const result = try mean(arr_obj, allocator);
    // Expected: 15 / 5 = 3.0
    try std.testing.expectEqual(@as(f64, 3.0), result);
}
