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

/// Matrix inverse - np.linalg.inv(arr)
/// Returns: inverted matrix as PyObject
pub fn inv(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len != 2 or arr.shape[0] != arr.shape[1]) {
        return error.InvalidDimension;
    }
    const n: c_int = @intCast(arr.shape[0]);

    // Copy matrix data in column-major order (LAPACK uses Fortran layout)
    // For row-major input, transposing is equivalent to computing inv(A^T)^T = inv(A)
    // So we can just use the data as-is and the result will be correct
    const result_data = try allocator.alloc(f64, @intCast(n * n));
    @memcpy(result_data, arr.data);

    // Pivot indices for LU factorization
    const ipiv = try allocator.alloc(c_int, @intCast(n));
    defer allocator.free(ipiv);

    // LU factorization (Fortran interface)
    var info: c_int = 0;
    dgetrf_(&n, &n, result_data.ptr, &n, ipiv.ptr, &info);
    if (info != 0) {
        allocator.free(result_data);
        return error.SingularMatrix;
    }

    // Query optimal workspace size
    var work_query: f64 = 0;
    var lwork: c_int = -1;
    dgetri_(&n, result_data.ptr, &n, ipiv.ptr, @ptrCast(&work_query), &lwork, &info);

    // Allocate workspace
    lwork = @intFromFloat(work_query);
    const work = try allocator.alloc(f64, @intCast(lwork));
    defer allocator.free(work);

    // Compute inverse from LU factorization
    dgetri_(&n, result_data.ptr, &n, ipiv.ptr, work.ptr, &lwork, &info);
    if (info != 0) {
        allocator.free(result_data);
        return error.SingularMatrix;
    }

    // Wrap result
    const np_result = try NumpyArray.fromOwnedSlice(allocator, result_data);
    np_result.shape = try allocator.dupe(usize, arr.shape);
    return try numpy_array_mod.createPyObject(allocator, np_result);
}

/// Solve linear system - np.linalg.solve(a, b)
/// Solves Ax = b for x
/// Returns: solution vector/matrix as PyObject
pub fn solve(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const a_arr = try numpy_array_mod.extractArray(a_obj);
    const b_arr = try numpy_array_mod.extractArray(b_obj);

    if (a_arr.shape.len != 2 or a_arr.shape[0] != a_arr.shape[1]) {
        return error.InvalidDimension;
    }
    const n: c_int = @intCast(a_arr.shape[0]);

    // Determine number of right-hand sides
    const nrhs: c_int = if (b_arr.shape.len == 1) 1 else @intCast(b_arr.shape[1]);

    // Copy A matrix (LAPACK modifies in place)
    const a_copy = try allocator.alloc(f64, @intCast(n * n));
    defer allocator.free(a_copy);
    @memcpy(a_copy, a_arr.data);

    // Copy b vector/matrix (solution overwrites this)
    const result_data = try allocator.alloc(f64, b_arr.size);
    @memcpy(result_data, b_arr.data);

    // Pivot indices
    const ipiv = try allocator.alloc(c_int, @intCast(n));
    defer allocator.free(ipiv);

    // Solve the system (Fortran interface)
    var info: c_int = 0;
    dgesv_(&n, &nrhs, a_copy.ptr, &n, ipiv.ptr, result_data.ptr, &n, &info);
    if (info != 0) {
        allocator.free(result_data);
        return error.SingularMatrix;
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
