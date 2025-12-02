/// Python inspect module - Runtime inspection
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const genIsabstract = h.c("false");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "isclass", h.c("false") }, .{ "isfunction", h.c("false") }, .{ "ismethod", h.c("false") },
    .{ "ismodule", h.c("false") }, .{ "isbuiltin", h.c("false") }, .{ "isroutine", h.c("false") },
    .{ "isabstract", h.c("false") }, .{ "isgenerator", h.c("false") }, .{ "iscoroutine", h.c("false") },
    .{ "isasyncgen", h.c("false") }, .{ "isdatadescriptor", h.c("false") },
    .{ "iscoroutinefunction", h.c("false") }, .{ "isgeneratorfunction", h.c("false") }, .{ "isasyncgenfunction", h.c("false") },
    .{ "getmembers", h.c("&[_]struct { name: []const u8, value: []const u8 }{}") },
    .{ "getmodule", h.c("@as(?*anyopaque, null)") },
    .{ "getfile", h.c("\"<compiled>\"") },
    .{ "getsourcefile", h.c("@as(?[]const u8, null)") },
    .{ "getsourcelines", h.c(".{ &[_][]const u8{}, @as(i64, 0) }") },
    .{ "getsource", h.c("\"\"") },
    .{ "getdoc", h.c("@as(?[]const u8, null)") },
    .{ "getcomments", h.c("@as(?[]const u8, null)") },
    .{ "signature", h.c("struct { parameters: []const u8 = \"\", return_annotation: ?[]const u8 = null, pub fn bind(self: @This(), a: anytype) @This() { _ = a; return @This(){}; } }{}") },
    .{ "Parameter", h.c("struct { name: []const u8, kind: i64 = 0, default: ?[]const u8 = null, annotation: ?[]const u8 = null, pub const POSITIONAL_ONLY: i64 = 0; pub const POSITIONAL_OR_KEYWORD: i64 = 1; pub const VAR_POSITIONAL: i64 = 2; pub const KEYWORD_ONLY: i64 = 3; pub const VAR_KEYWORD: i64 = 4; pub const empty: ?[]const u8 = null; }{ .name = \"\" }") },
    .{ "currentframe", h.c("@as(?*anyopaque, null)") },
    .{ "stack", h.c("&[_]struct { frame: ?*anyopaque, filename: []const u8, lineno: i64, function: []const u8 }{}") },
    .{ "getargspec", h.c(".{ .args = &[_][]const u8{}, .varargs = null, .varkw = null, .defaults = null }") },
    .{ "getfullargspec", h.c("struct { args: [][]const u8 = &[_][]const u8{}, varargs: ?[]const u8 = null, varkw: ?[]const u8 = null, defaults: ?[][]const u8 = null, kwonlyargs: [][]const u8 = &[_][]const u8{}, kwonlydefaults: ?hashmap_helper.StringHashMap([]const u8) = null, annotations: hashmap_helper.StringHashMap([]const u8) = .{} }{}") },
    .{ "getattr_static", h.c("@as(?*anyopaque, null)") },
    .{ "unwrap", genUnwrap },
});

fn genUnwrap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
