/// Python pydoc module - Documentation generation and display
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "help", genUnit }, .{ "doc", genUnit }, .{ "writedoc", genUnit }, .{ "writedocs", genUnit },
    .{ "render_doc", genEmptyStr }, .{ "plain", genPlain }, .{ "describe", genDescribe },
    .{ "locate", genNull }, .{ "resolve", genResolve }, .{ "getdoc", genEmptyStr },
    .{ "splitdoc", genSplitdoc }, .{ "classname", genDescribe }, .{ "isdata", genFalse },
    .{ "ispackage", genFalse }, .{ "source_synopsis", genNull }, .{ "synopsis", genNull },
    .{ "allmethods", genEmpty }, .{ "apropos", genUnit }, .{ "serve", genUnit }, .{ "browse", genUnit },
});

fn genPlain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}
fn genDescribe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"object\""); }
fn genResolve(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ null, \"\" }"); }
fn genSplitdoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", \"\" }"); }
