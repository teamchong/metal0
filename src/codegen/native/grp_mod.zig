/// Python grp module - Unix group database access
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getgrnam", genGetgrnam },
    .{ "getgrgid", genGetgrgid },
    .{ "getgrall", genGetgrall },
    .{ "struct_group", genStructGroup },
});

fn genGetgrnam(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }"), builder_mod.EmitConfig.forExpression());
}

fn genGetgrgid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }"), builder_mod.EmitConfig.forExpression());
}

fn genGetgrall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{ .gr_name = \"\", .gr_passwd = \"\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }){}"), builder_mod.EmitConfig.forExpression());
}

fn genStructGroup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { gr_name: []const u8, gr_passwd: []const u8, gr_gid: u32, gr_mem: []const []const u8 }"), builder_mod.EmitConfig.forExpression());
}

