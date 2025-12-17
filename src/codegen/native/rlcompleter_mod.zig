/// Python rlcompleter module - Readline completion support
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Completer", genCompleter },
});

fn genCompleter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const completer = builder_mod.ZigValue.raw(".{ .namespace = .{}, .use_main_ns = @as(i32, 0) }");
    try b.emitValue(completer, builder_mod.EmitConfig.forExpression());
}
