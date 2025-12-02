/// Python _functools module - C accelerator for functools (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "reduce", genReduce }, .{ "cmp_to_key", genCmpToKey },
});

fn genReduce(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { var result = ");
        if (args.len > 2) try self.genExpr(args[2]) else try self.emit("null");
        try self.emit("; const items = "); try self.genExpr(args[1]); try self.emit("; _ = items; break :blk result; }");
    } else try self.emit("null");
}

fn genCmpToKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const cmp = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .cmp = cmp }; }"); } else { try self.emit(".{}"); }
}
