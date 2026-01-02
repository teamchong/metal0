/// Raise statement code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const shared = @import("../../shared_maps.zig");
const ExceptionTypes = shared.RuntimeExceptions;
const expressions = @import("../../expressions.zig");

/// Extract exception type name from an expression
/// Handles both direct name (ValueError) and call (ValueError("msg"))
fn getExceptionName(exc: *const ast.Node) []const u8 {
    switch (exc.*) {
        .call => |call| {
            if (call.func.* == .name) {
                return call.func.name.id;
            }
            return "Exception";
        },
        .name => |n| return n.id,
        else => return "Exception",
    }
}

/// Generate the error message for a raise statement
/// Handles string literals and expressions
/// Returns a string that can be written to builder
fn genRaiseMessage(self: *NativeCodegen, b: anytype, arg: ast.Node) CodegenError!void {
    if (arg == .constant and arg.constant.value == .string) {
        // String literal - emit with proper escaping
        const raw = arg.constant.value.string;
        try b.emitRaw("\"");
        // Escape inner double quotes and backslashes for Zig string literal
        for (raw) |c| {
            if (c == '"') {
                try b.emitRaw("\\\"");
            } else if (c == '\\') {
                try b.emitRaw("\\\\");
            } else if (c == '\n') {
                try b.emitRaw("\\n");
            } else if (c == '\r') {
                try b.emitRaw("\\r");
            } else if (c == '\t') {
                try b.emitRaw("\\t");
            } else {
                var buf: [1]u8 = .{c};
                try b.emitRaw(&buf);
            }
        }
        try b.emitRaw("\"");
    } else {
        // Expression - convert to string at runtime
        const val = try self.captureExpr(arg);
        try b.emitRaw("(try runtime.builtins.pyStr(__global_allocator, ");
        try b.emitValue(val, .{});
        try b.emitRaw("))");
    }
}

