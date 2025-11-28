/// Python tomllib module - Parse TOML files (Python 3.11+)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate tomllib.load(fp, /, *, parse_float=float)
pub fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const fp = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = fp; break :blk .{}; }");
    } else {
        try self.emit(".{}");
    }
}

/// Generate tomllib.loads(s, /, *, parse_float=float)
pub fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const s = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = s; break :blk .{}; }");
    } else {
        try self.emit(".{}");
    }
}

/// Generate tomllib.TOMLDecodeError
pub fn genTOMLDecodeError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TOMLDecodeError");
}
