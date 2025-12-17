/// Python cmd module - Command-line interpreter framework
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Cmd", genCmd },
});

fn genCmd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const cmd_struct = builder_mod.ZigValue.raw(".{ .prompt = \"(Cmd) \", .intro = null, .identchars = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\", .ruler = \"=\", .lastcmd = \"\", .cmdqueue = &[_][]const u8{}, .completekey = \"tab\", .use_rawinput = true }");
    try b.emitValue(cmd_struct, builder_mod.EmitConfig.forExpression());
}