/// Generate raise statement
/// raise ValueError("msg") => return error.ValueError
/// raise => return error.Exception
/// NOTE: We use Zig errors so try/except can catch them.
/// When debug info is available, prints Python-style error message before returning.
pub fn genRaise(self: *NativeCodegen, raise_node: ast.Node.Raise) CodegenError!void {
    // Record line mapping for debug info (maps Python raise line -> Zig line)
    self.recordRaiseLineMapping();

    // Inside assertRaises context: break out of the block (exception was expected)
    if (self.in_assert_raises_context) {
        const b = try self.getBuilder();
        try b.writeIndent();
        try b.writeFmt("break :__ar_blk_{d} {{}}; // Exception caught by assertRaises\n", .{self.current_assert_raises_block_id});
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        self.control_flow_terminated = true;
        return;
    }

    // Inside finally block: break out of the labeled block with the error
    // This allows the exception to be captured and propagated after finally completes
    if (self.inside_finally_block) {
        const b = try self.getBuilder();
        if (raise_node.exc) |exc| {
            // Extract exception type name from the raise expression
            const exc_name = getExceptionName(exc);
            // Print Python-style error message if we have one
            if (exc.* == .call) {
                const call = exc.call;
                if (call.args.len > 0) {
                    try b.writeIndent();
                    try b.emitRaw("runtime.debug_reader.printPythonError(__global_allocator, \"");
                    try b.emitRaw(exc_name);
                    try b.emitRaw("\", ");
                    try genRaiseMessage(self, b, call.args[0]);
                    try b.emitRaw(", @src().line);\n");
                }
            }
            // Break out of finally block with the error
            try b.writeIndent();
            try b.writeFmt("break :__finally_blk_{d} error.{s};\n", .{ self.current_finally_id, exc_name });
        } else {
            // Bare raise - re-raise the current exception from exception stack
            try b.writeIndent();
            try b.emitRaw("{\n");
            try b.writeIndent();
            try b.emitRaw("    const __current_exc = runtime.exceptions.getCurrentException();\n");
            try b.writeIndent();
            try b.emitRaw("    if (__current_exc) |exc| {\n");
            try b.writeIndent();
            try b.emitRaw("        runtime.exceptions.setException(exc.type_name, exc.message);\n");
            try b.writeIndent();
            try b.emitRaw("        runtime.debug_reader.printPythonError(__global_allocator, exc.type_name, exc.message, @src().line);\n");
            try b.writeIndent();
            try b.writeFmt("        break :__finally_blk_{d} error.Exception;\n", .{self.current_finally_id});
            try b.writeIndent();
            try b.emitRaw("    } else {\n");
            try b.writeIndent();
            try b.emitRaw("        runtime.exceptions.setException(\"RuntimeError\", \"No active exception to re-raise\");\n");
            try b.writeIndent();
            try b.emitRaw("        runtime.debug_reader.printPythonError(__global_allocator, \"RuntimeError\", \"No active exception to re-raise\", @src().line);\n");
            try b.writeIndent();
            try b.writeFmt("        break :__finally_blk_{d} error.Exception;\n", .{self.current_finally_id});
            try b.writeIndent();
            try b.emitRaw("    }\n");
            try b.writeIndent();
            try b.emitRaw("}\n");
        }
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        self.control_flow_terminated = true;
        return;
    }

    // Inside try body with finally block (no handlers): store exception to pending variable
    // This allows finally to run before the exception is propagated
    if (self.inside_try_with_finally) {
        const b = try self.getBuilder();
        if (raise_node.exc) |exc| {
            // Extract exception type name from the raise expression
            const exc_name = getExceptionName(exc);
            // Print Python-style error message if we have one
            if (exc.* == .call) {
                const call = exc.call;
                if (call.args.len > 0) {
                    try b.writeIndent();
                    try b.emitRaw("runtime.debug_reader.printPythonError(__global_allocator, \"");
                    try b.emitRaw(exc_name);
                    try b.emitRaw("\", ");
                    try genRaiseMessage(self, b, call.args[0]);
                    try b.emitRaw(", @src().line);\n");
                }
            }
            // Store exception to pending variable (finally will propagate it)
            try b.writeIndent();
            try b.writeFmt("__pending_exception_{d} = error.{s};\n", .{ self.current_try_finally_id, exc_name });
        } else {
            // Bare raise - re-raise the current exception from exception stack
            try b.writeIndent();
            try b.emitRaw("{\n");
            try b.writeIndent();
            try b.emitRaw("    const __current_exc = runtime.exceptions.getCurrentException();\n");
            try b.writeIndent();
            try b.emitRaw("    if (__current_exc) |exc| {\n");
            try b.writeIndent();
            try b.emitRaw("        runtime.exceptions.setException(exc.type_name, exc.message);\n");
            try b.writeIndent();
            try b.emitRaw("        runtime.debug_reader.printPythonError(__global_allocator, exc.type_name, exc.message, @src().line);\n");
            try b.writeIndent();
            try b.writeFmt("        __pending_exception_{d} = error.Exception;\n", .{self.current_try_finally_id});
            try b.writeIndent();
            try b.emitRaw("    } else {\n");
            try b.writeIndent();
            try b.emitRaw("        runtime.exceptions.setException(\"RuntimeError\", \"No active exception to re-raise\");\n");
            try b.writeIndent();
            try b.emitRaw("        runtime.debug_reader.printPythonError(__global_allocator, \"RuntimeError\", \"No active exception to re-raise\", @src().line);\n");
            try b.writeIndent();
            try b.writeFmt("        __pending_exception_{d} = error.Exception;\n", .{self.current_try_finally_id});
            try b.writeIndent();
            try b.emitRaw("    }\n");
            try b.writeIndent();
            try b.emitRaw("}\n");
        }
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        // Don't set control_flow_terminated - code after raise should still be unreachable
        // but finally block must execute, and the exception will be propagated after finally
        self.control_flow_terminated = true;
        return;
    }

    // Inside defer but not finally block (legacy path) - skip raise
    if (self.inside_defer) {
        const b = try self.getBuilder();
        try b.writeIndent();
        try b.emitRaw("// raise inside defer - cannot propagate\n");
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Nuitka-style finally code duplication: emit all finally blocks BEFORE raise
    // This ensures Python semantics where finally runs before any exit
    if (self.hasActiveFinallyBlocks()) {
        // Execute all active finally blocks (innermost to outermost)
        try self.emitAllFinallyBlocks();
    }

    const b = try self.getBuilder();

    if (raise_node.exc) |exc| {
        // Check if this is an exception constructor call: raise ValueError("msg")
        if (exc.* == .call) {
            const call = exc.call;
            if (call.func.* == .name) {
                const exc_name = call.func.name.id;
                // Check if it's a known exception type
                if (ExceptionTypes.has(exc_name)) {
                    // Print Python-style error message if we have a message argument
                    if (call.args.len > 0) {
                        // Store exception info for assertRaises context manager
                        try b.writeIndent();
                        try b.emitRaw("runtime.exceptions.setException(\"");
                        try b.emitRaw(exc_name);
                        try b.emitRaw("\", ");
                        try genRaiseMessage(self, b, call.args[0]);
                        try b.emitRaw(");\n");
                        // Print Python-style error for display
                        try b.writeIndent();
                        try b.emitRaw("runtime.debug_reader.printPythonError(__global_allocator, \"");
                        try b.emitRaw(exc_name);
                        try b.emitRaw("\", ");
                        // Generate the message argument
                        try genRaiseMessage(self, b, call.args[0]);
                        try b.emitRaw(", @src().line);\n");
                    } else {
                        // Store exception info even without message
                        try b.writeIndent();
                        try b.emitRaw("runtime.exceptions.setException(\"");
                        try b.emitRaw(exc_name);
                        try b.emitRaw("\", \"\");\n");
                    }
                    // Generate: return error.ValueError
                    try b.writeIndent();
                    try b.emitRaw("return error.");
                    try b.emitRaw(exc_name);
                    try b.emitRaw(";\n");
                    const output = try b.getBodyDupe();
                    try self.output.appendSlice(self.allocator, output);
                    self.control_flow_terminated = true;
                    return;
                }
            }
        }
        // Check if this is just an exception name: raise TypeError
        if (exc.* == .name) {
            const exc_name = exc.name.id;
            if (ExceptionTypes.has(exc_name)) {
                // Store exception info for assertRaises context manager
                try b.writeIndent();
                try b.emitRaw("runtime.exceptions.setException(\"");
                try b.emitRaw(exc_name);
                try b.emitRaw("\", \"\");\n");
                // Print Python-style error without message
                try b.writeIndent();
                try b.emitRaw("runtime.debug_reader.printPythonError(__global_allocator, \"");
                try b.emitRaw(exc_name);
                try b.emitRaw("\", \"\", @src().line);\n");
                // Generate: return error.TypeError
                try b.writeIndent();
                try b.emitRaw("return error.");
                try b.emitRaw(exc_name);
                try b.emitRaw(";\n");
                const output = try b.getBodyDupe();
                try self.output.appendSlice(self.allocator, output);
                self.control_flow_terminated = true;
                return;
            }
        }
        // Fallback for other raise expressions - use generic error
        try b.writeIndent();
        try b.emitRaw("runtime.exceptions.setException(\"Exception\", \"\");\n");
        try b.writeIndent();
        try b.emitRaw("runtime.debug_reader.printPythonError(__global_allocator, \"Exception\", \"\", @src().line);\n");
        try b.writeIndent();
        try b.emitRaw("return error.Exception;\n");
    } else {
        // bare raise - re-raise the currently active exception from exception stack
        try b.writeIndent();
        try b.emitRaw("{\n");
        try b.writeIndent();
        try b.emitRaw("    const __current_exc = runtime.exceptions.getCurrentException();\n");
        try b.writeIndent();
        try b.emitRaw("    if (__current_exc) |exc| {\n");
        try b.writeIndent();
        try b.emitRaw("        runtime.exceptions.setException(exc.type_name, exc.message);\n");
        try b.writeIndent();
        try b.emitRaw("        runtime.debug_reader.printPythonError(__global_allocator, exc.type_name, exc.message, @src().line);\n");
        try b.writeIndent();
        try b.emitRaw("        return error.Exception;\n");
        try b.writeIndent();
        try b.emitRaw("    } else {\n");
        try b.writeIndent();
        try b.emitRaw("        runtime.exceptions.setException(\"RuntimeError\", \"No active exception to re-raise\");\n");
        try b.writeIndent();
        try b.emitRaw("        runtime.debug_reader.printPythonError(__global_allocator, \"RuntimeError\", \"No active exception to re-raise\", @src().line);\n");
        try b.writeIndent();
        try b.emitRaw("        return error.Exception;\n");
        try b.writeIndent();
        try b.emitRaw("    }\n");
        try b.writeIndent();
        try b.emitRaw("}\n");
    }
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
    self.control_flow_terminated = true;
}
