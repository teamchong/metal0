/// eval() and exec() builtins - wire to AST executor or comptime
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const bytecode_compiler = @import("../../bytecode.zig");

/// Generate code for comptime eval (string literal argument)
/// Compiles source to bytecode at compile time and embeds it in generated code
pub fn genComptimeEval(self: *NativeCodegen, source: []const u8) CodegenError!void {
    // Strip Python quotes from the source (AST stores lexeme with quotes)
    const eval_source = if (source.len >= 2 and
        ((source[0] == '"' and source[source.len - 1] == '"') or
        (source[0] == '\'' and source[source.len - 1] == '\'')))
        source[1 .. source.len - 1]
    else
        source;

    // Register this source string as a comptime eval candidate
    if (!self.comptime_evals.contains(eval_source)) {
        const source_copy = try self.allocator.dupe(u8, eval_source);
        try self.comptime_evals.put(source_copy, {});
    }

    // Compile source to bytecode at compile time
    const program = bytecode_compiler.compileSource(self.allocator, eval_source) catch |err| {
        // If bytecode compilation fails, fall back to runtime eval
        std.debug.print("comptime eval fallback for '{s}': {}\n", .{ eval_source, err });
        try self.output.appendSlice(self.allocator, "try runtime.eval(allocator, \"");
        try escapeZigString(self, eval_source);
        try self.output.appendSlice(self.allocator, "\")");
        return;
    };
    defer {
        // Free the instructions and constants since we've serialized them
        self.allocator.free(program.instructions);
        self.allocator.free(program.constants);
    }

    // Generate unique identifier for this bytecode blob
    const blob_id = self.comptime_evals.count();

    // Generate embedded bytecode execution:
    // {
    //     const _bytecode_N = [_]u8{ ... };
    //     var _program_N = runtime.BytecodeProgram.deserialize(allocator, &_bytecode_N) catch unreachable;
    //     defer _program_N.deinit();
    //     var _vm_N = runtime.BytecodeVM.init(allocator);
    //     defer _vm_N.deinit();
    //     _vm_N.execute(&_program_N)
    // }
    try self.output.appendSlice(self.allocator, "blk: {\n");

    // Emit bytecode as static const array
    try self.output.appendSlice(self.allocator, "    const _bytecode_");
    try emitInt(self, blob_id);
    try self.output.appendSlice(self.allocator, " = [_]u8{ ");

    // Serialize bytecode and emit as byte array
    const serialized = program.serialize(self.allocator) catch {
        try self.output.appendSlice(self.allocator, "// serialization failed\n");
        try self.output.appendSlice(self.allocator, "break :blk try runtime.eval(allocator, \"");
        try escapeZigString(self, source);
        try self.output.appendSlice(self.allocator, "\");\n}");
        return;
    };
    defer self.allocator.free(serialized);

    for (serialized, 0..) |byte, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
        try emitInt(self, byte);
    }
    try self.output.appendSlice(self.allocator, " };\n");

    // Deserialize and execute via VM
    try self.output.appendSlice(self.allocator, "    var _program_");
    try emitInt(self, blob_id);
    try self.output.appendSlice(self.allocator, " = runtime.BytecodeProgram.deserialize(allocator, &_bytecode_");
    try emitInt(self, blob_id);
    try self.output.appendSlice(self.allocator, ") catch unreachable;\n");

    try self.output.appendSlice(self.allocator, "    defer _program_");
    try emitInt(self, blob_id);
    try self.output.appendSlice(self.allocator, ".deinit();\n");

    try self.output.appendSlice(self.allocator, "    var _vm_");
    try emitInt(self, blob_id);
    try self.output.appendSlice(self.allocator, " = runtime.BytecodeVM.init(allocator);\n");

    try self.output.appendSlice(self.allocator, "    defer _vm_");
    try emitInt(self, blob_id);
    try self.output.appendSlice(self.allocator, ".deinit();\n");

    try self.output.appendSlice(self.allocator, "    break :blk try _vm_");
    try emitInt(self, blob_id);
    try self.output.appendSlice(self.allocator, ".execute(&_program_");
    try emitInt(self, blob_id);
    try self.output.appendSlice(self.allocator, ");\n}");
}

/// Helper to emit integer as decimal string
fn emitInt(self: *NativeCodegen, value: anytype) CodegenError!void {
    var buf: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.OutOfMemory;
    try self.output.appendSlice(self.allocator, result);
}

/// Helper to escape a string for Zig string literal
fn escapeZigString(self: *NativeCodegen, source: []const u8) CodegenError!void {
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
