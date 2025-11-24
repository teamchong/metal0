const std = @import("std");

/// Generic buffer implementation (comptime configurable)
pub fn BufferImpl(comptime Config: type) type {
    return struct {
        const Self = @This();

        // Core buffer data
        buf: *anyopaque,
        len: isize,
        itemsize: isize,
        readonly: bool,

        // Multi-dimensional info (comptime: only if Config.multi_dimensional)
        ndim: if (Config.multi_dimensional) isize else void,
        shape: if (Config.multi_dimensional) ?[]isize else void,
        strides: if (Config.multi_dimensional) ?[]isize else void,

        // Format (comptime: only if Config.has_format)
        format: if (Config.has_format) ?[*:0]const u8 else void,

        allocator: std.mem.Allocator,

        pub fn init(
            allocator: std.mem.Allocator,
            buf: *anyopaque,
            len: isize,
            readonly: bool,
        ) !Self {
            var self = Self{
                .buf = buf,
                .len = len,
                .itemsize = Config.default_itemsize,
                .readonly = readonly,
                .allocator = allocator,
                .ndim = if (Config.multi_dimensional) 1 else {},
                .shape = if (Config.multi_dimensional) null else {},
                .strides = if (Config.multi_dimensional) null else {},
                .format = if (Config.has_format) null else {},
            };

            if (Config.multi_dimensional) {
                // Allocate shape/strides
                self.shape = try allocator.alloc(isize, 1);
                self.shape.?[0] = len;

                self.strides = try allocator.alloc(isize, 1);
                self.strides.?[0] = self.itemsize;
            }

            return self;
        }

        pub fn initMultiDim(
            allocator: std.mem.Allocator,
            buf: *anyopaque,
            ndim: isize,
            shape: []const isize,
            strides: []const isize,
            format: ?[*:0]const u8,
        ) !Self {
            comptime {
                if (!Config.multi_dimensional) {
                    @compileError("Config doesn't support multi-dimensional buffers");
                }
            }

            var self = Self{
                .buf = buf,
                .len = calculateLen(shape),
                .itemsize = Config.default_itemsize,
                .readonly = Config.default_readonly,
                .allocator = allocator,
                .ndim = ndim,
                .shape = null,
                .strides = null,
                .format = if (Config.has_format) format else {},
            };

            // Copy shape
            self.shape = try allocator.alloc(isize, @intCast(ndim));
            @memcpy(self.shape.?, shape);

            // Copy strides
            self.strides = try allocator.alloc(isize, @intCast(ndim));
            @memcpy(self.strides.?, strides);

            return self;
        }

        pub fn isContiguous(self: *const Self, order: u8) bool {
            if (!Config.multi_dimensional) return true;

            // C-contiguous ('C')
            if (order == 'C') {
                var expected_stride = self.itemsize;
                var i: isize = self.ndim - 1;
                while (i >= 0) : (i -= 1) {
                    const idx: usize = @intCast(i);
                    if (self.strides.?[idx] != expected_stride) return false;
                    expected_stride *= self.shape.?[idx];
                }
                return true;
            }

            // F-contiguous ('F')
            if (order == 'F') {
                var expected_stride = self.itemsize;
                var i: isize = 0;
                while (i < self.ndim) : (i += 1) {
                    const idx: usize = @intCast(i);
                    if (self.strides.?[idx] != expected_stride) return false;
                    expected_stride *= self.shape.?[idx];
                }
                return true;
            }

            return false;
        }

        pub fn getItem(self: *Self, index: isize) *anyopaque {
            const offset = if (Config.multi_dimensional and self.strides != null)
                index * self.strides.?[0]
            else
                index * self.itemsize;

            const ptr = @as([*]u8, @ptrCast(self.buf));
            return @ptrCast(ptr + @as(usize, @intCast(offset)));
        }

        pub fn slice(self: *Self, start: isize, end: isize) !Self {
            comptime {
                if (!Config.multi_dimensional) {
                    @compileError("Config doesn't support slicing");
                }
            }

            const new_len = end - start;
            const offset = start * self.itemsize;
            const ptr = @as([*]u8, @ptrCast(self.buf));
            const new_buf = @as(*anyopaque, @ptrCast(ptr + @as(usize, @intCast(offset))));

            var result = Self{
                .buf = new_buf,
                .len = new_len,
                .itemsize = self.itemsize,
                .readonly = self.readonly,
                .allocator = self.allocator,
                .ndim = self.ndim,
                .shape = null,
                .strides = null,
                .format = if (Config.has_format) self.format else {},
            };

            // Copy shape and strides
            result.shape = try self.allocator.alloc(isize, @intCast(self.ndim));
            @memcpy(result.shape.?, self.shape.?);
            result.shape.?[0] = new_len;

            result.strides = try self.allocator.alloc(isize, @intCast(self.ndim));
            @memcpy(result.strides.?, self.strides.?);

            return result;
        }

        pub fn copy(self: *const Self) !Self {
            const new_size = @as(usize, @intCast(self.len * self.itemsize));
            const new_buf = try self.allocator.alloc(u8, new_size);

            const src = @as([*]const u8, @ptrCast(self.buf));
            @memcpy(new_buf, src[0..new_size]);

            var result = Self{
                .buf = @ptrCast(new_buf.ptr),
                .len = self.len,
                .itemsize = self.itemsize,
                .readonly = false, // Copies are always writable
                .allocator = self.allocator,
                .ndim = if (Config.multi_dimensional) self.ndim else {},
                .shape = if (Config.multi_dimensional) null else {},
                .strides = if (Config.multi_dimensional) null else {},
                .format = if (Config.has_format) self.format else {},
            };

            if (Config.multi_dimensional) {
                // Copy shape
                result.shape = try self.allocator.alloc(isize, @intCast(self.ndim));
                @memcpy(result.shape.?, self.shape.?);

                // Copy strides
                result.strides = try self.allocator.alloc(isize, @intCast(self.ndim));
                @memcpy(result.strides.?, self.strides.?);
            }

            return result;
        }

        pub fn makeContiguous(self: *Self, order: u8) !Self {
            if (!Config.multi_dimensional) return self.*;
            if (self.isContiguous(order)) return self.*;

            // Create contiguous copy
            const new_copy = try self.copy();

            // Update strides for requested order
            if (order == 'C') {
                var stride = new_copy.itemsize;
                var i: isize = new_copy.ndim - 1;
                while (i >= 0) : (i -= 1) {
                    const idx: usize = @intCast(i);
                    new_copy.strides.?[idx] = stride;
                    stride *= new_copy.shape.?[idx];
                }
            } else if (order == 'F') {
                var stride = new_copy.itemsize;
                var i: isize = 0;
                while (i < new_copy.ndim) : (i += 1) {
                    const idx: usize = @intCast(i);
                    new_copy.strides.?[idx] = stride;
                    stride *= new_copy.shape.?[idx];
                }
            }

            return new_copy;
        }

        pub fn deinit(self: *Self) void {
            if (Config.multi_dimensional) {
                if (self.shape) |s| self.allocator.free(s);
                if (self.strides) |s| self.allocator.free(s);
            }
        }

        fn calculateLen(shape: []const isize) isize {
            var total: isize = 1;
            for (shape) |dim| {
                total *= dim;
            }
            return total;
        }
    };
}

