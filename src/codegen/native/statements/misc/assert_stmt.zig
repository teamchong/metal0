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
        try b.write("if (!(");
        try b.emitValue(cond_expr, .{});
        try b.write(")) {\n");
    } else {
        // Use runtime.toBool for proper Python truthiness (lists, strings, etc.)
        try b.write("if (!runtime.toBool(");
        try b.emitValue(cond_expr, .{});
        try b.write(")) {\n");
    }

    b.indent();

    // Print Python-style error traceback before panic
    try b.writeIndent();
    if (assert_node.msg) |msg| {
        // assert x, "message"
        try b.write("runtime.debug_reader.printPythonError(__global_allocator, \"AssertionError\", ");
        // Generate message expression - if it's a string literal, emit directly
        if (msg.* == .constant and msg.constant.value == .string) {
            try b.write("\"");
            try b.write(msg.constant.value.string);
            try b.write("\"");
        } else {
            // For non-string messages, convert to string representation
            try b.write("\"assertion failed\"");
        }
        try b.write(", @src().line);\n");
        try b.writeIndent();
        try b.write("std.debug.panic(\"AssertionError: {any}\", .{");
        const msg_expr = try self.captureExpr(msg.*);
        try b.emitValue(msg_expr, .{});
        try b.write("});\n");
    } else {
        // assert x
        try b.write("runtime.debug_reader.printPythonError(__global_allocator, \"AssertionError\", \"assertion failed\", @src().line);\n");
        try b.writeIndent();
        try b.write("std.debug.panic(\"AssertionError\", .{});\n");
    }

    b.dedent();
    try b.writeIndent();
    try b.write("}\n");

    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}
