/// Python _ctypes module - Internal ctypes support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CDLL", genConst(".{ .handle = null, .name = null }") }, .{ "PyDLL", genConst(".{ .handle = null, .name = null }") },
    .{ "WinDLL", genConst(".{ .handle = null, .name = null }") }, .{ "OleDLL", genConst(".{ .handle = null, .name = null }") },
    .{ "dlopen", genConst("null") }, .{ "dlclose", genConst("@as(i32, 0)") }, .{ "dlsym", genConst("null") },
    .{ "FUNCFLAG_CDECL", genConst("@as(i32, 1)") }, .{ "FUNCFLAG_USE_ERRNO", genConst("@as(i32, 8)") },
    .{ "FUNCFLAG_USE_LASTERROR", genConst("@as(i32, 16)") }, .{ "FUNCFLAG_PYTHONAPI", genConst("@as(i32, 4)") },
    .{ "sizeof", genConst("@as(usize, 0)") }, .{ "alignment", genConst("@as(usize, 1)") }, .{ "byref", genConst(".{}") }, .{ "addressof", genConst("@as(usize, 0)") },
    .{ "POINTER", genConst("@TypeOf(.{})") }, .{ "pointer", genConst(".{}") }, .{ "cast", genConst(".{}") },
    .{ "set_errno", genConst("@as(i32, 0)") }, .{ "get_errno", genConst("@as(i32, 0)") }, .{ "resize", genConst("{}") },
    .{ "c_void_p", genConst("@as(?*anyopaque, null)") }, .{ "c_char_p", genConst("@as(?[*:0]const u8, null)") }, .{ "c_wchar_p", genConst("@as(?[*:0]const u16, null)") },
    .{ "c_bool", genConst("@as(bool, false)") }, .{ "c_char", genConst("@as(u8, 0)") }, .{ "c_wchar", genConst("@as(u16, 0)") },
    .{ "c_byte", genConst("@as(i8, 0)") }, .{ "c_ubyte", genConst("@as(u8, 0)") }, .{ "c_short", genConst("@as(i16, 0)") }, .{ "c_ushort", genConst("@as(u16, 0)") },
    .{ "c_int", genConst("@as(i32, 0)") }, .{ "c_uint", genConst("@as(u32, 0)") }, .{ "c_long", genConst("@as(i64, 0)") }, .{ "c_ulong", genConst("@as(u64, 0)") },
    .{ "c_longlong", genConst("@as(i64, 0)") }, .{ "c_ulonglong", genConst("@as(u64, 0)") },
    .{ "c_size_t", genConst("@as(usize, 0)") }, .{ "c_ssize_t", genConst("@as(isize, 0)") },
    .{ "c_float", genConst("@as(f32, 0.0)") }, .{ "c_double", genConst("@as(f64, 0.0)") }, .{ "c_longdouble", genConst("@as(f64, 0.0)") },
    .{ "Structure", genConst(".{}") }, .{ "Union", genConst(".{}") }, .{ "Array", genConst(".{}") },
    .{ "ArgumentError", genConst("error.ArgumentError") },
});
