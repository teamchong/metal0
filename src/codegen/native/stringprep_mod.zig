/// Python stringprep module - Internet string preparation (RFC 3454)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "in_table_a1", h.c("false") }, .{ "in_table_b1", h.c("false") },
    .{ "map_table_b2", genMapTable }, .{ "map_table_b3", genMapTable },
    .{ "in_table_c11", h.c("false") }, .{ "in_table_c12", h.c("false") }, .{ "in_table_c11_c12", h.c("false") },
    .{ "in_table_c21", h.c("false") }, .{ "in_table_c22", h.c("false") }, .{ "in_table_c21_c22", h.c("false") },
    .{ "in_table_c3", h.c("false") }, .{ "in_table_c4", h.c("false") }, .{ "in_table_c5", h.c("false") },
    .{ "in_table_c6", h.c("false") }, .{ "in_table_c7", h.c("false") }, .{ "in_table_c8", h.c("false") },
    .{ "in_table_c9", h.c("false") }, .{ "in_table_d1", h.c("false") }, .{ "in_table_d2", h.c("false") },
});

fn genMapTable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
