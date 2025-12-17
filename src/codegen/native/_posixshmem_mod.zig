/// Python _posixshmem module - POSIX shared memory
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "shm_open", genShmOpen },
    .{ "shm_unlink", genShmUnlink },
});

fn genShmOpen(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const neg_one = builder_mod.ZigValue.int(-1);
    try b.emitValue(neg_one, builder_mod.EmitConfig.forExpression());
}

fn genShmUnlink(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const empty_struct = builder_mod.ZigValue.raw("{}");
    try b.emitValue(empty_struct, builder_mod.EmitConfig.forExpression());
}
