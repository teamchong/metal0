/// Python _statistics module - Internal statistics support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "normal_dist_inv_cdf", genNormalDistInvCdf },
});

fn genNormalDistInvCdf(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const zero = builder_mod.ZigValue.float(0.0);
    try b.emitValue(zero, builder_mod.EmitConfig.forExpression());
}
