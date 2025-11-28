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

    /// Create empty array (uninitialized) - np.empty(shape)
    pub fn empty(allocator: std.mem.Allocator, shape_spec: []const usize) !*NumpyArray {
        var size: usize = 1;
        for (shape_spec) |dim| {
            size *= dim;
        }

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, size);
        // Don't initialize - that's the point of empty()

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

    /// Create array filled with given value - np.full(shape, fill_value)
    pub fn full(allocator: std.mem.Allocator, shape_spec: []const usize, fill_value: f64) !*NumpyArray {
        const arr = try zeros(allocator, shape_spec);
        @memset(arr.data, fill_value);
        return arr;
    }

    /// Create identity matrix - np.eye(n) or np.identity(n)
    pub fn eye(allocator: std.mem.Allocator, n: usize) !*NumpyArray {
        const shape = [_]usize{ n, n };
        const arr = try zeros(allocator, &shape);

        // Set diagonal to 1
        for (0..n) |i| {
            arr.data[i * n + i] = 1.0;
        }

        return arr;
    }

    /// Create range array - np.arange(start, stop, step)
    pub fn arange(allocator: std.mem.Allocator, start: f64, stop: f64, step: f64) !*NumpyArray {
        // Calculate number of elements
        const range = stop - start;
        const count: usize = @intFromFloat(@ceil(@abs(range / step)));

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, count);

        var val = start;
        for (0..count) |i| {
            data[i] = val;
            val += step;
        }

        const shape = try allocator.alloc(usize, 1);
        shape[0] = count;

        const strides = try allocator.alloc(usize, 1);
        strides[0] = 1;

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = count,
            .allocator = allocator,
        };

        return arr;
    }

    /// Create linearly spaced array - np.linspace(start, stop, num)
    pub fn linspace(allocator: std.mem.Allocator, start: f64, stop: f64, num: usize) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, num);

        if (num == 1) {
            data[0] = start;
        } else {
            const step = (stop - start) / @as(f64, @floatFromInt(num - 1));
            for (0..num) |i| {
                data[i] = start + @as(f64, @floatFromInt(i)) * step;
            }
        }

        const shape = try allocator.alloc(usize, 1);
        shape[0] = num;

        const strides = try allocator.alloc(usize, 1);
        strides[0] = 1;

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = num,
            .allocator = allocator,
        };

        return arr;
    }

    /// Create logarithmically spaced array - np.logspace(start, stop, num)
    pub fn logspace(allocator: std.mem.Allocator, start: f64, stop: f64, num: usize) !*NumpyArray {
        const arr = try linspace(allocator, start, stop, num);

        // Convert to powers of 10
        for (arr.data) |*val| {
            val.* = std.math.pow(f64, 10.0, val.*);
        }

        return arr;
    }

    /// Reshape array - np.reshape(arr, new_shape)
    /// Returns new array with same data but different shape
    pub fn reshape(self: *NumpyArray, allocator: std.mem.Allocator, new_shape: []const usize) !*NumpyArray {
        // Verify total size matches
        var new_size: usize = 1;
        for (new_shape) |dim| {
            new_size *= dim;
        }

        if (new_size != self.size) {
            return error.ShapeMismatch;
        }

        const arr = try allocator.create(NumpyArray);

        // Copy data
        const data = try allocator.alloc(f64, self.size);
        @memcpy(data, self.data);

        const shape = try allocator.dupe(usize, new_shape);
        const strides = try allocator.alloc(usize, new_shape.len);

        // Calculate strides
        var stride: usize = 1;
        var i: usize = new_shape.len;
        while (i > 0) {
            i -= 1;
            strides[i] = stride;
            stride *= new_shape[i];
        }

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Flatten array to 1D - np.flatten() or np.ravel()
    pub fn flatten(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        const shape = [_]usize{self.size};
        return self.reshape(allocator, &shape);
    }

    /// Transpose array - np.transpose() or arr.T
    pub fn transpose(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        if (self.shape.len != 2) {
            return error.InvalidDimension;
        }

        const rows = self.shape[0];
        const cols = self.shape[1];

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        // Transpose: out[j,i] = in[i,j]
        for (0..rows) |i| {
            for (0..cols) |j| {
                data[j * rows + i] = self.data[i * cols + j];
            }
        }

        const shape = try allocator.alloc(usize, 2);
        shape[0] = cols;
        shape[1] = rows;

        const strides = try allocator.alloc(usize, 2);
        strides[0] = rows;
        strides[1] = 1;

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Squeeze - remove dimensions of size 1
    pub fn squeeze(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        // Count non-1 dimensions
        var new_ndim: usize = 0;
        for (self.shape) |dim| {
            if (dim != 1) new_ndim += 1;
        }

        if (new_ndim == 0) new_ndim = 1; // Keep at least 1 dimension

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);
        @memcpy(data, self.data);

        const new_shape = try allocator.alloc(usize, new_ndim);
        const new_strides = try allocator.alloc(usize, new_ndim);

        var idx: usize = 0;
        for (self.shape, self.strides) |dim, stride| {
            if (dim != 1) {
                new_shape[idx] = dim;
                new_strides[idx] = stride;
                idx += 1;
            }
        }

        // Handle all-ones case
        if (idx == 0) {
            new_shape[0] = 1;
            new_strides[0] = 1;
        }

        arr.* = .{
            .data = data,
            .shape = new_shape,
            .strides = new_strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Expand dimensions - add axis of size 1
    pub fn expand_dims(self: *NumpyArray, allocator: std.mem.Allocator, axis: usize) !*NumpyArray {
        const new_ndim = self.shape.len + 1;
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);
        @memcpy(data, self.data);

        const new_shape = try allocator.alloc(usize, new_ndim);
        const new_strides = try allocator.alloc(usize, new_ndim);

        var old_idx: usize = 0;
        for (0..new_ndim) |i| {
            if (i == axis) {
                new_shape[i] = 1;
                new_strides[i] = if (old_idx < self.strides.len) self.strides[old_idx] else 1;
            } else {
                new_shape[i] = self.shape[old_idx];
                new_strides[i] = self.strides[old_idx];
                old_idx += 1;
            }
        }

        arr.* = .{
            .data = data,
            .shape = new_shape,
            .strides = new_strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    // ============================================================================
    // Element-wise operations (return new array)
    // ============================================================================

    /// Element-wise addition
    pub fn add(self: *NumpyArray, other: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        if (self.size != other.size) return error.ShapeMismatch;

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, other.data, 0..) |a, b, i| {
            data[i] = a + b;
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise subtraction
    pub fn subtract(self: *NumpyArray, other: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        if (self.size != other.size) return error.ShapeMismatch;

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, other.data, 0..) |a, b, i| {
            data[i] = a - b;
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise multiplication
    pub fn multiply(self: *NumpyArray, other: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        if (self.size != other.size) return error.ShapeMismatch;

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, other.data, 0..) |a, b, i| {
            data[i] = a * b;
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise division
    pub fn divide(self: *NumpyArray, other: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        if (self.size != other.size) return error.ShapeMismatch;

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, other.data, 0..) |a, b, i| {
            data[i] = a / b;
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Scalar multiplication
    pub fn multiplyScalar(self: *NumpyArray, scalar: f64, allocator: std.mem.Allocator) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, 0..) |a, i| {
            data[i] = a * scalar;
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise power
    pub fn power(self: *NumpyArray, exponent: f64, allocator: std.mem.Allocator) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, 0..) |a, i| {
            data[i] = std.math.pow(f64, a, exponent);
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise sqrt
    pub fn sqrt(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, 0..) |a, i| {
            data[i] = @sqrt(a);
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise exp
    pub fn exp(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, 0..) |a, i| {
            data[i] = @exp(a);
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise log (natural)
    pub fn log(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, 0..) |a, i| {
            data[i] = @log(a);
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise sin
    pub fn sin(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, 0..) |a, i| {
            data[i] = @sin(a);
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise cos
    pub fn cos(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, 0..) |a, i| {
            data[i] = @cos(a);
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Element-wise absolute value
    pub fn abs(self: *NumpyArray, allocator: std.mem.Allocator) !*NumpyArray {
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, self.size);

        for (self.data, 0..) |a, i| {
            data[i] = @abs(a);
        }

        const shape = try allocator.dupe(usize, self.shape);
        const strides = try allocator.dupe(usize, self.strides);

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = self.size,
            .allocator = allocator,
        };

        return arr;
    }

    // ============================================================================
    // Reduction operations (return scalar)
    // ============================================================================

    /// Sum all elements
    pub fn sum(self: *NumpyArray) f64 {
        var total: f64 = 0.0;
        for (self.data) |val| {
            total += val;
        }
        return total;
    }

    /// Product of all elements
    pub fn prod(self: *NumpyArray) f64 {
        var total: f64 = 1.0;
        for (self.data) |val| {
            total *= val;
        }
        return total;
    }

    /// Mean of all elements
    pub fn mean(self: *NumpyArray) f64 {
        return self.sum() / @as(f64, @floatFromInt(self.size));
    }

    /// Standard deviation (named stddev to avoid conflict with std import)
    pub fn stddev(self: *NumpyArray) f64 {
        const m = self.mean();
        var sum_sq: f64 = 0.0;
        for (self.data) |val| {
            const diff = val - m;
            sum_sq += diff * diff;
        }
        return @sqrt(sum_sq / @as(f64, @floatFromInt(self.size)));
    }

    /// Variance
    pub fn variance(self: *NumpyArray) f64 {
        const s = self.stddev();
        return s * s;
    }

    /// Minimum value
    pub fn min(self: *NumpyArray) f64 {
        var result = self.data[0];
        for (self.data[1..]) |val| {
            if (val < result) result = val;
        }
        return result;
    }

    /// Maximum value
    pub fn max(self: *NumpyArray) f64 {
        var result = self.data[0];
        for (self.data[1..]) |val| {
            if (val > result) result = val;
        }
        return result;
    }

    /// Index of minimum value
    pub fn argmin(self: *NumpyArray) usize {
        var min_idx: usize = 0;
        var min_val = self.data[0];
        for (self.data[1..], 1..) |val, i| {
            if (val < min_val) {
                min_val = val;
                min_idx = i;
            }
        }
        return min_idx;
    }

    /// Index of maximum value
    pub fn argmax(self: *NumpyArray) usize {
        var max_idx: usize = 0;
        var max_val = self.data[0];
        for (self.data[1..], 1..) |val, i| {
            if (val > max_val) {
                max_val = val;
                max_idx = i;
            }
        }
        return max_idx;
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

    /// Slice array with start:end (1D) - returns new array
    pub fn sliceRange(allocator: std.mem.Allocator, self: *NumpyArray, start: usize, end: usize) !*NumpyArray {
        const actual_start = @min(start, self.size);
        const actual_end = @min(end, self.size);

        if (actual_start >= actual_end) {
            // Return empty array
            return zeros(allocator, &[_]usize{0});
        }

        const new_size = actual_end - actual_start;
        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, new_size);
        @memcpy(data, self.data[actual_start..actual_end]);

        const shape = try allocator.alloc(usize, 1);
        shape[0] = new_size;

        const strides = try allocator.alloc(usize, 1);
        strides[0] = 1;

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = new_size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Slice array with step (1D) - returns new array
    /// Handles both positive and negative steps
    pub fn sliceWithStep(allocator: std.mem.Allocator, self: *NumpyArray, start: usize, end_i64: i64, step: i64) !*NumpyArray {
        if (step == 0) {
            return error.ValueError;
        }

        // Calculate result size
        var count: usize = 0;
        if (step > 0) {
            var i: usize = start;
            const step_u: usize = @intCast(step);
            while (@as(i64, @intCast(i)) < end_i64 and i < self.size) : (i += step_u) {
                count += 1;
            }
        } else {
            var i: i64 = @intCast(start);
            while (i > end_i64 and i >= 0) : (i += step) {
                count += 1;
            }
        }

        if (count == 0) {
            return zeros(allocator, &[_]usize{0});
        }

        const arr = try allocator.create(NumpyArray);
        const data = try allocator.alloc(f64, count);

        // Fill data
        var idx: usize = 0;
        if (step > 0) {
            var i: usize = start;
            const step_u: usize = @intCast(step);
            while (@as(i64, @intCast(i)) < end_i64 and i < self.size) : (i += step_u) {
                data[idx] = self.data[i];
                idx += 1;
            }
        } else {
            var i: i64 = @intCast(start);
            while (i > end_i64 and i >= 0) : (i += step) {
                data[idx] = self.data[@intCast(i)];
                idx += 1;
            }
        }

        const shape = try allocator.alloc(usize, 1);
        shape[0] = count;

        const strides = try allocator.alloc(usize, 1);
        strides[0] = 1;

        arr.* = .{
            .data = data,
            .shape = shape,
            .strides = strides,
            .size = count,
            .allocator = allocator,
        };

        return arr;
    }

    /// Clean up resources
    pub fn deinit(self: *NumpyArray) void {
        self.allocator.free(self.data);
        self.allocator.free(self.shape);
        self.allocator.free(self.strides);
        self.allocator.destroy(self);
    }
};

// ============================================================================
// Boolean Array for comparison operations
// ============================================================================

/// Boolean array data structure (result of comparison operations)
pub const BoolArray = struct {
    /// Raw boolean data buffer
    data: []bool,

    /// Shape of the array (dimensions)
    shape: []const usize,

    /// Number of elements
    size: usize,

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    /// Create BoolArray from comparison operation
    pub fn create(allocator: std.mem.Allocator, source: *NumpyArray) !*BoolArray {
        const arr = try allocator.create(BoolArray);
        const data = try allocator.alloc(bool, source.size);

        const shape = try allocator.dupe(usize, source.shape);

        arr.* = .{
            .data = data,
            .shape = shape,
            .size = source.size,
            .allocator = allocator,
        };

        return arr;
    }

    /// Count true values
    pub fn countTrue(self: *BoolArray) usize {
        var count: usize = 0;
        for (self.data) |val| {
            if (val) count += 1;
        }
        return count;
    }

    /// Any - returns true if any element is true
    pub fn any(self: *BoolArray) bool {
        for (self.data) |val| {
            if (val) return true;
        }
        return false;
    }

    /// All - returns true if all elements are true
    pub fn all(self: *BoolArray) bool {
        for (self.data) |val| {
            if (!val) return false;
        }
        return true;
    }

    /// Clean up resources
    pub fn deinit(self: *BoolArray) void {
        self.allocator.free(self.data);
        self.allocator.free(self.shape);
        self.allocator.destroy(self);
    }
};

/// Comparison operators for arrays
pub const CompareOp = enum {
    eq, // ==
    ne, // !=
    lt, // <
    le, // <=
    gt, // >
    ge, // >=
};

/// Element-wise comparison: arr op scalar
pub fn compareScalar(arr: *NumpyArray, scalar: f64, op: CompareOp, allocator: std.mem.Allocator) !*BoolArray {
    const result = try BoolArray.create(allocator, arr);

    for (arr.data, 0..) |val, i| {
        result.data[i] = switch (op) {
            .eq => val == scalar,
            .ne => val != scalar,
            .lt => val < scalar,
            .le => val <= scalar,
            .gt => val > scalar,
            .ge => val >= scalar,
        };
    }

    return result;
}

/// Element-wise comparison: arr1 op arr2
pub fn compareArrays(arr1: *NumpyArray, arr2: *NumpyArray, op: CompareOp, allocator: std.mem.Allocator) !*BoolArray {
    if (arr1.size != arr2.size) return error.ShapeMismatch;

    const result = try BoolArray.create(allocator, arr1);

    for (arr1.data, arr2.data, 0..) |a, b, i| {
        result.data[i] = switch (op) {
            .eq => a == b,
            .ne => a != b,
            .lt => a < b,
            .le => a <= b,
            .gt => a > b,
            .ge => a >= b,
        };
    }

    return result;
}

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

/// Wrap BoolArray in PyObject
pub fn createBoolPyObject(allocator: std.mem.Allocator, array: *BoolArray) !*runtime.PyObject {
    const obj = try allocator.create(runtime.PyObject);
    obj.* = .{
        .ref_count = 1,
        .type_id = .bool_array,
        .data = @ptrCast(array),
    };
    return obj;
}

/// Extract BoolArray from PyObject
pub fn extractBoolArray(obj: *runtime.PyObject) !*BoolArray {
    if (obj.type_id != .bool_array) {
        return error.TypeError;
    }
    return @ptrCast(@alignCast(obj.data));
}

/// Boolean indexing: arr[mask] - filter array by boolean mask
/// Returns new array with only elements where mask is true
pub fn booleanIndex(arr: *NumpyArray, mask: *BoolArray, allocator: std.mem.Allocator) !*NumpyArray {
    if (arr.size != mask.size) return error.ShapeMismatch;

    // Count true values to determine result size
    const count = mask.countTrue();

    if (count == 0) {
        return NumpyArray.zeros(allocator, &[_]usize{0});
    }

    const result = try allocator.create(NumpyArray);
    const data = try allocator.alloc(f64, count);

    // Copy matching elements
    var idx: usize = 0;
    for (arr.data, mask.data) |val, include| {
        if (include) {
            data[idx] = val;
            idx += 1;
        }
    }

    const shape = try allocator.alloc(usize, 1);
    shape[0] = count;

    const strides = try allocator.alloc(usize, 1);
    strides[0] = 1;

    result.* = .{
        .data = data,
        .shape = shape,
        .strides = strides,
        .size = count,
        .allocator = allocator,
    };

    return result;
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
