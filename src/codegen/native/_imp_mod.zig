/// Python _imp module - Internal import machinery support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _imp.lock_held()
pub fn genLockHeld(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _imp.acquire_lock()
pub fn genAcquireLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _imp.release_lock()
pub fn genReleaseLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _imp.get_frozen_object(name)
pub fn genGetFrozenObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _imp.is_frozen(name)
pub fn genIsFrozen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _imp.is_builtin(name)
pub fn genIsBuiltin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _imp.is_frozen_package(name)
pub fn genIsFrozenPackage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _imp.create_builtin(spec)
pub fn genCreateBuiltin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _imp.create_dynamic(spec, file)
pub fn genCreateDynamic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _imp.exec_builtin(module)
pub fn genExecBuiltin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _imp.exec_dynamic(module)
pub fn genExecDynamic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _imp.extension_suffixes()
pub fn genExtensionSuffixes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }");
}

/// Generate _imp.source_hash(key, source)
pub fn genSourceHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\x00\" ** 8");
}

/// Generate _imp.check_hash_based_pycs constant
pub fn genCheckHashBasedPycs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"default\"");
}
