/// Python imghdr module - Image file type determination
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "what", genWhat },
    .{ "tests", genTests },
});

fn genWhat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?[]const u8, null)"), builder_mod.EmitConfig.forExpression());
}

fn genTests(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*const fn ([]const u8, *anyopaque) ?[]const u8{}"), builder_mod.EmitConfig.forExpression());
}
