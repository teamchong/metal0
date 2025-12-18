/// Python py_compile module - Compile Python source files
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile", genCompile },
    .{ "main", genMain },
    .{ "PyCompileError", genPyCompileError },
    .{ "PycInvalidationMode", genPycInvalidationMode },
});

fn genCompile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?[]const u8, null)"), builder_mod.EmitConfig.forExpression());
}

fn genMain(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genPyCompileError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.PyCompileError"), builder_mod.EmitConfig.forExpression());
}

fn genPycInvalidationMode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .TIMESTAMP = @as(i32, 1), .CHECKED_HASH = @as(i32, 2), .UNCHECKED_HASH = @as(i32, 3) }"), builder_mod.EmitConfig.forExpression());
}
