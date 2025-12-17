/// Python codeop module - Compile Python code with compiler flags
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile_command", genCompileCommand },
    .{ "Compile", genCompile },
    .{ "CommandCompiler", genCommandCompiler },
    .{ "PyCF_DONT_IMPLY_DEDENT", genPyCfDontImplyDedent },
    .{ "PyCF_ALLOW_INCOMPLETE_INPUT", genPyCfAllowIncompleteInput },
});

fn genCompileCommand(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genCompile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .flags = @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genCommandCompiler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .compiler = .{ .flags = @as(i32, 0) } }"), builder_mod.EmitConfig.forExpression());
}

fn genPyCfDontImplyDedent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x200), builder_mod.EmitConfig.forExpression());
}

fn genPyCfAllowIncompleteInput(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x4000), builder_mod.EmitConfig.forExpression());
}

