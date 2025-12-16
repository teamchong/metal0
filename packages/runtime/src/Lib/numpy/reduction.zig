//! NumPy Array Reduction Operations
//!
//! Reduction operations: sum, mean, max, min, argmax, argmin, prod, etc.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ndarray_mod = @import("ndarray.zig");
const ndarray = ndarray_mod.ndarray;
const creation = @import("creation.zig");

// ============================================================================
// Basic Reductions
// ============================================================================

/// Sum of array elements
/// np.sum(a) or np.sum(a, axis=0)
pub fn sum(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    if (axis) |ax| {
        return sumAxis(allocator, a, ax);
    }
    // Total sum
    var total: f64 = 0;
    for (0..a.size) |i| {
        total += a.data[i];
    }
    const data = try allocator.alloc(f64, 1);
    data[0] = total;
    return ndarray.initWithData(allocator, data, &.{1}, .float64);
}

/// Mean of array elements
/// np.mean(a) or np.mean(a, axis=0)
pub fn mean(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    var s = try sum(allocator, a, axis);
    if (axis == null) {
        s.data[0] /= @floatFromInt(a.size);
    } else {
        const ax = axis.?;
        const divisor: f64 = @floatFromInt(a.shape[ax]);
        for (0..s.size) |i| {
            s.data[i] /= divisor;
        }
    }
    return s;
}

/// Standard deviation
/// np.std(a)
pub fn std_dev(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    var v = try variance(allocator, a, axis);
    for (0..v.size) |i| {
        v.data[i] = @sqrt(v.data[i]);
    }
    return v;
}

/// Variance
/// np.var(a)
pub fn variance(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    var m = try mean(allocator, a, axis);
    defer m.deinit();

    if (axis == null) {
        // Total variance
        const mean_val = m.data[0];
        var var_sum: f64 = 0;
        for (0..a.size) |i| {
            const diff = a.data[i] - mean_val;
            var_sum += diff * diff;
        }
        const data = try allocator.alloc(f64, 1);
        data[0] = var_sum / @as(f64, @floatFromInt(a.size));
        return ndarray.initWithData(allocator, data, &.{1}, .float64);
    }

    // TODO: Axis-wise variance
    return error.NotImplemented;
}

/// Product of array elements
/// np.prod(a)
pub fn prod(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    if (axis != null) {
        return error.NotImplemented;
    }
    var total: f64 = 1;
    for (0..a.size) |i| {
        total *= a.data[i];
    }
    const data = try allocator.alloc(f64, 1);
    data[0] = total;
    return ndarray.initWithData(allocator, data, &.{1}, .float64);
}

// ============================================================================
// Min/Max Operations
// ============================================================================

/// Maximum value
/// np.max(a) or np.amax(a)
pub fn max(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    if (axis != null) {
        return error.NotImplemented;
    }
    if (a.size == 0) return error.EmptyArray;

    var max_val: f64 = a.data[0];
    for (1..a.size) |i| {
        if (a.data[i] > max_val) {
            max_val = a.data[i];
        }
    }
    const data = try allocator.alloc(f64, 1);
    data[0] = max_val;
    return ndarray.initWithData(allocator, data, &.{1}, .float64);
}

/// Minimum value
/// np.min(a) or np.amin(a)
pub fn min(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    if (axis != null) {
        return error.NotImplemented;
    }
    if (a.size == 0) return error.EmptyArray;

    var min_val: f64 = a.data[0];
    for (1..a.size) |i| {
        if (a.data[i] < min_val) {
            min_val = a.data[i];
        }
    }
    const data = try allocator.alloc(f64, 1);
    data[0] = min_val;
    return ndarray.initWithData(allocator, data, &.{1}, .float64);
}

/// Index of maximum value
/// np.argmax(a)
pub fn argmax(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    if (axis != null) {
        return error.NotImplemented;
    }
    if (a.size == 0) return error.EmptyArray;

    var max_idx: usize = 0;
    var max_val: f64 = a.data[0];
    for (1..a.size) |i| {
        if (a.data[i] > max_val) {
            max_val = a.data[i];
            max_idx = i;
        }
    }
    const data = try allocator.alloc(f64, 1);
    data[0] = @floatFromInt(max_idx);
    return ndarray.initWithData(allocator, data, &.{1}, .float64);
}

/// Index of minimum value
/// np.argmin(a)
pub fn argmin(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    if (axis != null) {
        return error.NotImplemented;
    }
    if (a.size == 0) return error.EmptyArray;

    var min_idx: usize = 0;
    var min_val: f64 = a.data[0];
    for (1..a.size) |i| {
        if (a.data[i] < min_val) {
            min_val = a.data[i];
            min_idx = i;
        }
    }
    const data = try allocator.alloc(f64, 1);
    data[0] = @floatFromInt(min_idx);
    return ndarray.initWithData(allocator, data, &.{1}, .float64);
}

// ============================================================================
// Boolean Reductions
// ============================================================================

