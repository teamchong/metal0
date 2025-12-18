/// Python opcode module - Opcode definitions for Python bytecode
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "opname", genOpname },
    .{ "opmap", genOpmap },
    .{ "cmp_op", genCmpOp },
    .{ "hasarg", genEmptyU8Array },
    .{ "hasconst", genHasconst },
    .{ "hasname", genHasname },
    .{ "hasjrel", genHasjrel },
    .{ "hasjabs", genEmptyU8Array },
    .{ "haslocal", genHaslocal },
    .{ "hascompare", genHascompare },
    .{ "hasfree", genHasfree },
    .{ "hasexc", genHasexc },
    .{ "HAVE_ARGUMENT", genHaveArgument },
    .{ "EXTENDED_ARG", genExtendedArg },
    .{ "stack_effect", genStackEffect },
    .{ "_specialized_opmap", genEmptyStruct },
    .{ "_intrinsic_1_descs", genIntrinsic1Descs },
    .{ "_intrinsic_2_descs", genIntrinsic2Descs },
});

fn genOpname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"CACHE\", \"POP_TOP\", \"PUSH_NULL\", \"INTERPRETER_EXIT\", \"END_FOR\", \"END_SEND\", \"<6>\", \"<7>\", \"<8>\", \"NOP\", \"<10>\", \"UNARY_NEGATIVE\", \"UNARY_NOT\", \"<13>\", \"<14>\", \"UNARY_INVERT\", \"EXIT_INIT_CHECK\" }"), builder_mod.EmitConfig.forExpression());
}

fn genOpmap(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .CACHE = 0, .POP_TOP = 1, .PUSH_NULL = 2, .INTERPRETER_EXIT = 3, .END_FOR = 4, .END_SEND = 5, .NOP = 9, .UNARY_NEGATIVE = 11, .UNARY_NOT = 12, .UNARY_INVERT = 15 }"), builder_mod.EmitConfig.forExpression());
}

fn genCmpOp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"<\", \"<=\", \"==\", \"!=\", \">\", \">=\"}"), builder_mod.EmitConfig.forExpression());
}

fn genEmptyU8Array(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genHasconst(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{ 100 }"), builder_mod.EmitConfig.forExpression());
}

fn genHasname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{ 90, 91, 95, 96, 97, 98, 101, 106, 108, 109, 116 }"), builder_mod.EmitConfig.forExpression());
}

fn genHasjrel(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{ 93, 110, 111, 112, 114, 115, 120, 149, 172 }"), builder_mod.EmitConfig.forExpression());
}

fn genHaslocal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{ 124, 125, 126, 180 }"), builder_mod.EmitConfig.forExpression());
}

fn genHascompare(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{ 107 }"), builder_mod.EmitConfig.forExpression());
}

fn genHasfree(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{ 135, 136, 137, 138 }"), builder_mod.EmitConfig.forExpression());
}

fn genHasexc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{ 121 }"), builder_mod.EmitConfig.forExpression());
}

fn genHaveArgument(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 90)"), builder_mod.EmitConfig.forExpression());
}

fn genExtendedArg(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 144)"), builder_mod.EmitConfig.forExpression());
}

fn genStackEffect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genEmptyStruct(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genIntrinsic1Descs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"INTRINSIC_1_INVALID\", \"INTRINSIC_PRINT\", \"INTRINSIC_IMPORT_STAR\", \"INTRINSIC_STOPITERATION_ERROR\", \"INTRINSIC_ASYNC_GEN_WRAP\", \"INTRINSIC_UNARY_POSITIVE\", \"INTRINSIC_LIST_TO_TUPLE\", \"INTRINSIC_TYPEVAR\", \"INTRINSIC_PARAMSPEC\", \"INTRINSIC_TYPEVARTUPLE\", \"INTRINSIC_SUBSCRIPT_GENERIC\", \"INTRINSIC_TYPEALIAS\" }"), builder_mod.EmitConfig.forExpression());
}

fn genIntrinsic2Descs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"INTRINSIC_2_INVALID\", \"INTRINSIC_PREP_RERAISE_STAR\", \"INTRINSIC_TYPEVAR_WITH_BOUND\", \"INTRINSIC_TYPEVAR_WITH_CONSTRAINTS\", \"INTRINSIC_SET_FUNCTION_TYPE_PARAMS\" }"), builder_mod.EmitConfig.forExpression());
}
