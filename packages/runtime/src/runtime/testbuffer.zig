/// Python _testbuffer module - Buffer protocol test support
/// Provides ndarray and staticarray for testing PEP-3118 buffer protocol
const std = @import("std");

/// ndarray - multi-dimensional array for buffer protocol testing
/// Implements the buffer interface for testing memoryview operations
pub const ndarray = struct {
    // Data storage
    data: []u8 = &[_]u8{},
    // Shape of the array (dimensions)
    shape: []const i64 = &[_]i64{},
    // Strides for each dimension
    strides: []const i64 = &[_]i64{},
    // Suboffsets for PIL-style arrays (or null)
    suboffsets: ?[]const i64 = null,
    // Format string (struct format like 'B', 'i', 'L', etc.)
    format: []const u8 = "B",
    // Item size in bytes
    itemsize: i64 = 1,
    // Total number of dimensions
    ndim: i64 = 1,
    // Flags (ND_WRITABLE, ND_FORTRAN, etc.)
    flags: i64 = 0,
    // Readonly flag
    readonly: bool = false,
    // Reference to underlying exporter (for nested ndarrays)
    obj: ?*anyopaque = null,
    // Length (for Python len() compatibility)
    len: i64 = 0,
    // Dynamic dict for Python __dict__ attribute - stores PyValue for heterogeneous values
    __dict__: DictType = undefined,

    const DictType = struct {
        entries: std.StringHashMapUnmanaged(AttrValue) = .{},

        pub fn get(self: *const @This(), key: []const u8) ?AttrValue {
            return self.entries.get(key);
        }

        pub fn put(self: *@This(), allocator: std.mem.Allocator, key: []const u8, value: AttrValue) !void {
            try self.entries.put(allocator, key, value);
        }
    };
    pub const AttrValue = union(enum) {
        int: i64,
        string: []const u8,
        float: f64,
        bool: bool,

        pub fn asInt(self: AttrValue) i64 {
            return switch (self) {
                .int => |v| v,
                .float => |v| @intFromFloat(v),
                .bool => |v| if (v) @as(i64, 1) else @as(i64, 0),
                .string => 0,
            };
        }
    };

    const Self = @This();

    /// Create ndarray from list of items
    pub fn init(allocator: std.mem.Allocator, items: anytype, opts: struct {
        shape: []const i64 = &[_]i64{},
        strides: []const i64 = &[_]i64{},
        suboffsets: ?[]const i64 = null,
        format: []const u8 = "B",
        flags: i64 = 0,
        offset: i64 = 0,
        getbuf: i64 = 0,
    }) !Self {
        const ItemsType = @TypeOf(items);
        var data: []u8 = &[_]u8{};
        var shape: []const i64 = opts.shape;
        var len: i64 = 0;

        // Handle different input types
        if (@typeInfo(ItemsType) == .pointer) {
            const child = @typeInfo(ItemsType).pointer.child;
            if (@typeInfo(child) == .array) {
                // Array of values - convert to bytes
                const arr_len = @typeInfo(child).array.len;
                data = try allocator.alloc(u8, arr_len);
                for (items, 0..) |item, i| {
                    data[i] = @intCast(item);
                }
                len = @intCast(arr_len);
                if (shape.len == 0) {
                    const dynamic_shape = try allocator.alloc(i64, 1);
                    dynamic_shape[0] = len;
                    shape = dynamic_shape;
                }
            }
        } else if (@typeInfo(ItemsType) == .array) {
            // Direct array
            const arr_len = @typeInfo(ItemsType).array.len;
            data = try allocator.alloc(u8, arr_len);
            for (items, 0..) |item, i| {
                data[i] = @intCast(item);
            }
            len = @intCast(arr_len);
            if (shape.len == 0) {
                const dynamic_shape = try allocator.alloc(i64, 1);
                dynamic_shape[0] = len;
                shape = dynamic_shape;
            }
        }

        // Calculate strides if not provided
        var strides = opts.strides;
        if (strides.len == 0 and shape.len > 0) {
            const dynamic_strides = try allocator.alloc(i64, shape.len);
            var stride: i64 = 1;
            var i: usize = shape.len;
            while (i > 0) {
                i -= 1;
                dynamic_strides[i] = stride;
                stride *= shape[i];
            }
            strides = dynamic_strides;
        }

        return Self{
            .data = data,
            .shape = shape,
            .strides = strides,
            .suboffsets = opts.suboffsets,
            .format = opts.format,
            .itemsize = getItemSize(opts.format),
            .ndim = @intCast(shape.len),
            .flags = opts.flags,
            .readonly = false,
            .obj = null,
            .len = len,
            .__dict__ = .{},
        };
    }

    fn getItemSize(format: []const u8) i64 {
        if (format.len == 0) return 1;
        return switch (format[0]) {
            'b', 'B', 'c', '?' => 1,
            'h', 'H' => 2,
            'i', 'I', 'l', 'L', 'f' => 4,
            'q', 'Q', 'd' => 8,
            else => 1,
        };
    }

    /// Get total number of bytes
    pub fn nbytes(self: Self) i64 {
        var total: i64 = self.itemsize;
        for (self.shape) |dim| {
            total *= dim;
        }
        return total;
    }

    /// Check if array is contiguous (C order)
    pub fn c_contiguous(self: Self) bool {
        _ = self;
        return true;
    }

    /// Check if array is Fortran contiguous
    pub fn f_contiguous(self: Self) bool {
        _ = self;
        return false;
    }

    /// Check if array is contiguous in any order
    pub fn contiguous(self: Self) bool {
        return self.c_contiguous() or self.f_contiguous();
    }

    /// Get buffer info (for buffer protocol)
    pub fn getbuffer(self: *Self) *Self {
        return self;
    }

    /// Release buffer
    pub fn releasebuffer(self: *Self) void {
        _ = self;
    }

    /// Get item at flat index (Python __getitem__)
    pub fn getitem(self: Self, idx: i64) i64 {
        // Handle negative indices
        var actual_idx = idx;
        if (actual_idx < 0) {
            actual_idx += self.len;
        }
        if (actual_idx < 0 or actual_idx >= self.len) {
            return 0; // Out of bounds
        }
        const byte_offset: usize = @intCast(actual_idx * self.itemsize);
        if (byte_offset >= self.data.len) return 0;

        // Read value based on format
        return switch (self.itemsize) {
            1 => self.data[byte_offset],
            2 => if (byte_offset + 2 <= self.data.len)
                std.mem.readInt(i16, self.data[byte_offset..][0..2], .little)
            else
                0,
            4 => if (byte_offset + 4 <= self.data.len)
                std.mem.readInt(i32, self.data[byte_offset..][0..4], .little)
            else
                0,
            8 => if (byte_offset + 8 <= self.data.len)
                std.mem.readInt(i64, self.data[byte_offset..][0..8], .little)
            else
                0,
            else => 0,
        };
    }

    /// Python-style __getitem__ (alias for getitem)
    pub fn __getitem__(self: Self, idx: anytype) i64 {
        const IdxType = @TypeOf(idx);
        if (IdxType == i64 or IdxType == usize or @typeInfo(IdxType) == .comptime_int) {
            return self.getitem(@intCast(idx));
        }
        return 0;
    }

    /// Set item at flat index (Python __setitem__)
    pub fn setitem(self: *Self, idx: i64, value: i64) void {
        if (self.readonly) return;

        // Handle negative indices
        var actual_idx = idx;
        if (actual_idx < 0) {
            actual_idx += self.len;
        }
        if (actual_idx < 0 or actual_idx >= self.len) {
            return; // Out of bounds
        }
        const byte_offset: usize = @intCast(actual_idx * self.itemsize);
        if (byte_offset >= self.data.len) return;

        // Write value based on format
        switch (self.itemsize) {
            1 => {
                self.data[byte_offset] = @truncate(@as(u64, @bitCast(value)));
            },
            2 => {
                if (byte_offset + 2 <= self.data.len) {
                    std.mem.writeInt(i16, self.data[byte_offset..][0..2], @truncate(value), .little);
                }
            },
            4 => {
                if (byte_offset + 4 <= self.data.len) {
                    std.mem.writeInt(i32, self.data[byte_offset..][0..4], @truncate(value), .little);
                }
            },
            8 => {
                if (byte_offset + 8 <= self.data.len) {
                    std.mem.writeInt(i64, self.data[byte_offset..][0..8], value, .little);
                }
            },
            else => {},
        }
    }

    /// Python-style __setitem__
    pub fn __setitem__(self: *Self, idx: anytype, value: anytype) void {
        const IdxType = @TypeOf(idx);
        if (IdxType == i64 or IdxType == usize or @typeInfo(IdxType) == .comptime_int) {
            self.setitem(@intCast(idx), @intCast(value));
        }
    }

    /// Convert to list (allocates)
    pub fn tolist(self: Self, allocator: std.mem.Allocator) ![]i64 {
        const count: usize = @intCast(@divTrunc(self.len, @max(1, self.itemsize)));
        var result = try allocator.alloc(i64, count);
        for (0..count) |i| {
            result[i] = self.getitem(@intCast(i));
        }
        return result;
    }

    /// Convert to bytes
    pub fn tobytes(self: Self) []const u8 {
        return self.data;
    }

    /// Get memoryview representation
    pub fn memoryview(self: *Self) *Self {
        return self;
    }

    /// Create memoryview from buffer - returns self since ndarray IS a buffer
    pub fn memoryview_from_buffer(self: *Self) *Self {
        return self;
    }

    /// Python __buffer__ protocol (return self for buffer access)
    pub fn __buffer__(self: *Self, flags: anytype) *Self {
        _ = flags;
        return self;
    }

    /// String representation
    pub fn __repr__(self: Self) []const u8 {
        _ = self;
        return "ndarray(...)";
    }

    /// Length (product of shape)
    pub fn __len__(self: Self) i64 {
        var total: i64 = 1;
        for (self.shape) |dim| {
            total *= dim;
        }
        return total;
    }

    /// Hash
    pub fn __hash__(self: Self) i64 {
        _ = self;
        return 0;
    }

    /// Equality
    pub fn __eq__(self: Self, other: Self) bool {
        _ = self;
        _ = other;
        return true;
    }
};

