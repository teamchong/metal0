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
fn genRaiseMessage(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    if (arg == .constant and arg.constant.value == .string) {
        // String literal - emit with proper escaping
        const raw = arg.constant.value.string;
        try self.emit("\"");
        // Escape inner double quotes and backslashes for Zig string literal
        for (raw) |c| {
            if (c == '"') {
                try self.emit("\\\"");
            } else if (c == '\\') {
                try self.emit("\\\\");
            } else if (c == '\n') {
                try self.emit("\\n");
            } else if (c == '\r') {
                try self.emit("\\r");
            } else if (c == '\t') {
                try self.emit("\\t");
            } else {
                try self.output.writer(self.allocator).writeByte(c);
            }
        }
        try self.emit("\"");
    } else {
        // Expression - convert to string at runtime
        try self.emit("(try runtime.builtins.pyStr(__global_allocator, ");
        try expressions.genExpr(self, arg);
        try self.emit("))");
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
        try self.emitIndent();
        try self.emitFmt("break :__ar_blk_{d} {{}}; // Exception caught by assertRaises\n", .{self.current_assert_raises_block_id});
        self.control_flow_terminated = true;
        return;
    }

    // Inside finally block: break out of the labeled block with the error
    // This allows the exception to be captured and propagated after finally completes
    if (self.inside_finally_block) {
        if (raise_node.exc) |exc| {
            // Extract exception type name from the raise expression
            const exc_name = getExceptionName(exc);
            // Print Python-style error message if we have one
            if (exc.* == .call) {
                const call = exc.call;
                if (call.args.len > 0) {
                    try self.emitIndent();
                    try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"");
                    try self.emit(exc_name);
                    try self.emit("\", ");
                    try genRaiseMessage(self, call.args[0]);
                    try self.emit(", @src().line);\n");
                }
            }
            // Break out of finally block with the error
            try self.emitIndent();
            try self.output.writer(self.allocator).print("break :__finally_blk_{d} error.{s};\n", .{ self.current_finally_id, exc_name });
        } else {
            // Bare raise - re-raise the current exception (use generic error)
            try self.emitIndent();
            try self.output.writer(self.allocator).print("break :__finally_blk_{d} error.Exception;\n", .{self.current_finally_id});
        }
        self.control_flow_terminated = true;
        return;
    }

    // Inside try body with finally block (no handlers): store exception to pending variable
    // This allows finally to run before the exception is propagated
    if (self.inside_try_with_finally) {
        if (raise_node.exc) |exc| {
            // Extract exception type name from the raise expression
            const exc_name = getExceptionName(exc);
            // Print Python-style error message if we have one
            if (exc.* == .call) {
                const call = exc.call;
                if (call.args.len > 0) {
                    try self.emitIndent();
                    try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"");
                    try self.emit(exc_name);
                    try self.emit("\", ");
                    try genRaiseMessage(self, call.args[0]);
                    try self.emit(", @src().line);\n");
                }
            }
            // Store exception to pending variable (finally will propagate it)
            try self.emitIndent();
            try self.output.writer(self.allocator).print("__pending_exception_{d} = error.{s};\n", .{ self.current_try_finally_id, exc_name });
        } else {
            // Bare raise - store generic exception
            try self.emitIndent();
            try self.output.writer(self.allocator).print("__pending_exception_{d} = error.Exception;\n", .{self.current_try_finally_id});
        }
        // Don't set control_flow_terminated - code after raise should still be unreachable
        // but finally block must execute, and the exception will be propagated after finally
        self.control_flow_terminated = true;
        return;
    }

    // Inside defer but not finally block (legacy path) - skip raise
    if (self.inside_defer) {
        try self.emitIndent();
        try self.emit("// raise inside defer - cannot propagate\n");
        return;
    }

    // Nuitka-style finally code duplication: emit all finally blocks BEFORE raise
    // This ensures Python semantics where finally runs before any exit
    if (self.hasActiveFinallyBlocks()) {
        // Execute all active finally blocks (innermost to outermost)
        try self.emitAllFinallyBlocks();
    }

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
                        try self.emitIndent();
                        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"");
                        try self.emit(exc_name);
                        try self.emit("\", ");
                        // Generate the message argument
                        try genRaiseMessage(self, call.args[0]);
                        try self.emit(", @src().line);\n");
                    }
                    // Generate: return error.ValueError
                    try self.emitIndent();
                    try self.emit("return error.");
                    try self.emit(exc_name);
                    try self.emit(";\n");
                    self.control_flow_terminated = true;
                    return;
                }
            }
        }
        // Check if this is just an exception name: raise TypeError
        if (exc.* == .name) {
            const exc_name = exc.name.id;
            if (ExceptionTypes.has(exc_name)) {
                // Print Python-style error without message
                try self.emitIndent();
                try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"");
                try self.emit(exc_name);
                try self.emit("\", \"\", @src().line);\n");
                // Generate: return error.TypeError
                try self.emitIndent();
                try self.emit("return error.");
                try self.emit(exc_name);
                try self.emit(";\n");
                self.control_flow_terminated = true;
                return;
            }
        }
        // Fallback for other raise expressions - use generic error
        try self.emitIndent();
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"Exception\", \"\", @src().line);\n");
        try self.emitIndent();
        try self.emit("return error.Exception;\n");
    } else {
        // bare raise - use generic error
        try self.emitIndent();
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"Exception\", \"\", @src().line);\n");
        try self.emitIndent();
        try self.emit("return error.Exception;\n");
    }
    self.control_flow_terminated = true;
}
