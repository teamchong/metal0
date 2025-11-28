/// Python _ctypes module - Internal ctypes support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

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
