/// Python _ctypes module - Internal ctypes support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _ctypes.CDLL(name, mode=DEFAULT_MODE, handle=None, use_errno=False, use_last_error=False, winmode=None)
pub fn genCDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .handle = null, .name = null }");
}

/// Generate _ctypes.PyDLL(name, mode=DEFAULT_MODE, handle=None, use_errno=False, use_last_error=False, winmode=None)
pub fn genPyDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .handle = null, .name = null }");
}

/// Generate _ctypes.WinDLL(name, mode=DEFAULT_MODE, handle=None, use_errno=False, use_last_error=False, winmode=None)
pub fn genWinDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .handle = null, .name = null }");
}

/// Generate _ctypes.OleDLL(name, mode=DEFAULT_MODE, handle=None, use_errno=False, use_last_error=False, winmode=None)
pub fn genOleDLL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .handle = null, .name = null }");
}

/// Generate _ctypes.cast(obj, typ)
pub fn genCast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _ctypes.c_void_p type
pub fn genCVoidP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate _ctypes.c_char_p type
pub fn genCCharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[*:0]const u8, null)");
}

/// Generate _ctypes.c_wchar_p type
pub fn genCWcharP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[*:0]const u16, null)");
}

/// Generate _ctypes.c_bool type
pub fn genCBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(bool, false)");
}

/// Generate _ctypes.c_char type
pub fn genCChar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 0)");
}

/// Generate _ctypes.c_wchar type
pub fn genCWchar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0)");
}

/// Generate _ctypes.c_byte type
pub fn genCByte(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i8, 0)");
}

/// Generate _ctypes.c_ubyte type
pub fn genCUbyte(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u8, 0)");
}

/// Generate _ctypes.c_short type
pub fn genCShort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i16, 0)");
}

/// Generate _ctypes.c_ushort type
pub fn genCUshort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u16, 0)");
}

/// Generate _ctypes.c_int type
pub fn genCInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _ctypes.c_uint type
pub fn genCUint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0)");
}

/// Generate _ctypes.c_long type
pub fn genCLong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate _ctypes.c_ulong type
pub fn genCUlong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u64, 0)");
}

/// Generate _ctypes.c_longlong type
pub fn genCLonglong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate _ctypes.c_ulonglong type
pub fn genCUlonglong(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u64, 0)");
}

/// Generate _ctypes.c_size_t type
pub fn genCSizeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 0)");
}

/// Generate _ctypes.c_ssize_t type
pub fn genCSSizeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(isize, 0)");
}

/// Generate _ctypes.c_float type
pub fn genCFloat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f32, 0.0)");
}

/// Generate _ctypes.c_double type
pub fn genCDouble(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate _ctypes.c_longdouble type
pub fn genCLongdouble(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate _ctypes.ArgumentError exception
pub fn genArgumentError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ArgumentError");
}

/// Generate _ctypes.FUNCFLAG_CDECL constant
pub fn genFuncflagCdecl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _ctypes.FUNCFLAG_USE_ERRNO constant
pub fn genFuncflagUseErrno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

/// Generate _ctypes.FUNCFLAG_USE_LASTERROR constant
pub fn genFuncflagUseLastError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 16)");
}

/// Generate _ctypes.FUNCFLAG_PYTHONAPI constant
pub fn genFuncflagPythonapi(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

/// Generate _ctypes.sizeof(obj)
pub fn genSizeof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 0)");
}

/// Generate _ctypes.alignment(obj)
pub fn genAlignment(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 1)");
}

/// Generate _ctypes.byref(obj, offset=0)
pub fn genByref(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _ctypes.addressof(obj)
pub fn genAddressof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 0)");
}

/// Generate _ctypes.pointer(obj)
pub fn genPointer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _ctypes.POINTER(type)
pub fn genPOINTER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

/// Generate _ctypes.resize(obj, size)
pub fn genResize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _ctypes.get_errno()
pub fn genGetErrno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _ctypes.set_errno(value)
pub fn genSetErrno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _ctypes.dlopen(name, mode)
pub fn genDlopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _ctypes.dlclose(handle)
pub fn genDlclose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _ctypes.dlsym(handle, name)
pub fn genDlsym(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _ctypes.Structure class
pub fn genStructure(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _ctypes.Union class
pub fn genUnion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _ctypes.Array class
pub fn genArray(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _ctypes.CFuncPtr class
pub fn genCFuncPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _ctypes._SimpleCData class
pub fn genSimpleCData(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .value = 0 }");
}
