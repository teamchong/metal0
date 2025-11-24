/// eval() and exec() builtins - wire to AST executor or comptime
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for comptime eval (string literal argument)
/// Registers the source code for comptime compilation
/// For now, generates a placeholder - bytecode gen is separate task
pub fn genComptimeEval(self: *NativeCodegen, source: []const u8) CodegenError!void {
    // Register this source string as a comptime eval candidate
    if (!self.comptime_evals.contains(source)) {
        const source_copy = try self.allocator.dupe(u8, source);
        try self.comptime_evals.put(source_copy, {});
    }

    // TODO: Generate actual comptime bytecode execution
    // For now, fall through to runtime eval with a marker comment
    try self.output.appendSlice(self.allocator, "// COMPTIME_EVAL: ");
    try self.output.appendSlice(self.allocator, source);
    try self.output.appendSlice(self.allocator, "\n");
    // Still generate runtime call until bytecode gen is ready
    try self.output.appendSlice(self.allocator, "try runtime.eval(allocator, \"");
    // Escape the source string for Zig string literal
    for (source) |c| {
        switch (c) {
            '"' => try self.output.appendSlice(self.allocator, "\\\""),
            '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
            '\n' => try self.output.appendSlice(self.allocator, "\\n"),
            '\r' => try self.output.appendSlice(self.allocator, "\\r"),
            '\t' => try self.output.appendSlice(self.allocator, "\\t"),
            else => try self.output.append(self.allocator, c),
        }
    }
    try self.output.appendSlice(self.allocator, "\")");
}

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
