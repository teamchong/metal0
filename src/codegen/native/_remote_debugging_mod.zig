/// Python _remote_debugging module - Remote debugging support
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_state", genGetState },
});

fn genGetState(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const null_val = builder_mod.ZigValue.null_();
    try b.emitValue(null_val, builder_mod.EmitConfig.forExpression());
}
