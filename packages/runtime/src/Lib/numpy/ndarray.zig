//! NumPy-compatible N-dimensional Array
//!
//! Core ndarray type with shape, strides, and dtype support.
//! Supports views (zero-copy slicing) and contiguous/non-contiguous layouts.

const std = @import("std");
const Allocator = std.mem.Allocator;
const dtype_mod = @import("dtype.zig");
pub const DType = dtype_mod.DType;

/// N-dimensional array (NumPy compatible)
pub const ndarray = struct {
    /// Raw data storage (always f64 internally for simplicity, cast on access)
    data: []f64,

    /// Shape of the array (e.g., [3, 4] for 3x4 matrix)
    shape: []usize,

    /// Strides in elements (not bytes) per dimension
    strides: []usize,

    /// Data type
    dtype: DType,

    /// Memory allocator
    allocator: Allocator,

    /// Number of dimensions
    ndim: usize,

    /// Total number of elements
    size: usize,

    /// Whether data is contiguous in memory (C-order)
    is_contiguous: bool,

    /// Whether this array owns its data (false for views)
    owns_data: bool,

    const Self = @This();

    // ========================================================================
    // Initialization
    // ========================================================================

    /// Create a new ndarray with given shape, uninitialized data
    pub fn init(allocator: Allocator, shape: []const usize, dtype: DType) !Self {
        const ndim = shape.len;
        const size = computeSize(shape);

        // Allocate data
        const data = try allocator.alloc(f64, size);

        // Allocate and copy shape
        const owned_shape = try allocator.alloc(usize, ndim);
        @memcpy(owned_shape, shape);

        // Compute strides (C-order: row-major)
        const strides = try allocator.alloc(usize, ndim);
        computeStrides(shape, strides);

        return Self{
            .data = data,
            .shape = owned_shape,
            .strides = strides,
            .dtype = dtype,
            .allocator = allocator,
            .ndim = ndim,
            .size = size,
            .is_contiguous = true,
            .owns_data = true,
        };
    }

    /// Create from existing data (takes ownership)
    pub fn initWithData(allocator: Allocator, data: []f64, shape: []const usize, dtype: DType) !Self {
        const ndim = shape.len;
        const size = computeSize(shape);

        if (data.len != size) {
            return error.ShapeMismatch;
        }

        // Allocate and copy shape
        const owned_shape = try allocator.alloc(usize, ndim);
        @memcpy(owned_shape, shape);

        // Compute strides
        const strides = try allocator.alloc(usize, ndim);
        computeStrides(shape, strides);

        return Self{
            .data = data,
            .shape = owned_shape,
            .strides = strides,
            .dtype = dtype,
            .allocator = allocator,
            .ndim = ndim,
            .size = size,
            .is_contiguous = true,
            .owns_data = true,
        };
    }

    /// Create a view (does not own data)
    pub fn initView(
        data: []f64,
        shape: []usize,
        strides: []usize,
        dtype: DType,
        allocator: Allocator,
    ) Self {
        return Self{
            .data = data,
            .shape = shape,
            .strides = strides,
            .dtype = dtype,
            .allocator = allocator,
            .ndim = shape.len,
            .size = computeSize(shape),
            .is_contiguous = false, // Views are often non-contiguous
            .owns_data = false,
        };
    }

    /// Free array memory
    pub fn deinit(self: *Self) void {
        if (self.owns_data) {
            self.allocator.free(self.data);
        }
        self.allocator.free(self.shape);
        self.allocator.free(self.strides);
    }

    // ========================================================================
    // Properties (Python-style)
    // ========================================================================

    /// Get shape (arr.shape in Python)
    pub fn getShape(self: Self) []const usize {
        return self.shape;
    }

    /// Get dtype (arr.dtype in Python)
    pub fn getDtype(self: Self) DType {
        return self.dtype;
    }

    /// Get number of dimensions (arr.ndim in Python)
    pub fn getNdim(self: Self) usize {
        return self.ndim;
    }

    /// Get total number of elements (arr.size in Python)
    pub fn getSize(self: Self) usize {
        return self.size;
    }

    /// Get strides (arr.strides in Python) - in elements, not bytes
    pub fn getStrides(self: Self) []const usize {
        return self.strides;
    }

    /// Get number of bytes (arr.nbytes in Python)
    pub fn getNbytes(self: Self) usize {
        return self.size * self.dtype.size();
    }

    // ========================================================================
    // Element Access
    // ========================================================================

    /// Get element at indices (supports up to 4D)
    pub fn get(self: Self, indices: []const usize) f64 {
        const offset = self.computeOffset(indices);
        return self.data[offset];
    }

    /// Set element at indices
    pub fn set(self: *Self, indices: []const usize, value: f64) void {
        const offset = self.computeOffset(indices);
        self.data[offset] = value;
    }

    /// Compute linear offset from multi-dimensional indices
    fn computeOffset(self: Self, indices: []const usize) usize {
        var offset: usize = 0;
        for (indices, 0..) |idx, dim| {
            offset += idx * self.strides[dim];
        }
        return offset;
    }

    // ========================================================================
    // Iteration
    // ========================================================================

    /// Iterator for flat traversal
    pub const Iterator = struct {
        arr: *const ndarray,
        index: usize,

        pub fn next(self: *Iterator) ?f64 {
            if (self.index >= self.arr.size) return null;
            const value = self.arr.data[self.index];
            self.index += 1;
            return value;
        }
    };

    /// Get flat iterator
    pub fn iter(self: *const Self) Iterator {
        return Iterator{ .arr = self, .index = 0 };
    }

    // ========================================================================
    // Copy Operations
    // ========================================================================

    /// Create a copy of this array
    pub fn copy(self: Self) !Self {
        const new_arr = try init(self.allocator, self.shape, self.dtype);
        @memcpy(new_arr.data, self.data);
        return new_arr;
    }

    /// Copy data from another array
    pub fn copyFrom(self: *Self, other: Self) void {
        @memcpy(self.data, other.data);
    }

    // ========================================================================
    // Utilities
    // ========================================================================

    /// Fill array with a value
    pub fn fill(self: *Self, value: f64) void {
        @memset(self.data, value);
    }

    /// Convert to string representation
    pub fn toString(self: Self, allocator: Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        const writer = result.writer();

        try writer.writeAll("array(");

        // Simple 1D/2D printing for now
        if (self.ndim == 1) {
            try writer.writeAll("[");
            for (0..self.shape[0]) |i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{d:.4}", .{self.get(&.{i})});
            }
            try writer.writeAll("]");
        } else if (self.ndim == 2) {
            try writer.writeAll("[");
            for (0..self.shape[0]) |i| {
                if (i > 0) try writer.writeAll(",\n       ");
                try writer.writeAll("[");
                for (0..self.shape[1]) |j| {
                    if (j > 0) try writer.writeAll(", ");
                    try writer.print("{d:.4}", .{self.get(&.{ i, j })});
                }
                try writer.writeAll("]");
            }
            try writer.writeAll("]");
        } else {
            try writer.print("<{d}D array with {d} elements>", .{ self.ndim, self.size });
        }

        try writer.print(", dtype={s})", .{self.dtype.name()});

        return result.toOwnedSlice();
    }

    // ========================================================================
    // Static Helpers
    // ========================================================================

    /// Compute total size from shape
    pub fn computeSize(shape: []const usize) usize {
        var size: usize = 1;
        for (shape) |dim| {
            size *= dim;
        }
        return size;
    }

    /// Compute C-order (row-major) strides from shape
    pub fn computeStrides(shape: []const usize, strides: []usize) void {
        if (shape.len == 0) return;

        var stride: usize = 1;
        var i: usize = shape.len;
        while (i > 0) {
            i -= 1;
            strides[i] = stride;
            stride *= shape[i];
        }
    }
};

