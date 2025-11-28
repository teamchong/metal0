/// IO module codegen - StringIO, BytesIO
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Generate io.StringIO() constructor
pub fn genStringIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.StringIO.create(allocator)");
    } else {
        try self.emit("try runtime.io.StringIO.createWithValue(allocator, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}

/// Generate io.BytesIO() constructor
pub fn genBytesIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.BytesIO.create(allocator)");
    } else {
        try self.emit("try runtime.io.BytesIO.createWithValue(allocator, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}

/// Generate io.open() - same as builtin open()
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genOpen(self, args);
}
