/// Python inspect module - Runtime inspection
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const genIsabstract = genConst("false");

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "isclass", genConst("false") }, .{ "isfunction", genConst("false") }, .{ "ismethod", genConst("false") },
    .{ "ismodule", genConst("false") }, .{ "isbuiltin", genConst("false") }, .{ "isroutine", genConst("false") },
    .{ "isabstract", genConst("false") }, .{ "isgenerator", genConst("false") }, .{ "iscoroutine", genConst("false") },
    .{ "isasyncgen", genConst("false") }, .{ "isdatadescriptor", genConst("false") },
    .{ "iscoroutinefunction", genConst("false") }, .{ "isgeneratorfunction", genConst("false") }, .{ "isasyncgenfunction", genConst("false") },
    .{ "getmembers", genConst("&[_]struct { name: []const u8, value: []const u8 }{}") },
    .{ "getmodule", genConst("@as(?*anyopaque, null)") },
    .{ "getfile", genConst("\"<compiled>\"") },
    .{ "getsourcefile", genConst("@as(?[]const u8, null)") },
    .{ "getsourcelines", genConst(".{ &[_][]const u8{}, @as(i64, 0) }") },
    .{ "getsource", genConst("\"\"") },
    .{ "getdoc", genConst("@as(?[]const u8, null)") },
    .{ "getcomments", genConst("@as(?[]const u8, null)") },
    .{ "signature", genConst("struct { parameters: []const u8 = \"\", return_annotation: ?[]const u8 = null, pub fn bind(self: @This(), a: anytype) @This() { _ = a; return @This(){}; } }{}") },
    .{ "Parameter", genConst("struct { name: []const u8, kind: i64 = 0, default: ?[]const u8 = null, annotation: ?[]const u8 = null, pub const POSITIONAL_ONLY: i64 = 0; pub const POSITIONAL_OR_KEYWORD: i64 = 1; pub const VAR_POSITIONAL: i64 = 2; pub const KEYWORD_ONLY: i64 = 3; pub const VAR_KEYWORD: i64 = 4; pub const empty: ?[]const u8 = null; }{ .name = \"\" }") },
    .{ "currentframe", genConst("@as(?*anyopaque, null)") },
    .{ "stack", genConst("&[_]struct { frame: ?*anyopaque, filename: []const u8, lineno: i64, function: []const u8 }{}") },
    .{ "getargspec", genConst(".{ .args = &[_][]const u8{}, .varargs = null, .varkw = null, .defaults = null }") },
    .{ "getfullargspec", genConst("struct { args: [][]const u8 = &[_][]const u8{}, varargs: ?[]const u8 = null, varkw: ?[]const u8 = null, defaults: ?[][]const u8 = null, kwonlyargs: [][]const u8 = &[_][]const u8{}, kwonlydefaults: ?hashmap_helper.StringHashMap([]const u8) = null, annotations: hashmap_helper.StringHashMap([]const u8) = .{} }{}") },
    .{ "getattr_static", genConst("@as(?*anyopaque, null)") },
    .{ "unwrap", genUnwrap },
});

fn genUnwrap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
