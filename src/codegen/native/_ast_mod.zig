/// Python _ast module - Internal AST support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _ast.PyCF_ONLY_AST constant
pub fn genPyCF_ONLY_AST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x0400)");
}

/// Generate _ast.PyCF_TYPE_COMMENTS constant
pub fn genPyCF_TYPE_COMMENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x1000)");
}

/// Generate _ast.PyCF_ALLOW_TOP_LEVEL_AWAIT constant
pub fn genPyCF_ALLOW_TOP_LEVEL_AWAIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x2000)");
}
