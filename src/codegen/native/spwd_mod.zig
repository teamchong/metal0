/// Python spwd module - Shadow password database
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getspnam", genGetspnam },
    .{ "getspall", genGetspall },
    .{ "struct_spwd", genStructSpwd },
});

fn genGetspnam(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genGetspall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genStructSpwd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .sp_namp = \"\", .sp_pwdp = \"\", .sp_lstchg = 0, .sp_min = 0, .sp_max = 0, .sp_warn = 0, .sp_inact = 0, .sp_expire = 0, .sp_flag = 0 }"), builder_mod.EmitConfig.forExpression());
}
