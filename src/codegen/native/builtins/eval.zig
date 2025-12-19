/// eval() and exec() builtins - wire to AST executor or comptime
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const bytecode_compiler = @import("../../bytecode.zig");
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

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
        const source_copy = try self.arena.allocator().dupe(u8, eval_source);
        try self.comptime_evals.put(source_copy, {});
    }

    // Compile source to bytecode at compile time
    const program = bytecode_compiler.compileSource(self.allocator, eval_source) catch |err| {
        // If bytecode compilation fails, fall back to runtime eval
        std.debug.print("comptime eval fallback for '{s}': {}\n", .{ eval_source, err });
        try emitConst(self, "try runtime.eval(__global_allocator, \"");
        try escapeZigString(self, eval_source);
        try emitConst(self, "\")");
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
    const id = self.nextNameId();
    try emitFmtConst(self, "__m{d}_eval: {{\n", .{id});
    try emitConst(self, "    const _bytecode_");
    try emitInt(self, blob_id);
    try emitConst(self, " = [_]u8{ ");

    // Serialize bytecode and emit as byte array
    const serialized = program.serialize(self.allocator) catch {
        try emitConst(self, "// serialization failed\n");
        try emitFmtConst(self, "break :__m{d}_eval try runtime.eval(__global_allocator, \"", .{id});
        try escapeZigString(self, source);
        try emitConst(self, "\");\n}");
        return;
    };
    defer self.allocator.free(serialized);

    for (serialized, 0..) |byte, i| {
        if (i > 0) try emitConst(self, ", ");
        try emitInt(self, byte);
    }
    try emitConst(self, " };\n    var _program_");
    try emitInt(self, blob_id);
    try emitConst(self, " = runtime.BytecodeProgram.deserialize(__global_allocator, &_bytecode_");
    try emitInt(self, blob_id);
    try emitConst(self, ") catch unreachable;\n    defer _program_");
    try emitInt(self, blob_id);
    try emitConst(self, ".deinit();\n    var _vm_");
    try emitInt(self, blob_id);
    try emitConst(self, " = runtime.BytecodeVM.init(__global_allocator);\n    defer _vm_");
    try emitInt(self, blob_id);
    try emitConst(self, ".deinit();\n");
    try emitFmtConst(self, "    break :__m{d}_eval try _vm_", .{id});
    try emitInt(self, blob_id);
    try emitConst(self, ".execute(&_program_");
    try emitInt(self, blob_id);
    try emitConst(self, ");\n}");
}

/// Helper to emit integer as decimal string
fn emitInt(self: *NativeCodegen, value: anytype) CodegenError!void {
    try emitFmtConst(self, "{d}", .{value});
}

/// Helper to escape a string for Zig string literal
fn escapeZigString(self: *NativeCodegen, source: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    for (source) |c| {
        switch (c) {
            '"' => try b.write("\\\""),
            '\\' => try b.write("\\\\"),
            '\n' => try b.write("\\n"),
            '\r' => try b.write("\\r"),
            '\t' => try b.write("\\t"),
            else => try b.body.append(b.allocator, c),
        }
    }
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
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
    try emitConst(self, "try runtime.eval(__global_allocator, ");
    try self.genExpr(args[0]);
    try emitConst(self, ")");
}

/// Generate code for exec(source, [globals, [locals]])
/// Calls runtime.exec() which uses bytecode VM (no return value)
pub fn genExec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        return error.OutOfMemory; // exec() requires at least 1 argument
    }

    // For now, ignore globals and locals arguments (args[1] and args[2])
    // Generate: try runtime.exec(__global_allocator, source_code)
    try emitConst(self, "try runtime.exec(__global_allocator, ");
    try self.genExpr(args[0]);
    try emitConst(self, ")");
}
