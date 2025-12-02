/// eval() and exec() builtins - wire to AST executor or comptime
const std = @import("std");
const ast = @import("ast");
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
        try self.emit("try runtime.eval(__global_allocator, \"");
        try escapeZigString(self, eval_source);
        try self.emit("\")");
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
    //     var _program_N = runtime.BytecodeProgram.deserialize(__global_allocator, &_bytecode_N) catch unreachable;
    //     defer _program_N.deinit();
    //     var _vm_N = runtime.BytecodeVM.init(__global_allocator);
    //     defer _vm_N.deinit();
    //     _vm_N.execute(&_program_N)
    // }
    try self.emit("blk: {\n");

    // Emit bytecode as static const array
    try self.emit("    const _bytecode_");
    try emitInt(self, blob_id);
    try self.emit(" = [_]u8{ ");

    // Serialize bytecode and emit as byte array
    const serialized = program.serialize(self.allocator) catch {
        try self.emit("// serialization failed\n");
        try self.emit("break :blk try runtime.eval(__global_allocator, \"");
        try escapeZigString(self, source);
        try self.emit("\");\n}");
        return;
    };
    defer self.allocator.free(serialized);

    for (serialized, 0..) |byte, i| {
        if (i > 0) try self.emit(", ");
        try emitInt(self, byte);
    }
    try self.emit(" };\n");

    // Deserialize and execute via VM
    try self.emit("    var _program_");
    try emitInt(self, blob_id);
    try self.emit(" = runtime.BytecodeProgram.deserialize(__global_allocator, &_bytecode_");
    try emitInt(self, blob_id);
    try self.emit(") catch unreachable;\n");

    try self.emit("    defer _program_");
    try emitInt(self, blob_id);
    try self.emit(".deinit();\n");

    try self.emit("    var _vm_");
    try emitInt(self, blob_id);
    try self.emit(" = runtime.BytecodeVM.init(__global_allocator);\n");

    try self.emit("    defer _vm_");
    try emitInt(self, blob_id);
    try self.emit(".deinit();\n");

    try self.emit("    break :blk try _vm_");
    try emitInt(self, blob_id);
    try self.emit(".execute(&_program_");
    try emitInt(self, blob_id);
    try self.emit(");\n}");
}

/// Helper to emit integer as decimal string
fn emitInt(self: *NativeCodegen, value: anytype) CodegenError!void {
    var buf: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.OutOfMemory;
    try self.emit(result);
}

/// Helper to escape a string for Zig string literal
fn escapeZigString(self: *NativeCodegen, source: []const u8) CodegenError!void {
    for (source) |c| {
        switch (c) {
            '"' => try self.emit("\\\""),
            '\\' => try self.emit("\\\\"),
            '\n' => try self.emit("\\n"),
            '\r' => try self.emit("\\r"),
            '\t' => try self.emit("\\t"),
            else => try self.output.append(self.allocator, c),
        }
    }
}

/// Generate code for eval(source, [globals, [locals]])
/// Calls runtime.eval() which uses bytecode VM
/// Returns *runtime.PyObject that can be used with len(), pyObjToInt(), etc.
pub fn genEval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        return error.OutOfMemory; // eval() requires at least 1 argument
    }

    // For now, ignore globals and locals arguments (args[1] and args[2])
    // Generate: try runtime.eval(__global_allocator, source_code)
    // Returns *PyObject which can be a list, int, string, etc.
    try self.emit("try runtime.eval(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for exec(source, [globals, [locals]])
/// Calls runtime.exec() which uses bytecode VM (no return value)
pub fn genExec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        return error.OutOfMemory; // exec() requires at least 1 argument
    }

    // For now, ignore globals and locals arguments (args[1] and args[2])
    // Generate: try runtime.exec(__global_allocator, source_code)
    try self.emit("try runtime.exec(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}