// ============================================================================
// Slice type for indexing
// ============================================================================

/// Represents a slice range (start:stop:step)
pub const Slice = struct {
    start: ?isize = null, // null = from beginning
    stop: ?isize = null, // null = to end
    step: isize = 1,

    /// Create slice from start to stop
    pub fn init(start: isize, stop: isize) Slice {
        return .{ .start = start, .stop = stop };
    }

    /// Create slice with step
    pub fn initWithStep(start: isize, stop: isize, step: isize) Slice {
        return .{ .start = start, .stop = stop, .step = step };
    }

    /// Create "all" slice (equivalent to :)
    pub fn all() Slice {
        return .{};
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ndarray init" {
    const allocator = std.testing.allocator;

    var arr = try ndarray.init(allocator, &.{ 3, 4 }, .float64);
    defer arr.deinit();

    try std.testing.expectEqual(@as(usize, 2), arr.ndim);
    try std.testing.expectEqual(@as(usize, 12), arr.size);
    try std.testing.expectEqual(@as(usize, 3), arr.shape[0]);
    try std.testing.expectEqual(@as(usize, 4), arr.shape[1]);
}

test "ndarray strides" {
    const allocator = std.testing.allocator;

    var arr = try ndarray.init(allocator, &.{ 2, 3, 4 }, .float64);
    defer arr.deinit();

    // C-order strides: [12, 4, 1]
    try std.testing.expectEqual(@as(usize, 12), arr.strides[0]);
    try std.testing.expectEqual(@as(usize, 4), arr.strides[1]);
    try std.testing.expectEqual(@as(usize, 1), arr.strides[2]);
}

test "ndarray get/set" {
    const allocator = std.testing.allocator;

    var arr = try ndarray.init(allocator, &.{ 2, 3 }, .float64);
    defer arr.deinit();

    arr.set(&.{ 0, 0 }, 1.0);
    arr.set(&.{ 1, 2 }, 5.0);

    try std.testing.expectEqual(@as(f64, 1.0), arr.get(&.{ 0, 0 }));
    try std.testing.expectEqual(@as(f64, 5.0), arr.get(&.{ 1, 2 }));
}

test "ndarray fill" {
    const allocator = std.testing.allocator;

    var arr = try ndarray.init(allocator, &.{5}, .float64);
    defer arr.deinit();

    arr.fill(3.14);

    for (0..5) |i| {
        try std.testing.expectEqual(@as(f64, 3.14), arr.get(&.{i}));
    }
}
