const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // compile(source, filename, mode, [flags, [dont_inherit, [optimize]]])
    // We require at least source, filename, and mode (first 3 args)
    if (args.len < 3) {
        // For tests that call compile() with fewer args, emit a stub
        try emitConst(self, "(blk_compile: { @panic(\"compile() requires at least 3 arguments\"); })");
        return;
    }
    try emitConst(self, "try runtime.compile_builtin(__global_allocator, ");
    try self.genExpr(args[0]); // source
    try emitConst(self, ", ");
    try self.genExpr(args[1]); // filename
    try emitConst(self, ", ");
    try self.genExpr(args[2]); // mode
    try emitConst(self, ")");
}
