/// Python _testbuffer module - Buffer protocol test support
/// Provides ndarray and buffer flag constants for testing PEP-3118
const std = @import("std");
const h = @import("mod_helper.zig");

// Buffer flags (from Python's buffer protocol)
// These match CPython's definitions in Include/cpython/object.h
pub const PyBUF_SIMPLE: i64 = 0;
pub const PyBUF_WRITABLE: i64 = 0x0001;
pub const PyBUF_WRITE: i64 = PyBUF_WRITABLE; // Alias
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

pub const Consts = std.StaticStringMap(h.H).initComptime(.{
    // PyBUF_* constants
    .{ "PyBUF_SIMPLE", h.c("@as(i64, 0)") },
    .{ "PyBUF_WRITABLE", h.c("@as(i64, 0x0001)") },
    .{ "PyBUF_WRITE", h.c("@as(i64, 0x0001)") },
    .{ "PyBUF_READ", h.c("@as(i64, 0x100)") },
    .{ "PyBUF_FORMAT", h.c("@as(i64, 0x0004)") },
    .{ "PyBUF_ND", h.c("@as(i64, 0x0008)") },
    .{ "PyBUF_STRIDES", h.c("@as(i64, 0x0018)") },
    .{ "PyBUF_C_CONTIGUOUS", h.c("@as(i64, 0x0038)") },
    .{ "PyBUF_F_CONTIGUOUS", h.c("@as(i64, 0x0058)") },
    .{ "PyBUF_ANY_CONTIGUOUS", h.c("@as(i64, 0x0098)") },
    .{ "PyBUF_INDIRECT", h.c("@as(i64, 0x0118)") },
    .{ "PyBUF_CONTIG", h.c("@as(i64, 0x0009)") },
    .{ "PyBUF_CONTIG_RO", h.c("@as(i64, 0x0008)") },
    .{ "PyBUF_STRIDED", h.c("@as(i64, 0x0019)") },
    .{ "PyBUF_STRIDED_RO", h.c("@as(i64, 0x0018)") },
    .{ "PyBUF_RECORDS", h.c("@as(i64, 0x001d)") },
    .{ "PyBUF_RECORDS_RO", h.c("@as(i64, 0x001c)") },
    .{ "PyBUF_FULL", h.c("@as(i64, 0x011d)") },
    .{ "PyBUF_FULL_RO", h.c("@as(i64, 0x011c)") },
    // ND_* constants
    .{ "ND_MAX_NDIM", h.c("@as(i64, 64)") },
    .{ "ND_WRITABLE", h.c("@as(i64, 0x001)") },
    .{ "ND_FORTRAN", h.c("@as(i64, 0x002)") },
    .{ "ND_PIL", h.c("@as(i64, 0x004)") },
    .{ "ND_REDIRECT", h.c("@as(i64, 0x008)") },
    .{ "ND_GETBUF_FAIL", h.c("@as(i64, 0x010)") },
    .{ "ND_GETBUF_UNDEFINED", h.c("@as(i64, 0x020)") },
    .{ "ND_VAREXPORT", h.c("@as(i64, 0x040)") },
    // ndarray class - returns a stub struct
    .{ "ndarray", h.c("runtime.TestBuffer.ndarray") },
    // staticarray for testing
    .{ "staticarray", h.c("runtime.TestBuffer.staticarray") },
    // get_sizeof_void_p - returns pointer size
    .{ "get_sizeof_void_p", h.c("@as(i64, @sizeOf(*anyopaque))") },
});

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // ndarray constructor handled specially
    .{ "get_sizeof_void_p", h.c("@as(i64, @sizeOf(*anyopaque))") },
});
