/// Python grp module - Unix group database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getgrnam", genConst(".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }") },
    .{ "getgrgid", genConst(".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }") },
    .{ "getgrall", genConst("&[_]@TypeOf(.{ .gr_name = \"\", .gr_passwd = \"\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }){}") },
    .{ "struct_group", genConst("struct { gr_name: []const u8, gr_passwd: []const u8, gr_gid: u32, gr_mem: []const []const u8 }") },
});
