/// Python ctypes module - Foreign function library
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genCType(comptime zig_type: []const u8, comptime default: []const u8, comptime pre: []const u8, comptime suf: []const u8) h.H {
    return h.wrap(pre, suf, "@as(" ++ zig_type ++ ", " ++ default ++ ")");
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // DLLs
    .{ "CDLL", genDLL }, .{ "WinDLL", genDLL }, .{ "OleDLL", genDLL }, .{ "PyDLL", genDLL },
    // C types
    .{ "c_bool", h.wrap("@as(bool, ", " != 0)", "false") },
    .{ "c_char", genCType("u8", "0", "@as(u8, @truncate(@as(usize, @intCast(", "))))") },
    .{ "c_wchar", genCType("u32", "0", "@as(u32, @intCast(", "))") },
    .{ "c_byte", genCType("i8", "0", "@as(i8, @truncate(@as(i64, ", ")))") },
    .{ "c_ubyte", genCType("u8", "0", "@as(u8, @truncate(@as(u64, @intCast(", "))))") },
    .{ "c_short", genCType("i16", "0", "@as(i16, @truncate(@as(i64, ", ")))") },
    .{ "c_ushort", genCType("u16", "0", "@as(u16, @truncate(@as(u64, @intCast(", "))))") },
    .{ "c_int", genCType("i32", "0", "@as(i32, @truncate(@as(i64, ", ")))") },
    .{ "c_uint", genCType("u32", "0", "@as(u32, @truncate(@as(u64, @intCast(", "))))") },
    .{ "c_long", genCType("i64", "0", "@as(i64, ", ")") },
    .{ "c_ulong", genCType("u64", "0", "@as(u64, @intCast(", "))") },
    .{ "c_longlong", genCType("i64", "0", "@as(i64, ", ")") },
    .{ "c_ulonglong", genCType("u64", "0", "@as(u64, @intCast(", "))") },
    .{ "c_size_t", genCType("usize", "0", "@as(usize, @intCast(", "))") },
    .{ "c_ssize_t", genCType("isize", "0", "@as(isize, @intCast(", "))") },
    .{ "c_float", genCType("f32", "0.0", "@as(f32, @floatCast(", "))") },
    .{ "c_double", genCType("f64", "0.0", "@as(f64, ", ")") },
    .{ "c_longdouble", genCType("f128", "0.0", "@as(f128, ", ")") },
    // Pointer types
    .{ "c_char_p", h.c("@as(?[*:0]const u8, null)") },
    .{ "c_wchar_p", h.c("@as(?[*:0]const u32, null)") },
    .{ "c_void_p", h.wrap("@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(", "))))", "@as(?*anyopaque, null)") },
    // Structures
    .{ "Structure", h.c("struct {}{}") }, .{ "Union", h.c("union {}{}") },
    .{ "BigEndianStructure", h.c("struct {}{}") }, .{ "LittleEndianStructure", h.c("struct {}{}") },
    // Arrays/pointers
    .{ "Array", h.c("[]anyopaque") }, .{ "POINTER", h.c("*anyopaque") },
    .{ "pointer", h.wrap("@as(*anyopaque, @ptrCast(&", "))", "@as(?*anyopaque, null)") },
    // Utility
    .{ "sizeof", h.wrap("@sizeOf(@TypeOf(", "))", "0") },
    .{ "alignment", h.wrap("@alignOf(@TypeOf(", "))", "1") },
    .{ "addressof", h.wrap("@intFromPtr(&", ")", "0") },
    .{ "byref", h.wrap("&", "", "null") },
    .{ "cast", h.wrap("@as(*anyopaque, @ptrCast(", "))", "null") },
    .{ "create_string_buffer", h.c("@as([]u8, __global_allocator.alloc(u8, 256) catch &[_]u8{})") },
    .{ "create_unicode_buffer", h.c("@as([]u32, __global_allocator.alloc(u32, 256) catch &[_]u32{})") },
    .{ "get_errno", h.I32(0) }, .{ "set_errno", h.I32(0) },
    .{ "get_last_error", h.I32(0) }, .{ "set_last_error", h.I32(0) },
    .{ "memmove", h.c("{}") }, .{ "memset", h.c("{}") },
    .{ "string_at", h.c("\"\"") }, .{ "wstring_at", h.c("\"\"") },
    // Function types
    .{ "CFUNCTYPE", h.c("*const fn() callconv(.c) void") },
    .{ "WINFUNCTYPE", h.c("*const fn() callconv(.stdcall) void") },
    .{ "PYFUNCTYPE", h.c("*const fn() void") },
});

const genDLL = h.wrap("struct { _name: []const u8 = ", ", _handle: ?*anyopaque = null }{}", "struct { _name: []const u8 = \"\", _handle: ?*anyopaque = null }{}");


