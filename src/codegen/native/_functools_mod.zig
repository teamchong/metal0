/// Python _functools module - C accelerator for functools (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _functools.reduce(function, iterable, initializer=None)
pub fn genReduce(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { var result = ");
        if (args.len > 2) {
            try self.genExpr(args[2]);
        } else {
            try self.emit("null");
        }
        try self.emit("; const items = ");
        try self.genExpr(args[1]);
        try self.emit("; _ = items; break :blk result; }");
    } else {
        try self.emit("null");
    }
}

/// Generate _functools.cmp_to_key(mycmp)
pub fn genCmpToKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const cmp = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .cmp = cmp }; }");
    } else {
        try self.emit(".{}");
    }
}
