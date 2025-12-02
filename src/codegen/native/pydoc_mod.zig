/// Python pydoc module - Documentation generation and display
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "help", h.c("{}") }, .{ "doc", h.c("{}") }, .{ "writedoc", h.c("{}") }, .{ "writedocs", h.c("{}") },
    .{ "render_doc", h.c("\"\"") }, .{ "plain", genPlain }, .{ "describe", h.c("\"object\"") },
    .{ "locate", h.c("null") }, .{ "resolve", h.c(".{ null, \"\" }") }, .{ "getdoc", h.c("\"\"") },
    .{ "splitdoc", h.c(".{ \"\", \"\" }") }, .{ "classname", h.c("\"object\"") }, .{ "isdata", h.c("false") },
    .{ "ispackage", h.c("false") }, .{ "source_synopsis", h.c("null") }, .{ "synopsis", h.c("null") },
    .{ "allmethods", h.c(".{}") }, .{ "apropos", h.c("{}") }, .{ "serve", h.c("{}") }, .{ "browse", h.c("{}") },
});

fn genPlain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