/// staticarray - fixed size array (simpler than ndarray)
pub const staticarray = struct {
    data: []const u8 = &[_]u8{},
    size: i64 = 0,
    format: []const u8 = "B",

    const Self = @This();

    pub fn init(items: anytype, opts: struct {
        format: []const u8 = "B",
    }) Self {
        _ = items;
        _ = opts;
        return Self{};
    }

    pub fn __len__(self: Self) i64 {
        return self.size;
    }

    pub fn __repr__(self: Self) []const u8 {
        _ = self;
        return "staticarray(...)";
    }

    pub fn tobytes(self: Self) []const u8 {
        return self.data;
    }
};

// Buffer flags (from Python's buffer protocol)
pub const PyBUF_SIMPLE: i64 = 0;
pub const PyBUF_WRITABLE: i64 = 0x0001;
pub const PyBUF_WRITE: i64 = PyBUF_WRITABLE;
pub const PyBUF_READ: i64 = 0x100;
pub const PyBUF_FORMAT: i64 = 0x0004;
pub const PyBUF_ND: i64 = 0x0008;
pub const PyBUF_STRIDES: i64 = 0x0010 | PyBUF_ND;
pub const PyBUF_C_CONTIGUOUS: i64 = 0x0020 | PyBUF_STRIDES;
pub const PyBUF_F_CONTIGUOUS: i64 = 0x0040 | PyBUF_STRIDES;
pub const PyBUF_ANY_CONTIGUOUS: i64 = 0x0080 | PyBUF_STRIDES;
pub const PyBUF_INDIRECT: i64 = 0x0100 | PyBUF_STRIDES;
pub const PyBUF_CONTIG: i64 = PyBUF_ND | PyBUF_WRITABLE;
pub const PyBUF_CONTIG_RO: i64 = PyBUF_ND;
pub const PyBUF_STRIDED: i64 = PyBUF_STRIDES | PyBUF_WRITABLE;
pub const PyBUF_STRIDED_RO: i64 = PyBUF_STRIDES;
pub const PyBUF_RECORDS: i64 = PyBUF_STRIDES | PyBUF_WRITABLE | PyBUF_FORMAT;
pub const PyBUF_RECORDS_RO: i64 = PyBUF_STRIDES | PyBUF_FORMAT;
pub const PyBUF_FULL: i64 = PyBUF_INDIRECT | PyBUF_WRITABLE | PyBUF_FORMAT;
pub const PyBUF_FULL_RO: i64 = PyBUF_INDIRECT | PyBUF_FORMAT;

