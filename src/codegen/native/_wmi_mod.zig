/// Python _wmi module - Windows Management Instrumentation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "exec_query", genExecQuery },
});

fn genExecQuery(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const empty_array = builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}");
    try b.emitValue(empty_array, builder_mod.EmitConfig.forExpression());
}
