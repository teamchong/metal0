/// Python _pylong module - Pure Python long integer implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _pylong.int_to_decimal_string(n)
pub fn genIntToDecimalString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const n = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = n; break :blk \"0\"; }");
    } else {
        try self.emit("\"0\"");
    }
}

/// Generate _pylong.int_from_string(s, base=10)
pub fn genIntFromString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}
