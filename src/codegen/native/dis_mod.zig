/// Python dis module - Disassembler for Python bytecode
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dis", genDis },
    .{ "disassemble", genDisassemble },
    .{ "distb", genDistb },
    .{ "disco", genDisco },
    .{ "code_info", genCodeInfo },
    .{ "show_code", genShowCode },
    .{ "get_instructions", genGetInstructions },
    .{ "findlinestarts", genFindlinestarts },
    .{ "findlabels", genFindlabels },
    .{ "stack_effect", genStackEffect },
    .{ "Bytecode", genBytecode },
    .{ "Instruction", genInstruction },
    .{ "HAVE_ARGUMENT", genHaveArgument },
    .{ "EXTENDED_ARG", genExtendedArg },
});

fn genDis(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDisassemble(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDistb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDisco(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genCodeInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genShowCode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetInstructions(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }){}"), builder_mod.EmitConfig.forExpression());
}

fn genFindlinestarts(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]struct { offset: i32, line: i32 }{}"), builder_mod.EmitConfig.forExpression());
}

fn genFindlabels(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]i32{}"), builder_mod.EmitConfig.forExpression());
}

fn genStackEffect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genBytecode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .codeobj = @as(?*anyopaque, null), .first_line = @as(i32, 0), .current_offset = @as(?i32, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genInstruction(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }"), builder_mod.EmitConfig.forExpression());
}

fn genHaveArgument(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(90), builder_mod.EmitConfig.forExpression());
}

fn genExtendedArg(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(144), builder_mod.EmitConfig.forExpression());
}
