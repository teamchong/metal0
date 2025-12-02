/// Python spwd module - Shadow password database
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getspnam", genGetspnam },
    .{ "getspall", genGetspall },
    .{ "struct_spwd", genStructSpwd },
});

/// Generate spwd.getspnam(name) - Get shadow password entry by username
pub fn genGetspnam(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate spwd.getspall() - Get all shadow password entries
pub fn genGetspall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate spwd.struct_spwd type
pub fn genStructSpwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .sp_namp = \"\", .sp_pwdp = \"\", .sp_lstchg = 0, .sp_min = 0, .sp_max = 0, .sp_warn = 0, .sp_inact = 0, .sp_expire = 0, .sp_flag = 0 }");
}
