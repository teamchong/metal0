/// Python _posixsubprocess module - Internal posixsubprocess support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "fork_exec", genForkExec },
    .{ "cloexec_pipe", genCloexecPipe },
});

fn genForkExec(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-1), builder_mod.EmitConfig.forExpression());
}

fn genCloexecPipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i32, -1), @as(i32, -1) }"), builder_mod.EmitConfig.forExpression());
}
