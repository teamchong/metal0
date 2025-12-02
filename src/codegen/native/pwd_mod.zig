/// Python pwd module - Unix password database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getpwnam", genConst(".{ .pw_name = \"\", .pw_passwd = \"x\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"/\", .pw_shell = \"/bin/sh\" }") },
    .{ "getpwuid", genConst(".{ .pw_name = \"\", .pw_passwd = \"x\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"/\", .pw_shell = \"/bin/sh\" }") },
    .{ "getpwall", genConst("&[_]@TypeOf(.{ .pw_name = \"\", .pw_passwd = \"\", .pw_uid = @as(u32, 0), .pw_gid = @as(u32, 0), .pw_gecos = \"\", .pw_dir = \"\", .pw_shell = \"\" }){}") },
    .{ "struct_passwd", genConst("struct { pw_name: []const u8, pw_passwd: []const u8, pw_uid: u32, pw_gid: u32, pw_gecos: []const u8, pw_dir: []const u8, pw_shell: []const u8 }") },
});
