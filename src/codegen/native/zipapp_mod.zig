/// Python zipapp module - Manage executable Python zip archives
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "create_archive", genCreateArchive },
    .{ "get_interpreter", genGetInterpreter },
});

fn genCreateArchive(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetInterpreter(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}
