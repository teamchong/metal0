/// Python _functools module - C accelerator for functools (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reduce", genReduce }, .{ "cmp_to_key", h.wrap("blk: { const cmp = ", "; break :blk .{ .cmp = cmp }; }", ".{}") },
});

fn genReduce(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { var result = ");
        if (args.len > 2) try self.genExpr(args[2]) else try self.emit("null");
        try self.emit("; const items = "); try self.genExpr(args[1]); try self.emit("; _ = items; break :blk result; }");
    } else try self.emit("null");
}
