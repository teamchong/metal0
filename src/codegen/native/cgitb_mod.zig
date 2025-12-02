/// Python cgitb module - Traceback manager for CGI scripts (deprecated 3.11)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "enable", genConst("{}") }, .{ "handler", genConst("{}") }, .{ "text", genConst("\"\"") },
    .{ "html", genConst("\"<html></html>\"") }, .{ "reset", genConst("{}") },
    .{ "Hook", genConst(".{ .display = 1, .logdir = null, .context = 5, .file = null, .format = \"html\" }") },
});
