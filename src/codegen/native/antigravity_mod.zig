/// Python antigravity module - Easter egg (opens xkcd comic)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "init", genInit },
    .{ "geohash", genGeohash },
});

fn genInit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const empty_struct = builder_mod.ZigValue.raw("{}");
    try b.emitValue(empty_struct, builder_mod.EmitConfig.forExpression());
}

fn genGeohash(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const zero = builder_mod.ZigValue.float(0.0);
    try b.emitValue(zero, builder_mod.EmitConfig.forExpression());
}
