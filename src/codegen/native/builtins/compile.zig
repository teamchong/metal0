const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");

pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // compile(source, filename, mode, [flags, [dont_inherit, [optimize]]])
    // We require at least source, filename, and mode (first 3 args)
    if (args.len < 3) {
        // For tests that call compile() with fewer args, emit a stub
        const b = try self.getBuilder();
        try b.write("(blk_compile: { @panic(\"compile() requires at least 3 arguments\"); })");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    {
        const b = try self.getBuilder();
        try b.write("try runtime.compile_builtin(__global_allocator, ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]); // source
    {
        const b = try self.getBuilder();
        try b.write(", ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]); // filename
    {
        const b = try self.getBuilder();
        try b.write(", ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[2]); // mode
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}
