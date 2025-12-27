/// eval() and exec() builtins - wire to AST executor or comptime
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const bytecode_compiler = @import("../../bytecode.zig");
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

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

    // When inside a defer block, we can't use 'try' - use 'catch unreachable' instead
    const try_expr = if (self.inside_defer) "" else "try ";
    const catch_expr = if (self.inside_defer) " catch unreachable" else "";

    // Compile source to bytecode at compile time (use compileExpr for eval semantics)
    var program = bytecode_compiler.compileExpr(self.allocator, eval_source) catch |err| {
        // If bytecode compilation fails, fall back to runtime eval
        std.debug.print("comptime eval fallback for '{s}': {}\n", .{ eval_source, err });
        try self.emitFmt("runtime.PyValue.from({s}runtime.eval(__global_allocator, \"", .{try_expr});
        try escapeZigString(self, eval_source);
        try self.emitFmt("\"){s})", .{catch_expr});
        return;
    };
    defer program.deinit();

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
    try self.emitFmt("__m{d}_eval: {{\n", .{id});
    try self.emit("    const _bytecode_");
    try emitInt(self, blob_id);
    try self.emit(" = [_]u8{ ");

    // Serialize bytecode and emit as byte array
    const serialized = program.serialize(self.allocator) catch {
        try self.emit("// serialization failed\n");
        try self.emitFmt("break :__m{d}_eval runtime.PyValue.from({s}runtime.eval(__global_allocator, \"", .{ id, try_expr });
        try escapeZigString(self, source);
        try self.emitFmt("\"){s});\n}}", .{catch_expr});
        return;
    };
    defer self.allocator.free(serialized);

    for (serialized, 0..) |byte, i| {
        if (i > 0) try self.emit(", ");
        try emitInt(self, byte);
    }
    try self.emit(" };\n    var _program_");
    try emitInt(self, blob_id);
    try self.emit(" = runtime.BytecodeProgram.deserialize(__global_allocator, &_bytecode_");
    try emitInt(self, blob_id);
    try self.emit(") catch unreachable;\n    defer _program_");
    try emitInt(self, blob_id);
    try self.emit(".deinit();\n    var _vm_");
    try emitInt(self, blob_id);
    try self.emit(" = runtime.BytecodeVM.init(__global_allocator);\n    defer _vm_");
    try emitInt(self, blob_id);
    try self.emit(".deinit();\n");
    try self.emitFmt("    break :__m{d}_eval runtime.PyValue.from({s}_vm_", .{ id, try_expr });
    try emitInt(self, blob_id);
    try self.emit(".execute(&_program_");
    try emitInt(self, blob_id);
    try self.emitFmt("){s});\n}}", .{catch_expr});
}

/// Helper to emit integer as decimal string
fn emitInt(self: *NativeCodegen, value: anytype) CodegenError!void {
    try self.emitFmt("{d}", .{value});
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

/// Generate source string expression for eval/exec
/// Handles BinOp string/bytes concat specially using std.mem.concat
/// Regular strings/expressions use genExpr
fn genEvalSource(codegen: *NativeCodegen, source: ast.Node) CodegenError!void {
    switch (source) {
        .binop => |b| {
            // Check if this is an Add operation (string/bytes concatenation)
            // For eval/exec source args, Add should always be string concat
            if (b.op == .Add) {
                const left = b.left.*;
                const right = b.right.*;

                // Generate: try std.mem.concat(__global_allocator, u8, &.{ left, right })
                try codegen.emit("try std.mem.concat(__global_allocator, u8, &.{ ");
                try genEvalSource(codegen, left);
                try codegen.emit(", ");
                try genEvalSource(codegen, right);
                try codegen.emit(" })");
                return;
            }
            // For non-Add binops, fall through to genExpr
            try codegen.genExpr(source);
        },
        else => {
            // For non-binop expressions, use normal genExpr
            try codegen.genExpr(source);
        },
    }
}

/// Generate code for eval(source, [globals, [locals]])
/// Calls runtime.eval() or runtime.evalWithScope() which uses bytecode VM
/// Returns *runtime.PyObject that can be used with len(), pyObjToInt(), etc.
pub fn genEval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        return error.OutOfMemory; // eval() requires at least 1 argument
    }

    // When inside a defer block, we can't use 'try' - use 'catch unreachable' instead
    const try_expr = if (self.inside_defer) "" else "try ";
    const catch_expr = if (self.inside_defer) " catch unreachable" else "";

    if (args.len >= 2) {
        // eval(source, globals, [locals])
        // Generate: runtime.PyValue.from(try runtime.evalWithScope(...))
        // Wrap result in PyValue since eval returns *PyObject
        try self.emitFmt("runtime.PyValue.from({s}runtime.evalWithScope(__global_allocator, ", .{try_expr});
        try genEvalSource(self, args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]); // globals
        try self.emit(", ");
        if (args.len >= 3) {
            try self.genExpr(args[2]); // locals
        } else {
            try self.emit("null"); // no locals, use globals as locals
        }
        try self.emitFmt("){s})", .{catch_expr});
    } else {
        // eval(source) - no scope args
        // Generate: runtime.PyValue.from(try runtime.eval(...))
        // Wrap result in PyValue since eval returns *PyObject
        try self.emitFmt("runtime.PyValue.from({s}runtime.eval(__global_allocator, ", .{try_expr});
        try genEvalSource(self, args[0]);
        try self.emitFmt("){s})", .{catch_expr});
    }
}

/// Generate code for exec(source, [globals, [locals]])
/// Calls runtime.exec() or runtime.execWithScope() which uses bytecode VM (no return value)
pub fn genExec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        return error.OutOfMemory; // exec() requires at least 1 argument
    }

    if (args.len >= 2) {
        // exec(source, globals, [locals])
        // Generate: try runtime.execWithScope(__global_allocator, source, globals, locals)
        try self.emit("try runtime.execWithScope(__global_allocator, ");
        try genEvalSource(self, args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]); // globals
        try self.emit(", ");
        if (args.len >= 3) {
            try self.genExpr(args[2]); // locals
        } else {
            try self.emit("null"); // no locals, use globals as locals
        }
        try self.emit(")");
    } else {
        // exec(source) - no scope args
        // Generate: try runtime.exec(__global_allocator, source_code)
        try self.emit("try runtime.exec(__global_allocator, ");
        try genEvalSource(self, args[0]);
        try self.emit(")");
    }
}
