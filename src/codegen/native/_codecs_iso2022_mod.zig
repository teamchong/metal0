/// Python _codecs_MODULE module - ISO 2022 codecs
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcodec", genGetcodec },
});

fn genGetcodec(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const codec = builder_mod.ZigValue.raw(".{ .name = \"iso2022_jp\" }");
    try b.emitValue(codec, builder_mod.EmitConfig.forExpression());
}
