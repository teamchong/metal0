/// Python _ctypes module - Internal ctypes support (C accelerator)
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c(), h.I64(), h.F64(), h.err() factories for constants
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // DLL types
    .{ "CDLL", h.c(".{ .handle = null, .name = null }") },
    .{ "PyDLL", h.c(".{ .handle = null, .name = null }") },
    .{ "WinDLL", h.c(".{ .handle = null, .name = null }") },
    .{ "OleDLL", h.c(".{ .handle = null, .name = null }") },
    // Dynamic loading
    .{ "dlopen", h.c("null") },
    .{ "dlclose", h.I64(0) },
    .{ "dlsym", h.c("null") },
    // Function flags
    .{ "FUNCFLAG_CDECL", h.I64(1) },
    .{ "FUNCFLAG_USE_ERRNO", h.I64(8) },
    .{ "FUNCFLAG_USE_LASTERROR", h.I64(16) },
    .{ "FUNCFLAG_PYTHONAPI", h.I64(4) },
    // Utility functions
    .{ "sizeof", h.c("@as(usize, 0)") },
    .{ "alignment", h.c("@as(usize, 1)") },
    .{ "byref", h.c(".{}") },
    .{ "addressof", h.c("@as(usize, 0)") },
    .{ "POINTER", h.c("@TypeOf(.{})") },
    .{ "pointer", h.c(".{}") },
    .{ "cast", h.c(".{}") },
    .{ "set_errno", h.I64(0) },
    .{ "get_errno", h.I64(0) },
    .{ "resize", h.c("{}") },
    // Pointer types
    .{ "c_void_p", h.c("@as(?*anyopaque, null)") },
    .{ "c_char_p", h.c("@as(?[*:0]const u8, null)") },
    .{ "c_wchar_p", h.c("@as(?[*:0]const u16, null)") },
    // Primitive types
    .{ "c_bool", h.c("@as(bool, false)") },
    .{ "c_char", h.U8(0) },
    .{ "c_wchar", h.U16(0) },
    .{ "c_byte", h.c("@as(i8, 0)") },
    .{ "c_ubyte", h.U8(0) },
    .{ "c_short", h.I16(0) },
    .{ "c_ushort", h.U16(0) },
    .{ "c_int", h.I64(0) },
    .{ "c_uint", h.U32(0) },
    .{ "c_long", h.I64(0) },
    .{ "c_ulong", h.c("@as(u64, 0)") },
    .{ "c_longlong", h.I64(0) },
    .{ "c_ulonglong", h.c("@as(u64, 0)") },
    .{ "c_size_t", h.c("@as(usize, 0)") },
    .{ "c_ssize_t", h.c("@as(isize, 0)") },
    .{ "c_float", h.c("@as(f32, 0.0)") },
    .{ "c_double", h.F64(0.0) },
    .{ "c_longdouble", h.F64(0.0) },
    // Compound types
    .{ "Structure", h.c(".{}") },
    .{ "Union", h.c(".{}") },
    .{ "Array", h.c(".{}") },
    // Error type
    .{ "ArgumentError", h.err("ArgumentError") },
});
