/// Python grp module - Unix group database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getgrnam", genGroup }, .{ "getgrgid", genGroup }, .{ "getgrall", genGroupList }, .{ "struct_group", genGroupType },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genGroup(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .gr_name = \"\", .gr_passwd = \"x\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }"); }
fn genGroupList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{ .gr_name = \"\", .gr_passwd = \"\", .gr_gid = @as(u32, 0), .gr_mem = &[_][]const u8{} }){}"); }
fn genGroupType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { gr_name: []const u8, gr_passwd: []const u8, gr_gid: u32, gr_mem: []const []const u8 }"); }
