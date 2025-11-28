/// Python _opcode module - Internal opcode support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _opcode.stack_effect(opcode, oparg=None, *, jump=None)
pub fn genStackEffect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _opcode.is_valid(opcode)
pub fn genIsValid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _opcode.has_arg(opcode)
pub fn genHasArg(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _opcode.has_const(opcode)
pub fn genHasConst(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _opcode.has_name(opcode)
pub fn genHasName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _opcode.has_jump(opcode)
pub fn genHasJump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _opcode.has_free(opcode)
pub fn genHasFree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _opcode.has_local(opcode)
pub fn genHasLocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _opcode.has_exc(opcode)
pub fn genHasExc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}