/// Simple 1D buffer (like bytes)
pub const SimpleBufferConfig = struct {
    pub const multi_dimensional = false;
    pub const has_format = false;
    pub const default_itemsize = 1;
    pub const default_readonly = false;
};

/// Multi-dimensional buffer (like NumPy arrays)
pub const NDArrayBufferConfig = struct {
    pub const multi_dimensional = true;
    pub const has_format = true;
    pub const default_itemsize = 1;
    pub const default_readonly = false;
};

/// Read-only buffer
pub const ReadOnlyBufferConfig = struct {
    pub const multi_dimensional = false;
    pub const has_format = false;
    pub const default_itemsize = 1;
    pub const default_readonly = true;
};

/// Typed buffer configs for common types
pub fn TypedBufferConfig(comptime T: type) type {
    return struct {
        pub const multi_dimensional = false;
        pub const has_format = true;
        pub const default_itemsize = @sizeOf(T);
        pub const default_readonly = false;
    };
}

// Common typed configs
pub const Int32BufferConfig = TypedBufferConfig(i32);
pub const Float64BufferConfig = TypedBufferConfig(f64);
pub const UInt8BufferConfig = TypedBufferConfig(u8);

test "simple buffer init" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Buffer = BufferImpl(SimpleBufferConfig);

    var data = [_]u8{1, 2, 3, 4, 5};
    var buffer = try Buffer.init(allocator, @ptrCast(&data), 5, false);
    defer buffer.deinit();

    try testing.expectEqual(@as(isize, 5), buffer.len);
    try testing.expectEqual(@as(isize, 1), buffer.itemsize);
    try testing.expectEqual(false, buffer.readonly);
}

test "multi-dimensional buffer" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Buffer = BufferImpl(NDArrayBufferConfig);

    var data = [_]i32{1, 2, 3, 4, 5, 6};
    const shape = [_]isize{2, 3};
    const strides = [_]isize{12, 4};

    var buffer = try Buffer.initMultiDim(
        allocator,
        @ptrCast(&data),
        2,
        &shape,
        &strides,
        null
    );
    defer buffer.deinit();

    try testing.expectEqual(@as(isize, 2), buffer.ndim);
    try testing.expectEqual(@as(isize, 6), buffer.len);
}

test "buffer contiguity check" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Buffer = BufferImpl(NDArrayBufferConfig);

    var data = [_]i32{1, 2, 3, 4, 5, 6};
    const shape = [_]isize{2, 3};
    const strides = [_]isize{12, 4}; // C-contiguous for i32 (itemsize=4)

    var buffer = try Buffer.initMultiDim(
        allocator,
        @ptrCast(&data),
        2,
        &shape,
        &strides,
        null
    );
    defer buffer.deinit();

    try testing.expect(buffer.isContiguous('C'));
    try testing.expect(!buffer.isContiguous('F'));
}