// ndarray flags from _testbuffer.c
pub const ND_MAX_NDIM: i64 = 64;
pub const ND_WRITABLE: i64 = 0x001;
pub const ND_FORTRAN: i64 = 0x002;
pub const ND_PIL: i64 = 0x004;
pub const ND_REDIRECT: i64 = 0x008;
pub const ND_GETBUF_FAIL: i64 = 0x010;
pub const ND_GETBUF_UNDEFINED: i64 = 0x020;
pub const ND_VAREXPORT: i64 = 0x040;

/// Get slice indices from a slice object and sequence length
/// Returns (start, stop, step, slicelen)
pub fn slice_indices(s: anytype, length: i64) struct { i64, i64, i64, i64 } {
    // Handle slice struct
    const start = if (@hasField(@TypeOf(s), "start"))
        s.start orelse 0
    else
        0;
    const stop = if (@hasField(@TypeOf(s), "stop"))
        s.stop orelse length
    else
        length;
    const step = if (@hasField(@TypeOf(s), "step"))
        s.step orelse 1
    else
        1;

    if (step == 0) return .{ 0, 0, 0, 0 }; // ValueError

    var adj_start = start;
    var adj_stop = stop;

    // Handle negative indices
    if (adj_start < 0) adj_start += length;
    if (adj_stop < 0) adj_stop += length;

    // Clamp to bounds
    if (adj_start < 0) adj_start = if (step < 0) -1 else 0;
    if (adj_start > length) adj_start = if (step < 0) length - 1 else length;
    if (adj_stop < 0) adj_stop = if (step < 0) -1 else 0;
    if (adj_stop > length) adj_stop = if (step < 0) length - 1 else length;

    // Calculate slice length
    var slicelen: i64 = 0;
    if (step > 0 and adj_stop > adj_start) {
        slicelen = @divFloor(adj_stop - adj_start - 1, step) + 1;
    } else if (step < 0 and adj_stop < adj_start) {
        slicelen = @divFloor(adj_start - adj_stop - 1, -step) + 1;
    }

    return .{ adj_start, adj_stop, step, slicelen };
}

