/// Python _uuid module - Internal UUID support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getnode", genGetnode },
    .{ "generate_time_safe", genGenerateTimeSafe },
    .{ "uuid_create", genUuidCreate },
    .{ "has_uuid_generate_time_safe", genHasUuidGenerateTimeSafe },
});

fn genGetnode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGenerateTimeSafe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\\x00\" ** 16, @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genUuidCreate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\x00\" ** 16"), builder_mod.EmitConfig.forExpression());
}

fn genHasUuidGenerateTimeSafe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

