/// Python this module - The Zen of Python easter egg
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "s", genS },
    .{ "d", genD },
});

fn genS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const zen = builder_mod.ZigValue.string("Gur Mra bs Clguba, ol Gvz Crgref...");
    try b.emitValue(zen, builder_mod.EmitConfig.forExpression());
}

fn genD(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const empty = builder_mod.ZigValue.raw(".{}");
    try b.emitValue(empty, builder_mod.EmitConfig.forExpression());
}
