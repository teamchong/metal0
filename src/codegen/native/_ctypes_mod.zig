/// Python _ctypes module - Internal ctypes support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "CDLL", h.c(".{ .handle = null, .name = null }") }, .{ "PyDLL", h.c(".{ .handle = null, .name = null }") },
    .{ "WinDLL", h.c(".{ .handle = null, .name = null }") }, .{ "OleDLL", h.c(".{ .handle = null, .name = null }") },
    .{ "dlopen", h.c("null") }, .{ "dlclose", h.I32(0) }, .{ "dlsym", h.c("null") },
    .{ "FUNCFLAG_CDECL", h.I32(1) }, .{ "FUNCFLAG_USE_ERRNO", h.I32(8) },
    .{ "FUNCFLAG_USE_LASTERROR", h.I32(16) }, .{ "FUNCFLAG_PYTHONAPI", h.I32(4) },
    .{ "sizeof", h.c("@as(usize, 0)") }, .{ "alignment", h.c("@as(usize, 1)") }, .{ "byref", h.c(".{}") }, .{ "addressof", h.c("@as(usize, 0)") },
    .{ "POINTER", h.c("@TypeOf(.{})") }, .{ "pointer", h.c(".{}") }, .{ "cast", h.c(".{}") },
    .{ "set_errno", h.I32(0) }, .{ "get_errno", h.I32(0) }, .{ "resize", h.c("{}") },
    .{ "c_void_p", h.c("@as(?*anyopaque, null)") }, .{ "c_char_p", h.c("@as(?[*:0]const u8, null)") }, .{ "c_wchar_p", h.c("@as(?[*:0]const u16, null)") },
    .{ "c_bool", h.c("@as(bool, false)") }, .{ "c_char", h.U8(0) }, .{ "c_wchar", h.c("@as(u16, 0)") },
    .{ "c_byte", h.c("@as(i8, 0)") }, .{ "c_ubyte", h.U8(0) }, .{ "c_short", h.c("@as(i16, 0)") }, .{ "c_ushort", h.c("@as(u16, 0)") },
    .{ "c_int", h.I32(0) }, .{ "c_uint", h.U32(0) }, .{ "c_long", h.I64(0) }, .{ "c_ulong", h.c("@as(u64, 0)") },
    .{ "c_longlong", h.I64(0) }, .{ "c_ulonglong", h.c("@as(u64, 0)") },
    .{ "c_size_t", h.c("@as(usize, 0)") }, .{ "c_ssize_t", h.c("@as(isize, 0)") },
    .{ "c_float", h.c("@as(f32, 0.0)") }, .{ "c_double", h.F64(0.0) }, .{ "c_longdouble", h.F64(0.0) },
    .{ "Structure", h.c(".{}") }, .{ "Union", h.c(".{}") }, .{ "Array", h.c(".{}") },
    .{ "ArgumentError", h.err("ArgumentError") },
});
