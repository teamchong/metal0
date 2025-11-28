/// Python ctypes module - Foreign function library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Loading dynamic libraries
// ============================================================================

/// Generate ctypes.CDLL(name, mode=DEFAULT_MODE, handle=None, use_errno=False, use_last_error=False, winmode=None)
pub fn genCDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_name: []const u8 = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
    try self.emit(",\n");
    try self.emitIndent();
    try self.emit("_handle: ?*anyopaque = null,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate ctypes.WinDLL (Windows-specific)
pub fn genWinDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_name: []const u8 = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
    try self.emit(",\n");
    try self.emitIndent();
    try self.emit("_handle: ?*anyopaque = null,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate ctypes.OleDLL (Windows-specific)
pub fn genOleDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_name: []const u8 = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
    try self.emit(",\n");
    try self.emitIndent();
    try self.emit("_handle: ?*anyopaque = null,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate ctypes.PyDLL
pub fn genPyDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_name: []const u8 = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
    try self.emit(",\n");
    try self.emitIndent();
    try self.emit("_handle: ?*anyopaque = null,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

// ============================================================================
// Simple C data types
// ============================================================================

/// Generate ctypes.c_bool
pub fn genCBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(bool, ");
        try self.genExpr(args[0]);
        try self.emit(" != 0)");
    } else {
        try self.emit("false");
    }
}

/// Generate ctypes.c_char
pub fn genCChar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(u8, @truncate(@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(u8, 0)");
    }
}

/// Generate ctypes.c_wchar
pub fn genCWchar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(u32, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate ctypes.c_byte
pub fn genCByte(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(i8, @truncate(@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(i8, 0)");
    }
}

/// Generate ctypes.c_ubyte
pub fn genCUbyte(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(u8, @truncate(@as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(u8, 0)");
    }
}

/// Generate ctypes.c_short
pub fn genCShort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(i16, @truncate(@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(i16, 0)");
    }
}

/// Generate ctypes.c_ushort
pub fn genCUshort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(u16, @truncate(@as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(u16, 0)");
    }
}

/// Generate ctypes.c_int
pub fn genCInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(i32, @truncate(@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(i32, 0)");
    }
}

/// Generate ctypes.c_uint
pub fn genCUint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(u32, @truncate(@as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate ctypes.c_long
pub fn genCLong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

/// Generate ctypes.c_ulong
pub fn genCUlong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(u64, 0)");
    }
}

/// Generate ctypes.c_longlong
pub fn genCLonglong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

/// Generate ctypes.c_ulonglong
pub fn genCUlonglong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(u64, 0)");
    }
}

/// Generate ctypes.c_size_t
pub fn genCSizeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(usize, 0)");
    }
}

/// Generate ctypes.c_ssize_t
pub fn genCSSizeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(isize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(isize, 0)");
    }
}

/// Generate ctypes.c_float
pub fn genCFloat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(f32, @floatCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f32, 0.0)");
    }
}

/// Generate ctypes.c_double
pub fn genCDouble(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

/// Generate ctypes.c_longdouble
pub fn genCLongdouble(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(f128, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(f128, 0.0)");
    }
}

/// Generate ctypes.c_char_p (pointer to null-terminated string)
pub fn genCCharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?[*:0]const u8, null)");
    }
}

/// Generate ctypes.c_wchar_p (pointer to wide string)
pub fn genCWcharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?[*:0]const u32, null)");
    }
}

/// Generate ctypes.c_void_p (void pointer)
pub fn genCVoidP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(*anyopaque, @ptrFromInt(@as(usize, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))))");
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

// ============================================================================
// Structure and Union
// ============================================================================

/// Generate ctypes.Structure base class
pub fn genStructure(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {}{}");
}

/// Generate ctypes.Union base class
pub fn genUnion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("union {}{}");
}

/// Generate ctypes.BigEndianStructure base class
pub fn genBigEndianStructure(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {}{}");
}

/// Generate ctypes.LittleEndianStructure base class
pub fn genLittleEndianStructure(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {}{}");
}

// ============================================================================
// Arrays and Pointers
// ============================================================================

/// Generate ctypes.Array base class
pub fn genArrayType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("[]anyopaque");
}

/// Generate ctypes.POINTER(type)
pub fn genPOINTER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("*anyopaque");
}

/// Generate ctypes.pointer(obj)
pub fn genPointer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(*anyopaque, @ptrCast(&");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

// ============================================================================
// Utility functions
// ============================================================================

/// Generate ctypes.sizeof(obj_or_type)
pub fn genSizeof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@sizeOf(@TypeOf(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("0");
    }
}

/// Generate ctypes.alignment(obj_or_type)
pub fn genAlignment(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@alignOf(@TypeOf(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("1");
    }
}

/// Generate ctypes.addressof(obj)
pub fn genAddressof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@intFromPtr(&");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

/// Generate ctypes.byref(obj, offset=0)
pub fn genByref(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("&");
        try self.genExpr(args[0]);
    } else {
        try self.emit("null");
    }
}

/// Generate ctypes.cast(obj, type)
pub fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(*anyopaque, @ptrCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("null");
    }
}

/// Generate ctypes.create_string_buffer(init_or_size, size=None)
pub fn genCreateStringBuffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as([]u8, allocator.alloc(u8, 256) catch &[_]u8{})");
}

/// Generate ctypes.create_unicode_buffer(init_or_size, size=None)
pub fn genCreateUnicodeBuffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as([]u32, allocator.alloc(u32, 256) catch &[_]u32{})");
}

/// Generate ctypes.get_errno()
pub fn genGetErrno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate ctypes.set_errno(value)
pub fn genSetErrno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate ctypes.get_last_error() (Windows)
pub fn genGetLastError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate ctypes.set_last_error(value) (Windows)
pub fn genSetLastError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate ctypes.memmove(dst, src, count)
pub fn genMemmove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ctypes.memset(dst, c, count)
pub fn genMemset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ctypes.string_at(address, size=-1)
pub fn genStringAt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate ctypes.wstring_at(address, size=-1)
pub fn genWstringAt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

// ============================================================================
// Function types
// ============================================================================

/// Generate ctypes.CFUNCTYPE(restype, *argtypes)
pub fn genCFUNCTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("*const fn() callconv(.c) void");
}

/// Generate ctypes.WINFUNCTYPE(restype, *argtypes) (Windows)
pub fn genWINFUNCTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("*const fn() callconv(.stdcall) void");
}

/// Generate ctypes.PYFUNCTYPE(restype, *argtypes)
pub fn genPYFUNCTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("*const fn() void");
}
