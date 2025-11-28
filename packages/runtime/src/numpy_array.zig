/// NumPy array implementation for PyAOT
/// Provides NumPy-compatible arrays with C BLAS interoperability
const std = @import("std");
const runtime = @import("runtime.zig");

/// NumPy array data structure
/// Compatible with C NumPy API and BLAS libraries
pub const NumpyArray = struct {
    /// Raw data buffer (contiguous memory)
    data: []f64,

    /// Shape of the array (dimensions)
    /// Example: [3, 4] for 3x4 matrix
    shape: []const usize,

    /// Strides for memory layout
    /// Example: [4, 1] means rows are 4 elements apart, columns are 1 element apart
    strides: []const usize,

    /// Number of elements (product of shape)
    size: usize,

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    /// Create 1D array from slice
    pub fn fromSlice(allocator: std.mem.Allocator, data: []const f64) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);

        // Copy data
        const data_copy = try allocator.alloc(f64, data.len);
        @memcpy(data_copy, data);

        // Allocate shape and strides
        const shape = try allocator.alloc(usize, 1);
        shape[0] = data.len;

        const strides = try allocator.alloc(usize, 1);
        strides[0] = 1;

        arr.* = .{
            .data = data_copy,
            .shape = shape,
            .strides = strides,
            .size = data.len,
            .allocator = allocator,
        };

        return arr;
    }

    /// Create 1D array from owned slice (takes ownership, no copy)
    pub fn fromOwnedSlice(allocator: std.mem.Allocator, data: []f64) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);

        // Allocate shape and strides
        const shape = try allocator.alloc(usize, 1);
        shape[0] = data.len;

        const strides = try allocator.alloc(usize, 1);
        strides[0] = 1;

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = data.len,
            .allocator = allocator,
        };

        return arr;
    }

    /// Create 2D array from shape
    pub fn create2D(allocator: std.mem.Allocator, rows: usize, cols: usize) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);

        const size = rows * cols;
        const data = try allocator.alloc(f64, size);
        @memset(data, 0);

        const shape = try allocator.alloc(usize, 2);
        shape[0] = rows;
        shape[1] = cols;

        const strides = try allocator.alloc(usize, 2);
        strides[0] = cols; // Row stride
        strides[1] = 1; // Column stride

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Create array filled with zeros
    pub fn zeros(allocator: std.mem.Allocator, shape_spec: []const usize) !*NumpyArray {
        var size: usize = 1;
        for (shape_spec) |dim| {
            size *= dim;
        }

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, size);
        @memset(data, 0);

        const shape = try allocator.dupe(usize, shape_spec);
        const strides = try allocator.alloc(usize, shape_spec.len);

        // Calculate strides (C-contiguous order)
        var stride: usize = 1;
        var i: usize = shape_spec.len;
        while (i > 0) {
            i -= 1;
            strides[i] = stride;
            stride *= shape_spec[i];
        }

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Create array filled with ones
    pub fn ones(allocator: std.mem.Allocator, shape_spec: []const usize) !*NumpyArray {
        const arr = try zeros(allocator, shape_spec);
        @memset(arr.data, 1.0);
        return arr;
    }

    /// Get element at index (1D only for now)
    pub fn get(self: *const NumpyArray, index: usize) f64 {
        return self.data[index];
    }

    /// Set element at index (1D only for now)
    pub fn set(self: *NumpyArray, index: usize, value: f64) void {
        self.data[index] = value;
    }

    /// Get element at 2D index
    pub fn get2D(self: *const NumpyArray, row: usize, col: usize) f64 {
        const index = row * self.strides[0] + col * self.strides[1];
        return self.data[index];
    }

    /// Set element at 2D index
    pub fn set2D(self: *NumpyArray, row: usize, col: usize, value: f64) void {
        const index = row * self.strides[0] + col * self.strides[1];
        self.data[index] = value;
    }

    /// Clean up resources
    pub fn deinit(self: *NumpyArray) void {
        self.allocator.free(self.data);
        self.allocator.free(self.shape);
        self.allocator.free(self.strides);
        self.allocator.destroy(self);
    }
};

/// Wrap NumpyArray in PyObject
pub fn createPyObject(allocator: std.mem.Allocator, array: *NumpyArray) !*runtime.PyObject {
    const obj = try allocator.create(runtime.PyObject);
    obj.* = .{
        .ref_count = 1,
        .type_id = .numpy_array,
        .data = @ptrCast(array),
    };
    return obj;
}

/// Extract NumpyArray from PyObject
pub fn extractArray(obj: *runtime.PyObject) !*NumpyArray {
    if (obj.type_id != .numpy_array) {
        return error.TypeError;
    }
    return @ptrCast(@alignCast(obj.data));
}

// Tests
test "create 1D array from slice" {
    const allocator = std.testing.allocator;

    const data = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const arr = try NumpyArray.fromSlice(allocator, &data);
    defer arr.deinit();

    try std.testing.expectEqual(@as(usize, 5), arr.size);
    try std.testing.expectEqual(@as(usize, 1), arr.shape.len);
    try std.testing.expectEqual(@as(usize, 5), arr.shape[0]);
    try std.testing.expectEqual(@as(f64, 3.0), arr.get(2));
}

test "create 2D array" {
    const allocator = std.testing.allocator;

    const arr = try NumpyArray.create2D(allocator, 3, 4);
    defer arr.deinit();

    try std.testing.expectEqual(@as(usize, 12), arr.size);
    try std.testing.expectEqual(@as(usize, 2), arr.shape.len);
    try std.testing.expectEqual(@as(usize, 3), arr.shape[0]);
    try std.testing.expectEqual(@as(usize, 4), arr.shape[1]);

    arr.set2D(1, 2, 42.0);
    try std.testing.expectEqual(@as(f64, 42.0), arr.get2D(1, 2));
}

test "zeros and ones" {
    const allocator = std.testing.allocator;

    const shape = [_]usize{ 2, 3 };
    const arr_zeros = try NumpyArray.zeros(allocator, &shape);
    defer arr_zeros.deinit();

    try std.testing.expectEqual(@as(f64, 0.0), arr_zeros.get(0));

    const arr_ones = try NumpyArray.ones(allocator, &shape);
    defer arr_ones.deinit();

    try std.testing.expectEqual(@as(f64, 1.0), arr_ones.get(0));
}

test "wrap in PyObject" {
    const allocator = std.testing.allocator;

    const data = [_]f64{ 1.0, 2.0, 3.0 };
    const arr = try NumpyArray.fromSlice(allocator, &data);

    const obj = try createPyObject(allocator, arr);
    defer {
        const extracted = extractArray(obj) catch unreachable;
        extracted.deinit();
        allocator.destroy(obj);
    }

    try std.testing.expectEqual(runtime.PyObject.TypeId.numpy_array, obj.type_id);

    const extracted = try extractArray(obj);
    try std.testing.expectEqual(@as(usize, 3), extracted.size);
}
