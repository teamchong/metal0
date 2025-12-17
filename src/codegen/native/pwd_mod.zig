/// Python pwd module - Unix password database access
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getpwnam", genGetpwnam },
    .{ "getpwuid", genGetpwuid },
    .{ "getpwall", genGetpwall },
    .{ "struct_passwd", genStructPasswd },
});

fn genGetpwnam(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .pw_name = \"\", .pw_passwd = \"x\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"/\", .pw_shell = \"/bin/sh\" }"), builder_mod.EmitConfig.forExpression());
}

fn genGetpwuid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .pw_name = \"\", .pw_passwd = \"x\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"/\", .pw_shell = \"/bin/sh\" }"), builder_mod.EmitConfig.forExpression());
}

fn genGetpwall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{ .pw_name = \"\", .pw_passwd = \"\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"\", .pw_shell = \"\" }){}"), builder_mod.EmitConfig.forExpression());
}

fn genStructPasswd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { pw_name: []const u8, pw_passwd: []const u8, pw_uid: u32, pw_gid: u32, pw_gecos: []const u8, pw_dir: []const u8, pw_shell: []const u8 }"), builder_mod.EmitConfig.forExpression());
}

