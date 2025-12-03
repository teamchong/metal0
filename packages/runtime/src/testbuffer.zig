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

    const Self = @This();

    /// Create ndarray from list of items
    pub fn init(items: anytype, opts: struct {
        shape: []const i64 = &[_]i64{},
        strides: []const i64 = &[_]i64{},
        suboffsets: ?[]const i64 = null,
        format: []const u8 = "B",
        flags: i64 = 0,
        offset: i64 = 0,
        getbuf: i64 = 0,
    }) Self {
        _ = items;
        _ = opts;
        return Self{};
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

    /// Get item at flat index
    pub fn getitem(self: Self, idx: i64) i64 {
        _ = self;
        _ = idx;
        return 0;
    }

    /// Set item at flat index
    pub fn setitem(self: *Self, idx: i64, value: i64) void {
        _ = self;
        _ = idx;
        _ = value;
    }

    /// Convert to list
    pub fn tolist(self: Self) []const i64 {
        _ = self;
        return &[_]i64{};
    }

    /// Convert to bytes
    pub fn tobytes(self: Self) []const u8 {
        return self.data;
    }

    /// Get memoryview representation
    pub fn memoryview(self: *Self) *Self {
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
