/// Python ctypes module - Foreign function library
/// Generates code that uses runtime.ctypes for actual FFI
const std = @import("std");
const ast = @import("ast");
const m = @import("mod_helper.zig");
const H = m.H;

// === Comptime generators for C type conversions ===

/// Generate ctypes integer type: @as(runtime.ctypes.@"type_name", @intCast(arg))
fn cInt(comptime name: []const u8) H {
    return m.wrap("@as(runtime.ctypes.@\"" ++ name ++ "\", @intCast(", "))", "@as(runtime.ctypes.@\"" ++ name ++ "\", 0)");
}

/// Generate ctypes float type: @as(runtime.ctypes.@"type_name", @floatCast(arg))
fn cFloat(comptime name: []const u8, comptime def: []const u8) H {
    return m.wrap("@as(runtime.ctypes.@\"" ++ name ++ "\", @floatCast(", "))", "@as(runtime.ctypes.@\"" ++ name ++ "\", " ++ def ++ ")");
}

/// Generate ctypes direct cast: @as(runtime.ctypes.@"type_name", arg)
fn cDirect(comptime name: []const u8, comptime def: []const u8) H {
    return m.wrap("@as(runtime.ctypes.@\"" ++ name ++ "\", ", ")", "@as(runtime.ctypes.@\"" ++ name ++ "\", " ++ def ++ ")");
}

/// Generate truncated int: @as(T, @truncate(@as(i64/u64, arg)))
fn cTrunc(comptime name: []const u8, comptime cast: []const u8) H {
    return m.wrap("@as(runtime.ctypes.@\"" ++ name ++ "\", @truncate(@as(" ++ cast ++ ", ", ")))", "@as(runtime.ctypes.@\"" ++ name ++ "\", 0)");
}

pub const Funcs = std.StaticStringMap(H).initComptime(.{
    // pythonapi - access to Python C API symbols
    .{ "pythonapi", m.c("runtime.ctypes.PythonAPI{}") },
    // DLLs - actual dynamic library loading
    .{ "CDLL", genCDLL }, .{ "WinDLL", genCDLL }, .{ "OleDLL", genCDLL }, .{ "PyDLL", genCDLL },
    // C types - use runtime.ctypes type aliases
    .{ "c_bool", genCBool },
    .{ "c_char", genCChar },
    .{ "c_wchar", cInt("c_wchar") },
    .{ "c_byte", cTrunc("c_byte", "i64") },
    .{ "c_ubyte", cTrunc("c_ubyte", "u64, @intCast(") },
    .{ "c_short", cTrunc("c_short", "i64") },
    .{ "c_ushort", cTrunc("c_ushort", "u64, @intCast(") },
    .{ "c_int", cTrunc("c_int", "i64") },
    .{ "c_uint", cTrunc("c_uint", "u64, @intCast(") },
    .{ "c_long", cInt("c_long") },
    .{ "c_ulong", cInt("c_ulong") },
    .{ "c_longlong", cInt("c_longlong") },
    .{ "c_ulonglong", cInt("c_ulonglong") },
    .{ "c_size_t", cInt("c_size_t") },
    .{ "c_ssize_t", cInt("c_ssize_t") },
    .{ "c_float", cFloat("c_float", "0.0") },
    .{ "c_double", cDirect("c_double", "0.0") },
    .{ "c_longdouble", cDirect("c_longdouble", "0.0") },
    // Pointer types
    .{ "c_char_p", cDirect("c_char_p", "null") },
    .{ "c_wchar_p", cDirect("c_wchar_p", "null") },
    .{ "c_void_p", genCVoidP },
    // Structures
    .{ "Structure", m.c("struct {}{}") },
    .{ "Union", m.c("union {}{}") },
    .{ "BigEndianStructure", m.c("struct {}{}") },
    .{ "LittleEndianStructure", m.c("struct {}{}") },
    // Arrays/pointers
    .{ "Array", m.c("[]anyopaque") },
    .{ "POINTER", m.c("*anyopaque") },
    .{ "pointer", m.wrap("@as(*anyopaque, @ptrCast(&", "))", "@as(?*anyopaque, null)") },
    // Utility
    .{ "sizeof", m.wrap("@sizeOf(@TypeOf(", "))", "0") },
    .{ "alignment", m.wrap("@alignOf(@TypeOf(", "))", "1") },
    .{ "addressof", m.wrap("@intFromPtr(&", ")", "0") },
    .{ "byref", m.wrap("&", "", "null") },
    .{ "cast", m.wrap("@as(*anyopaque, @ptrCast(", "))", "null") },
    .{ "create_string_buffer", m.wrap("(runtime.ctypes.create_string_buffer(__global_allocator, ", ") catch &[_]u8{})", "(runtime.ctypes.create_string_buffer(__global_allocator, 256) catch &[_]u8{})") },
    .{ "create_unicode_buffer", m.wrap("(runtime.ctypes.create_unicode_buffer(__global_allocator, ", ") catch &[_]u32{})", "(runtime.ctypes.create_unicode_buffer(__global_allocator, 256) catch &[_]u32{})") },
    .{ "get_errno", m.c("runtime.ctypes.get_errno()") },
    .{ "set_errno", m.wrap("runtime.ctypes.set_errno(", ")", "runtime.ctypes.set_errno(0)") },
    .{ "get_last_error", m.c("runtime.ctypes.get_errno()") },
    .{ "set_last_error", m.wrap("runtime.ctypes.set_errno(", ")", "runtime.ctypes.set_errno(0)") },
    .{ "memmove", genMemmove },
    .{ "memset", genMemset },
    .{ "string_at", m.wrap2("runtime.ctypes.string_at(", ", ", ")", "\"\"") },
    .{ "wstring_at", m.wrap2("runtime.ctypes.string_at(", ", ", ")", "\"\"") },
    // Function types (stubs - actual implementation needs type analysis)
    .{ "CFUNCTYPE", m.c("*const fn() callconv(.c) void") },
    .{ "WINFUNCTYPE", m.c("*const fn() callconv(.c) void") },
    .{ "PYFUNCTYPE", m.c("*const fn() callconv(.c) void") },
});

// === Complex handlers ===

fn genCDLL(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    try self.emit("(runtime.ctypes.CDLL.init(__global_allocator, ");
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
    try self.emit(") catch unreachable)");
}

fn genCBool(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_bool\", ");
        try self.genExpr(args[0]);
        try self.emit(" != 0)");
    } else try self.emit("@as(runtime.ctypes.@\"c_bool\", false)");
}

fn genCChar(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_char\", @truncate(@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else try self.emit("@as(runtime.ctypes.@\"c_char\", 0)");
}

fn genCVoidP(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_void_p\", @ptrFromInt(@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else try self.emit("@as(runtime.ctypes.@\"c_void_p\", null)");
}

fn genMemmove(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len >= 3) {
        try self.emit("runtime.ctypes.memmove(@ptrCast(");
        try self.genExpr(args[0]);
        try self.emit("), @ptrCast(");
        try self.genExpr(args[1]);
        try self.emit("), ");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else try self.emit("{}");
}

fn genMemset(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len >= 3) {
        try self.emit("runtime.ctypes.memset(@ptrCast(");
        try self.genExpr(args[0]);
        try self.emit("), ");
        try self.genExpr(args[1]);
        try self.emit(", ");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else try self.emit("{}");
}