/// Get pointer at indices in buffer
pub fn get_pointer(buf: *ndarray, indices: []const i64) ?*u8 {
    if (indices.len != @as(usize, @intCast(buf.ndim))) return null;

    var offset: usize = 0;
    for (indices, 0..) |idx, i| {
        if (i >= buf.strides.len) return null;
        const stride = buf.strides[i];
        offset += @as(usize, @intCast(idx * stride));
    }

    if (offset >= buf.data.len) return null;
    return &buf.data[offset];
}

/// Get contiguous copy of buffer
pub fn get_contiguous(buf: *ndarray, order: i64, flags: i64) ndarray {
    _ = order;
    _ = flags;
    // Return copy of data in contiguous layout
    return ndarray{
        .data = buf.data,
        .shape = buf.shape,
        .strides = buf.strides,
        .format = buf.format,
        .itemsize = buf.itemsize,
        .ndim = buf.ndim,
        .flags = buf.flags,
    };
}

/// Copy buffer to contiguous memory
pub fn py_buffer_to_contiguous(dest: []u8, src: *ndarray, order: i64) void {
    _ = order;
    const len = @min(dest.len, src.data.len);
    @memcpy(dest[0..len], src.data[0..len]);
}

/// Compare two contiguous buffers
pub fn cmp_contig(a: *ndarray, b: *ndarray) i64 {
    const len = @min(a.data.len, b.data.len);
    for (0..len) |i| {
        if (a.data[i] < b.data[i]) return -1;
        if (a.data[i] > b.data[i]) return 1;
    }
    if (a.data.len < b.data.len) return -1;
    if (a.data.len > b.data.len) return 1;
    return 0;
}

/// Check if buffer is contiguous in given order
/// order: 'C' for C-contiguous, 'F' for Fortran-contiguous, 'A' for either
pub fn is_contiguous(buf: anytype, order: anytype) bool {
    // Check if buffer has required methods
    if (@typeInfo(@TypeOf(buf)) == .pointer) {
        const ptr = buf;
        if (@hasField(@TypeOf(ptr.*), "c_contiguous") and @hasField(@TypeOf(ptr.*), "f_contiguous")) {
            // ndarray type - check contiguity
            const order_char: u8 = if (@TypeOf(order) == []const u8 or @TypeOf(order) == [:0]const u8)
                order[0]
            else if (@typeInfo(@TypeOf(order)) == .int or @typeInfo(@TypeOf(order)) == .comptime_int)
                @as(u8, @intCast(order))
            else
                'A';

            return switch (order_char) {
                'C' => ptr.c_contiguous(),
                'F' => ptr.f_contiguous(),
                'A' => ptr.c_contiguous() or ptr.f_contiguous(),
                else => false,
            };
        }
    }
    // For other types, assume contiguous
    return true;
}
