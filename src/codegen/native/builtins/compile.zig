const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 3) return error.OutOfMemory;
    try self.emit("try runtime.compile_builtin(allocator, ");
    try self.genExpr(args[0]); // source
    try self.emit(", ");
    try self.genExpr(args[1]); // filename
    try self.emit(", ");
    try self.genExpr(args[2]); // mode
    try self.emit(")");
}
