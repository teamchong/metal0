/// Python contextvars module - Context Variables
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ContextVar", genContextVar }, .{ "Token", h.c(".{ .var = null, .old_value = null }") },
    .{ "Context", h.c(".{ .data = metal0_runtime.PyDict([]const u8, ?anyopaque).init() }") },
    .{ "copy_context", h.c(".{ .data = metal0_runtime.PyDict([]const u8, ?anyopaque).init() }") },
});

fn genContextVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .value = null }; }"); } else try self.emit(".{ .name = \"\", .value = null }");
}
