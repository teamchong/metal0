/// Python ctypes module - Foreign function library
/// Generates code that uses runtime.ctypes for actual FFI
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // DLLs - actual dynamic library loading
    .{ "CDLL", genCDLL },
    .{ "WinDLL", genCDLL },
    .{ "OleDLL", genCDLL },
    .{ "PyDLL", genCDLL },
    // C types - use runtime.ctypes type aliases
    .{ "c_bool", genCBool },
    .{ "c_char", genCChar },
    .{ "c_wchar", genCWchar },
    .{ "c_byte", genCByte },
    .{ "c_ubyte", genCUbyte },
    .{ "c_short", genCShort },
    .{ "c_ushort", genCUshort },
    .{ "c_int", genCInt },
    .{ "c_uint", genCUint },
    .{ "c_long", genCLong },
    .{ "c_ulong", genCUlong },
    .{ "c_longlong", genCLonglong },
    .{ "c_ulonglong", genCUlonglong },
    .{ "c_size_t", genCSizeT },
    .{ "c_ssize_t", genCSSizeT },
    .{ "c_float", genCFloat },
    .{ "c_double", genCDouble },
    .{ "c_longdouble", genCLongDouble },
    // Pointer types
    .{ "c_char_p", genCCharP },
    .{ "c_wchar_p", genCWcharP },
    .{ "c_void_p", genCVoidP },
    // Structures
    .{ "Structure", genStructure },
    .{ "Union", genUnion },
    .{ "BigEndianStructure", genStructure },
    .{ "LittleEndianStructure", genStructure },
    // Arrays/pointers
    .{ "Array", genArray },
    .{ "POINTER", genPointer },
    .{ "pointer", genPointerFn },
    // Utility
    .{ "sizeof", genSizeof },
    .{ "alignment", genAlignment },
    .{ "addressof", genAddressof },
    .{ "byref", genByref },
    .{ "cast", genCast },
    .{ "create_string_buffer", genCreateStringBuffer },
    .{ "create_unicode_buffer", genCreateUnicodeBuffer },
    .{ "get_errno", genGetErrno },
    .{ "set_errno", genSetErrno },
    .{ "get_last_error", genGetErrno },
    .{ "set_last_error", genSetErrno },
    .{ "memmove", genMemmove },
    .{ "memset", genMemset },
    .{ "string_at", genStringAt },
    .{ "wstring_at", genStringAt },
    // Function types (stubs - actual implementation needs type analysis)
    .{ "CFUNCTYPE", genCFunctype },
    .{ "WINFUNCTYPE", genCFunctype },
    .{ "PYFUNCTYPE", genCFunctype },
});

fn genCDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // ctypes.CDLL("libfoo.so") -> runtime.ctypes.CDLL.init(__global_allocator, "libfoo.so")
    try self.emit("(runtime.ctypes.CDLL.init(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
    try self.emit(") catch unreachable)");
}

fn genCBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_bool\", ");
        try self.genExpr(args[0]);
        try self.emit(" != 0)");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_bool\", false)");
    }
}

fn genCChar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_char\", @truncate(@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_char\", 0)");
    }
}

fn genCWchar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_wchar\", @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_wchar\", 0)");
    }
}

fn genCByte(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_byte\", @truncate(@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_byte\", 0)");
    }
}

fn genCUbyte(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_ubyte\", @truncate(@as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_ubyte\", 0)");
    }
}

fn genCShort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_short\", @truncate(@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_short\", 0)");
    }
}

fn genCUshort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_ushort\", @truncate(@as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_ushort\", 0)");
    }
}

fn genCInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_int\", @truncate(@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_int\", 0)");
    }
}

fn genCUint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_uint\", @truncate(@as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_uint\", 0)");
    }
}

fn genCLong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_long\", @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_long\", 0)");
    }
}

fn genCUlong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_ulong\", @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_ulong\", 0)");
    }
}

fn genCLonglong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_longlong\", @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_longlong\", 0)");
    }
}

fn genCUlonglong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_ulonglong\", @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_ulonglong\", 0)");
    }
}

fn genCSizeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_size_t\", @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_size_t\", 0)");
    }
}

fn genCSSizeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_ssize_t\", @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_ssize_t\", 0)");
    }
}

fn genCFloat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_float\", @floatCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_float\", 0.0)");
    }
}

fn genCDouble(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_double\", ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_double\", 0.0)");
    }
}

fn genCLongDouble(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_longdouble\", ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_longdouble\", 0.0)");
    }
}

fn genCCharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_char_p\", ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_char_p\", null)");
    }
}

fn genCWcharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_wchar_p\", ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_wchar_p\", null)");
    }
}

fn genCVoidP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(runtime.ctypes.@\"c_void_p\", @ptrFromInt(@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(runtime.ctypes.@\"c_void_p\", null)");
    }
}

fn genStructure(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    // Structure base class - returns empty struct
    try self.emit("struct {}{}");
}

fn genUnion(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    // Union base class - returns empty union
    try self.emit("union {}{}");
}

fn genArray(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("[]anyopaque");
}

fn genPointer(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("*anyopaque");
}

fn genPointerFn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(*anyopaque, @ptrCast(&");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

fn genSizeof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@sizeOf(@TypeOf(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("0");
    }
}

fn genAlignment(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@alignOf(@TypeOf(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("1");
    }
}

fn genAddressof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@intFromPtr(&");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

fn genByref(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("&");
        try self.genExpr(args[0]);
    } else {
        try self.emit("null");
    }
}

fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(*anyopaque, @ptrCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("null");
    }
}

fn genCreateStringBuffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("(runtime.ctypes.create_string_buffer(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("256");
    }
    try self.emit(") catch &[_]u8{})");
}

fn genCreateUnicodeBuffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("(runtime.ctypes.create_unicode_buffer(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("256");
    }
    try self.emit(") catch &[_]u32{})");
}

fn genGetErrno(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("runtime.ctypes.get_errno()");
}

fn genSetErrno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.ctypes.set_errno(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("0");
    }
    try self.emit(")");
}

fn genMemmove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit("runtime.ctypes.memmove(@ptrCast(");
        try self.genExpr(args[0]);
        try self.emit("), @ptrCast(");
        try self.genExpr(args[1]);
        try self.emit("), ");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        try self.emit("{}");
    }
}

fn genMemset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit("runtime.ctypes.memset(@ptrCast(");
        try self.genExpr(args[0]);
        try self.emit("), ");
        try self.genExpr(args[1]);
        try self.emit(", ");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        try self.emit("{}");
    }
}

fn genStringAt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("runtime.ctypes.string_at(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("\"\"");
    }
}

fn genCFunctype(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    // Function type factory - returns generic function pointer type
    // Actual function signature would need more complex type analysis
    try self.emit("*const fn() callconv(.c) void");
}
