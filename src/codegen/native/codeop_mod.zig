/// Python codeop module - Compile Python code with compiler flags
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate codeop.compile_command(source, filename, symbol)
pub fn genCompile_command(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codeop.Compile class
pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .flags = @as(i32, 0) }");
}

/// Generate codeop.CommandCompiler class
pub fn genCommandCompiler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler = .{ .flags = @as(i32, 0) } }");
}

/// Generate codeop.PyCF_DONT_IMPLY_DEDENT
pub fn genPyCF_DONT_IMPLY_DEDENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x200)");
}

/// Generate codeop.PyCF_ALLOW_INCOMPLETE_INPUT
pub fn genPyCF_ALLOW_INCOMPLETE_INPUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x4000)");
}
