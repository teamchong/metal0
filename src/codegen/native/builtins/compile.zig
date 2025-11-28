const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // compile(source, filename, mode, [flags, [dont_inherit, [optimize]]])
    // We require at least source, filename, and mode (first 3 args)
    if (args.len < 3) {
        // For tests that call compile() with fewer args, emit a stub
        try self.emit("@compileError(\"compile() requires at least 3 arguments\")");
        return;
    }
    try self.emit("try runtime.compile_builtin(__global_allocator, ");
    try self.genExpr(args[0]); // source
    try self.emit(", ");
    try self.genExpr(args[1]); // filename
    try self.emit(", ");
    try self.genExpr(args[2]); // mode
    try self.emit(")");
}
