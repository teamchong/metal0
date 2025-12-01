/// Python dis module - Disassembler for Python bytecode
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dis", genDis },
    .{ "disassemble", genDisassemble },
    .{ "distb", genDistb },
    .{ "disco", genDisco },
    .{ "code_info", genCode_info },
    .{ "show_code", genShow_code },
    .{ "get_instructions", genGet_instructions },
    .{ "findlinestarts", genFindlinestarts },
    .{ "findlabels", genFindlabels },
    .{ "stack_effect", genStack_effect },
    .{ "Bytecode", genBytecode },
    .{ "Instruction", genInstruction },
    .{ "HAVE_ARGUMENT", genHAVE_ARGUMENT },
    .{ "EXTENDED_ARG", genEXTENDED_ARG },
});

/// Generate dis.dis(x=None, file=None, depth=None, ...)
pub fn genDis(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate dis.disassemble(co, lasti=-1, file=None)
pub fn genDisassemble(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate dis.distb(tb=None, file=None)
pub fn genDistb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate dis.disco(co, lasti=-1, file=None) - alias for disassemble
pub fn genDisco(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate dis.code_info(x)
pub fn genCode_info(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate dis.show_code(co, file=None)
pub fn genShow_code(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate dis.get_instructions(x, first_line=None, ...)
pub fn genGet_instructions(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }){}");
}

/// Generate dis.findlinestarts(code)
pub fn genFindlinestarts(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { offset: i32, line: i32 }{}");
}

/// Generate dis.findlabels(code)
pub fn genFindlabels(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i32{}");
}

/// Generate dis.stack_effect(opcode, oparg=None, jump=None)
pub fn genStack_effect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate dis.Bytecode class
pub fn genBytecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .codeobj = @as(?*anyopaque, null), .first_line = @as(i32, 0), .current_offset = @as(?i32, null) }");
}

/// Generate dis.Instruction named tuple
pub fn genInstruction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }");
}

// ============================================================================
// Opcode constants (selected important ones)
// ============================================================================

pub fn genHAVE_ARGUMENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 90)");
}

pub fn genEXTENDED_ARG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 144)");
}
