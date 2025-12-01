/// Python _opcode module - Internal opcode support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "stack_effect", genStackEffect },
    .{ "is_valid", genIsValid },
    .{ "has_arg", genHasArg },
    .{ "has_const", genHasConst },
    .{ "has_name", genHasName },
    .{ "has_jump", genHasJump },
    .{ "has_free", genHasFree },
    .{ "has_local", genHasLocal },
    .{ "has_exc", genHasExc },
});

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
