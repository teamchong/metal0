/// Python pydoc_data module - Pydoc data files
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "topics", genTopics },
});

fn genTopics(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const empty_struct = builder_mod.ZigValue.raw(".{}");
    try b.emitValue(empty_struct, builder_mod.EmitConfig.forExpression());
}
