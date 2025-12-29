const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

/// Helper context for compile builtin
const CompileCtx = struct { a: []ast.Node };

/// Helper: emit compile_builtin args
fn emitCompileArgs(s: *NativeCodegen, ctx: CompileCtx) CodegenError!void {
    try s.emit("__global_allocator, ");
    try s.genExpr(ctx.a[0]); // source
    try s.emit(", ");
    try s.genExpr(ctx.a[1]); // filename
    try s.emit(", ");
    try s.genExpr(ctx.a[2]); // mode
    try s.emit(", ");
    // flags parameter (optional, default 0)
    if (ctx.a.len >= 4) {
        try s.genExpr(ctx.a[3]);
    } else {
        try s.emit("0");
    }
}

pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // compile(source, filename, mode, [flags, [dont_inherit, [optimize]]])
    // We require at least source, filename, and mode (first 3 args)
    if (args.len < 3) {
        // For tests that call compile() with fewer args, emit a stub
        try self.emit("(blk_compile: { @panic(\"compile() requires at least 3 arguments\"); })");
        return;
    }
    // In assertRaises context, don't emit try - let error propagate as error union
    if (self.in_assert_raises_context) {
        try self.emitCallCtx("runtime.compile_builtin", CompileCtx{ .a = args }, emitCompileArgs);
    } else {
        try self.emitCallCtx("try runtime.compile_builtin", CompileCtx{ .a = args }, emitCompileArgs);
    }
}
