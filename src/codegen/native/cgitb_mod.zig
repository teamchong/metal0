/// Python cgitb module - Traceback manager for CGI scripts (deprecated 3.11)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "enable", genUnit }, .{ "handler", genUnit }, .{ "text", genEmptyStr }, .{ "html", genHtml }, .{ "reset", genUnit }, .{ "Hook", genHook },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genHtml(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"<html></html>\""); }
fn genHook(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .display = 1, .logdir = null, .context = 5, .file = null, .format = \"html\" }"); }
