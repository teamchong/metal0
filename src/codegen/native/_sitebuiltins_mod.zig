/// Python _sitebuiltins module - Internal site builtins support
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "quitter", genQuitter },
    .{ "printer", genPrinter },
    .{ "helper", genHelper },
});

fn genQuitter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"quit\", .eof = \"Ctrl-D (i.e. EOF)\" }"), builder_mod.EmitConfig.forExpression());
}

fn genPrinter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .data = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genHelper(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}