/// Test whether all elements are true (non-zero)
/// np.all(a)
pub fn all(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    if (axis != null) {
        return error.NotImplemented;
    }
    for (0..a.size) |i| {
        if (a.data[i] == 0) {
            const data = try allocator.alloc(f64, 1);
            data[0] = 0;
            return ndarray.initWithData(allocator, data, &.{1}, .float64);
        }
    }
    const data = try allocator.alloc(f64, 1);
    data[0] = 1;
    return ndarray.initWithData(allocator, data, &.{1}, .float64);
}

/// Test whether any element is true (non-zero)
/// np.any(a)
pub fn any(allocator: Allocator, a: ndarray, axis: ?usize) !ndarray {
    if (axis != null) {
        return error.NotImplemented;
    }
    for (0..a.size) |i| {
        if (a.data[i] != 0) {
            const data = try allocator.alloc(f64, 1);
            data[0] = 1;
            return ndarray.initWithData(allocator, data, &.{1}, .float64);
        }
    }
    const data = try allocator.alloc(f64, 1);
    data[0] = 0;
    return ndarray.initWithData(allocator, data, &.{1}, .float64);
}

// ============================================================================
// Cumulative Operations
// ============================================================================

/// Cumulative sum
/// np.cumsum(a)
pub fn cumsum(allocator: Allocator, a: ndarray) !ndarray {
    const data = try allocator.alloc(f64, a.size);
    var running: f64 = 0;
    for (0..a.size) |i| {
        running += a.data[i];
        data[i] = running;
    }
    return ndarray.initWithData(allocator, data, &.{a.size}, .float64);
}

/// Cumulative product
/// np.cumprod(a)
pub fn cumprod(allocator: Allocator, a: ndarray) !ndarray {
    const data = try allocator.alloc(f64, a.size);
    var running: f64 = 1;
    for (0..a.size) |i| {
        running *= a.data[i];
        data[i] = running;
    }
    return ndarray.initWithData(allocator, data, &.{a.size}, .float64);
}

// ============================================================================
// Helper Functions
// ============================================================================

fn sumAxis(allocator: Allocator, a: ndarray, axis: usize) !ndarray {
    if (axis >= a.ndim) return error.InvalidAxis;

    // Calculate output shape (remove the axis dimension)
    var new_shape = try allocator.alloc(usize, a.ndim - 1);
    var j: usize = 0;
    for (0..a.ndim) |i| {
        if (i != axis) {
            new_shape[j] = a.shape[i];
            j += 1;
        }
    }

    var result = try creation.zeros(allocator, new_shape);
    allocator.free(new_shape);

    // Simple implementation for 2D case
    if (a.ndim == 2) {
        if (axis == 0) {
            // Sum along rows
            for (0..a.shape[1]) |col| {
                var s: f64 = 0;
                for (0..a.shape[0]) |row| {
                    s += a.get(&.{ row, col });
                }
                result.set(&.{col}, s);
            }
        } else {
            // Sum along columns
            for (0..a.shape[0]) |row| {
                var s: f64 = 0;
                for (0..a.shape[1]) |col| {
                    s += a.get(&.{ row, col });
                }
                result.set(&.{row}, s);
            }
        }
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "sum" {
    const allocator = std.testing.allocator;

    var a = try creation.array(allocator, &.{ 1.0, 2.0, 3.0, 4.0, 5.0 });
    defer a.deinit();

    var s = try sum(allocator, a, null);
    defer s.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 15.0), s.data[0], 0.001);
}

test "mean" {
    const allocator = std.testing.allocator;

    var a = try creation.array(allocator, &.{ 1.0, 2.0, 3.0, 4.0, 5.0 });
    defer a.deinit();

    var m = try mean(allocator, a, null);
    defer m.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 3.0), m.data[0], 0.001);
}

test "max min" {
    const allocator = std.testing.allocator;

    var a = try creation.array(allocator, &.{ 3.0, 1.0, 4.0, 1.0, 5.0, 9.0 });
    defer a.deinit();

    var mx = try max(allocator, a, null);
    defer mx.deinit();
    var mn = try min(allocator, a, null);
    defer mn.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 9.0), mx.data[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), mn.data[0], 0.001);
}

test "argmax argmin" {
    const allocator = std.testing.allocator;

    var a = try creation.array(allocator, &.{ 3.0, 1.0, 4.0, 1.0, 5.0, 9.0 });
    defer a.deinit();

    var amx = try argmax(allocator, a, null);
    defer amx.deinit();
    var amn = try argmin(allocator, a, null);
    defer amn.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 5.0), amx.data[0], 0.001); // index of 9
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), amn.data[0], 0.001); // index of first 1
}

test "cumsum" {
    const allocator = std.testing.allocator;

    var a = try creation.array(allocator, &.{ 1.0, 2.0, 3.0, 4.0 });
    defer a.deinit();

    var c = try cumsum(allocator, a);
    defer c.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 1.0), c.data[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), c.data[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), c.data[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), c.data[3], 0.001);
}
