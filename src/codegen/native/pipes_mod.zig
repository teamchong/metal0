/// Python pipes module - Interface to shell pipelines (deprecated in 3.11)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Template", h.c(".{ .steps = &[_][]const u8{}, .debugging = false }") }, .{ "reset", h.c("{}") },
    .{ "clone", h.c(".{ .steps = &[_][]const u8{}, .debugging = false }") }, .{ "debug", h.c("{}") },
    .{ "append", h.c("{}") }, .{ "prepend", h.c("{}") }, .{ "open", h.c("null") }, .{ "copy", h.c("{}") },
    .{ "FILEIN_FILEOUT", h.c("\"ff\"") }, .{ "STDIN_FILEOUT", h.c("\"-f\"") },
    .{ "FILEIN_STDOUT", h.c("\"f-\"") }, .{ "STDIN_STDOUT", h.c("\"--\"") },
    .{ "quote", genQuote },
});

fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; _ = s; break :blk \"''\"; }"); }
    else try self.emit("\"''\"");
}
