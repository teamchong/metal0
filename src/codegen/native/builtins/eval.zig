/// eval() and exec() builtins - wire to AST executor
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for eval(source)
/// Calls runtime.eval() which uses AST executor
pub fn genEval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return error.OutOfMemory; // eval() requires exactly 1 argument
    }

    // Generate: try runtime.eval(allocator, source_code)
    try self.output.appendSlice(self.allocator, "try runtime.eval(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for exec(source)
/// Calls runtime.exec() which uses AST executor (no return value)
pub fn genExec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return error.OutOfMemory; // exec() requires exactly 1 argument
    }

    // Generate: try runtime.exec(allocator, source_code)
    try self.output.appendSlice(self.allocator, "try runtime.exec(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}
