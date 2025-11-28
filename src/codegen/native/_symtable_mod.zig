/// Python _symtable module - Internal symtable support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _symtable.symtable(code, filename, compile_type)
pub fn genSymtable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"top\", .type = \"module\", .id = 0, .lineno = 0 }");
}

/// Generate _symtable.SCOPE_OFF constant
pub fn genSCOPE_OFF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 11)");
}

/// Generate _symtable.SCOPE_MASK constant
pub fn genSCOPE_MASK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0xf)");
}

/// Generate _symtable.LOCAL constant
pub fn genLOCAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _symtable.GLOBAL_EXPLICIT constant
pub fn genGLOBAL_EXPLICIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate _symtable.GLOBAL_IMPLICIT constant
pub fn genGLOBAL_IMPLICIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

/// Generate _symtable.FREE constant
pub fn genFREE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

/// Generate _symtable.CELL constant
pub fn genCELL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

/// Generate _symtable.TYPE_FUNCTION constant
pub fn genTYPE_FUNCTION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _symtable.TYPE_CLASS constant
pub fn genTYPE_CLASS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate _symtable.TYPE_MODULE constant
pub fn genTYPE_MODULE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}
