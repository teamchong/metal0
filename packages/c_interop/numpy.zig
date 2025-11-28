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
/// Returns: PyObject wrapping float result
pub fn dot(a_obj: *PyObject, b_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    // Extract NumPy arrays from PyObjects
    const a_arr = try numpy_array_mod.extractArray(a_obj);
    const b_arr = try numpy_array_mod.extractArray(b_obj);

    std.debug.assert(a_arr.size == b_arr.size);

    // Use BLAS ddot: double precision dot product
    const ddot_result = cblas_ddot(
        @intCast(a_arr.size),  // N: number of elements
        a_arr.data.ptr,        // X: pointer to first vector
        1,                     // incX: stride for X
        b_arr.data.ptr,        // Y: pointer to second vector
        1                      // incY: stride for Y
    );

    // Wrap result in PyFloat
    return try PyFloat.create(allocator, ddot_result);
}

/// Sum all elements in array (Python: np.sum(arr))
/// Returns: PyObject wrapping float result
pub fn sum(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);

    var total: f64 = 0.0;
    for (arr.data) |val| {
        total += val;
    }

    return try PyFloat.create(allocator, total);
}

/// Calculate mean (average) of array elements (Python: np.mean(arr))
/// Returns: PyObject wrapping float result
pub fn mean(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);

    if (arr.size == 0) {
        return try PyFloat.create(allocator, 0.0);
    }

    var total: f64 = 0.0;
    for (arr.data) |val| {
        total += val;
    }

    const avg = total / @as(f64, @floatFromInt(arr.size));
    return try PyFloat.create(allocator, avg);
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
pub fn npStd(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return try PyFloat.create(allocator, arr.stddev());
}

/// Variance - np.var(arr)
pub fn npVar(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return try PyFloat.create(allocator, arr.variance());
}

/// Minimum - np.min(arr)
pub fn npMin(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return try PyFloat.create(allocator, arr.min());
}

/// Maximum - np.max(arr)
pub fn npMax(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return try PyFloat.create(allocator, arr.max());
}

/// Index of minimum - np.argmin(arr)
pub fn argmin(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = arr.argmin();
    const obj = try allocator.create(PyObject);
    obj.* = .{
        .ref_count = 1,
        .type_id = .int,
        .data = @ptrFromInt(result),
    };
    return obj;
}

/// Index of maximum - np.argmax(arr)
pub fn argmax(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const result = arr.argmax();
    const obj = try allocator.create(PyObject);
    obj.* = .{
        .ref_count = 1,
        .type_id = .int,
        .data = @ptrFromInt(result),
    };
    return obj;
}

/// Product - np.prod(arr)
pub fn prod(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    return try PyFloat.create(allocator, arr.prod());
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
pub fn norm(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    var sum_sq: f64 = 0.0;
    for (arr.data) |val| {
        sum_sq += val * val;
    }
    return try PyFloat.create(allocator, @sqrt(sum_sq));
}

/// Determinant - np.linalg.det(arr)
pub fn det(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
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
    return try PyFloat.create(allocator, result);
}

/// Trace - np.trace(arr)
pub fn trace(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    if (arr.shape.len != 2) return error.InvalidDimension;
    const n = @min(arr.shape[0], arr.shape[1]);
    var result: f64 = 0.0;
    for (0..n) |i| {
        result += arr.data[i * arr.shape[1] + i];
    }
    return try PyFloat.create(allocator, result);
}

// ============================================================================
// Statistics Functions
// ============================================================================

/// Median - np.median(arr)
pub fn median(arr_obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const sorted = try allocator.alloc(f64, arr.size);
    defer allocator.free(sorted);
    @memcpy(sorted, arr.data);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    const mid = arr.size / 2;
    const result = if (arr.size % 2 == 0)
        (sorted[mid - 1] + sorted[mid]) / 2.0
    else
        sorted[mid];
    return try PyFloat.create(allocator, result);
}

/// Percentile - np.percentile(arr, q)
pub fn percentile(arr_obj: *PyObject, q: f64, allocator: std.mem.Allocator) !*PyObject {
    const arr = try numpy_array_mod.extractArray(arr_obj);
    const sorted = try allocator.alloc(f64, arr.size);
    defer allocator.free(sorted);
    @memcpy(sorted, arr.data);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    const idx = (q / 100.0) * @as(f64, @floatFromInt(arr.size - 1));
    const lo: usize = @intFromFloat(@floor(idx));
    const hi: usize = @intFromFloat(@ceil(idx));
    const frac = idx - @as(f64, @floatFromInt(lo));
    const result = sorted[lo] * (1.0 - frac) + sorted[@min(hi, arr.size - 1)] * frac;
    return try PyFloat.create(allocator, result);
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

    const result_obj = try dot(a_obj, b_obj, allocator);
    defer allocator.destroy(result_obj);

    const result_float = @as(*PyFloat, @ptrCast(@alignCast(result_obj.data)));
    // Expected: 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
    try std.testing.expectEqual(@as(f64, 32.0), result_float.value);
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

    const result_obj = try sum(arr_obj, allocator);
    defer allocator.destroy(result_obj);

    const result_float = @as(*PyFloat, @ptrCast(@alignCast(result_obj.data)));
    // Expected: 1 + 2 + 3 + 4 + 5 = 15
    try std.testing.expectEqual(@as(f64, 15.0), result_float.value);
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

    const result_obj = try mean(arr_obj, allocator);
    defer allocator.destroy(result_obj);

    const result_float = @as(*PyFloat, @ptrCast(@alignCast(result_obj.data)));
    // Expected: 15 / 5 = 3.0
    try std.testing.expectEqual(@as(f64, 3.0), result_float.value);
}
