/// Assert statement code generation
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

/// Generate assert statement
/// Transforms: assert condition or assert condition, message
/// Into: if (!runtime.toBool(condition)) { runtime.debug_reader.printPythonError(...); std.debug.panic(...); }
pub fn genAssert(self: *NativeCodegen, assert_node: ast.Node.Assert) CodegenError!void {
    // Record line mapping for debug info (maps Python assert line -> Zig line)
    self.recordAssertLineMapping();

    // Check if condition is a simple bool type that doesn't need toBool wrapper
    const cond_type = self.inferExprScoped(assert_node.condition.*) catch .unknown;
    const is_simple_bool = type_traits.isBoolean(cond_type);

    const b = try self.getBuilder();

    // Capture the condition expression
    const cond_expr = try self.captureExpr(assert_node.condition.*);

    try b.writeIndent();
    if (is_simple_bool) {
        // Direct negation for bool expressions
        try b.emitRaw("if (!(");
        try b.emitValue(cond_expr, .{});
        try b.emitRaw(")) {\n");
    } else {
        // Use runtime.toBool for proper Python truthiness (lists, strings, etc.)
        try b.emitRaw("if (!runtime.toBool(");
        try b.emitValue(cond_expr, .{});
        try b.emitRaw(")) {\n");
    }

    b.indent();

    // Print Python-style error traceback before panic
    try b.writeIndent();
    if (assert_node.msg) |msg| {
        // assert x, "message"
        // Capture message expression once
        const msg_expr = try self.captureExpr(msg.*);

        try b.emitRaw("runtime.debug_reader.printPythonError(__global_allocator, \"AssertionError\", ");
        // Generate message expression - if it's a string literal, emit directly
        if (msg.* == .constant and msg.constant.value == .string) {
            try b.emitRaw("\"");
            try b.emitRaw(msg.constant.value.string);
            try b.emitRaw("\"");
            try b.emitRaw(", @src().line);\n");
            try b.writeIndent();
            // Set exception info and return error (so it can be caught by try/except)
            try b.emitRaw("runtime.exceptions.setException(\"AssertionError\", \"");
            try b.emitRaw(msg.constant.value.string);
            try b.emitRaw("\");\n");
            try b.writeIndent();
            try b.emitRaw("return error.AssertionError;\n");
        } else {
            // For non-string messages (tuples, etc.), convert to Python repr format at runtime
            try b.emitRaw("(try runtime.builtins.pyRepr(__global_allocator, ");
            try b.emitValue(msg_expr, .{});
            try b.emitRaw(")), @src().line);\n");
            try b.writeIndent();
            // Set exception info with repr message and return error (so it can be caught)
            try b.emitRaw("runtime.exceptions.setException(\"AssertionError\", try runtime.builtins.pyRepr(__global_allocator, ");
            try b.emitValue(msg_expr, .{});
            try b.emitRaw("));\n");
            try b.writeIndent();
            try b.emitRaw("return error.AssertionError;\n");
        }
    } else {
        // assert x
        try b.emitRaw("runtime.debug_reader.printPythonError(__global_allocator, \"AssertionError\", \"assertion failed\", @src().line);\n");
        try b.writeIndent();
        // Set exception info and return error (so it can be caught by try/except)
        try b.emitRaw("runtime.exceptions.setException(\"AssertionError\", \"assertion failed\");\n");
        try b.writeIndent();
        try b.emitRaw("return error.AssertionError;\n");
    }

    b.dedent();
    try b.writeIndent();
    try b.emitRaw("}\n");

    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}
