/// Python code module - Interactive interpreter base classes
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "InteractiveConsole", genInteractiveConsole },
    .{ "InteractiveInterpreter", genInteractiveInterpreter },
    .{ "compile_command", genCompileCommand },
    .{ "interact", genInteract },
});

fn genInteractiveConsole(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .locals = @as(?*anyopaque, null), .filename = \"<console>\" }"), builder_mod.EmitConfig.forExpression());
}

fn genInteractiveInterpreter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .locals = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genCompileCommand(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genInteract(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

