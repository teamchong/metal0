/// Python mailcap module - Mailcap file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "findmatch", genConst("@as(?@TypeOf(.{ \"\", .{} }), null)") }, .{ "getcaps", genConst(".{}") },
    .{ "listmailcapfiles", genConst("&[_][]const u8{}") }, .{ "readmailcapfile", genConst(".{}") },
    .{ "lookup", genConst("&[_].{ []const u8, .{} }{}") }, .{ "subst", genConst("\"\"") },
});
