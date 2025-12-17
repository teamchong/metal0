/// Python tomllib module - Parse TOML files (Python 3.11+)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "load", genLoad },
    .{ "loads", genLoads },
    .{ "TOMLDecodeError", genError },
});

fn genLoad(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genLoads(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.TOMLDecodeError"), builder_mod.EmitConfig.forExpression());
}
