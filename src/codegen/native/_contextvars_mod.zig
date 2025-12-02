/// Python _contextvars module - Internal contextvars support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "context_var", genContextVar }, .{ "context", h.c(".{}") }, .{ "token", h.c(".{ .var = null, .old_value = null, .used = false }") },
    .{ "copy_context", h.c(".{}") }, .{ "get", h.c("null") }, .{ "set", h.c(".{ .var = null, .old_value = null, .used = false }") },
    .{ "reset", h.c("{}") }, .{ "run", h.c("null") }, .{ "copy", h.c(".{}") },
});

fn genContextVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .default = null }; }"); } else { try self.emit(".{ .name = \"\", .default = null }"); }
}
