/// Python py_compile module - Compile Python source files
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate py_compile.compile(file, cfile=None, dfile=None, doraise=False, optimize=-1, invalidation_mode=PycInvalidationMode.TIMESTAMP, quiet=0)
pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

/// Generate py_compile.main(args=None)
pub fn genMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genPyCompileError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.PyCompileError");
}

// ============================================================================
// Invalidation mode enum
// ============================================================================

pub fn genPycInvalidationMode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .TIMESTAMP = @as(i32, 1), .CHECKED_HASH = @as(i32, 2), .UNCHECKED_HASH = @as(i32, 3) }");
}
