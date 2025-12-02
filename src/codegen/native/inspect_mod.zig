/// Python inspect module - Runtime inspection
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "isclass", genFalse }, .{ "isfunction", genFalse }, .{ "ismethod", genFalse },
    .{ "ismodule", genFalse }, .{ "isbuiltin", genFalse }, .{ "isroutine", genFalse },
    .{ "isabstract", genFalse }, .{ "isgenerator", genFalse }, .{ "iscoroutine", genFalse },
    .{ "isasyncgen", genFalse }, .{ "isdatadescriptor", genFalse },
    .{ "iscoroutinefunction", genFalse }, .{ "isgeneratorfunction", genFalse }, .{ "isasyncgenfunction", genFalse },
    .{ "getmembers", genEmptyMembers }, .{ "getmodule", genNull }, .{ "getfile", genCompiled },
    .{ "getsourcefile", genNullStr }, .{ "getsourcelines", genSourceLines }, .{ "getsource", genEmptyStr },
    .{ "getdoc", genNullStr }, .{ "getcomments", genNullStr },
    .{ "signature", genSignature }, .{ "Parameter", genParameter },
    .{ "currentframe", genNull }, .{ "stack", genEmptyStack },
    .{ "getargspec", genArgspec }, .{ "getfullargspec", genFullargspec },
    .{ "getattr_static", genNull }, .{ "unwrap", genUnwrap },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
pub fn genIsabstract(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genNullStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?[]const u8, null)"); }
fn genCompiled(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"<compiled>\""); }
fn genEmptyMembers(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]struct { name: []const u8, value: []const u8 }{}"); }
fn genSourceLines(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ &[_][]const u8{}, @as(i64, 0) }"); }
fn genEmptyStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]struct { frame: ?*anyopaque, filename: []const u8, lineno: i64, function: []const u8 }{}"); }
fn genArgspec(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .args = &[_][]const u8{}, .varargs = null, .varkw = null, .defaults = null }"); }

// Complex types
fn genSignature(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { parameters: []const u8 = \"\", return_annotation: ?[]const u8 = null, pub fn bind(self: @This(), a: anytype) @This() { _ = a; return @This(){}; } }{}");
}

fn genParameter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { name: []const u8, kind: i64 = 0, default: ?[]const u8 = null, annotation: ?[]const u8 = null, pub const POSITIONAL_ONLY: i64 = 0; pub const POSITIONAL_OR_KEYWORD: i64 = 1; pub const VAR_POSITIONAL: i64 = 2; pub const KEYWORD_ONLY: i64 = 3; pub const VAR_KEYWORD: i64 = 4; pub const empty: ?[]const u8 = null; }{ .name = \"\" }");
}

fn genFullargspec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { args: [][]const u8 = &[_][]const u8{}, varargs: ?[]const u8 = null, varkw: ?[]const u8 = null, defaults: ?[][]const u8 = null, kwonlyargs: [][]const u8 = &[_][]const u8{}, kwonlydefaults: ?hashmap_helper.StringHashMap([]const u8) = null, annotations: hashmap_helper.StringHashMap([]const u8) = .{} }{}");
}

fn genUnwrap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
