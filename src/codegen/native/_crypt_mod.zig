/// Python _crypt module - Unix crypt() password hashing
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "crypt", genCrypt },
});

fn genCrypt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const empty_str = builder_mod.ZigValue.string("");
    try b.emitValue(empty_str, builder_mod.EmitConfig.forExpression());
}
