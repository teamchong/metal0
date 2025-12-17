/// Assert statement code generation
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");

/// Generate assert statement
/// Transforms: assert condition or assert condition, message
/// Into: if (!runtime.toBool(condition)) { runtime.debug_reader.printPythonError(...); std.debug.panic(...); }
pub fn genAssert(self: *NativeCodegen, assert_node: ast.Node.Assert) CodegenError!void {
    // Record line mapping for debug info (maps Python assert line -> Zig line)
    self.recordAssertLineMapping();

    // Check if condition is a simple bool type that doesn't need toBool wrapper
    const cond_type = self.inferExprScoped(assert_node.condition.*) catch .unknown;
    const is_simple_bool = type_traits.isBoolean(cond_type);

    try self.emitIndent();
    if (is_simple_bool) {
        // Direct negation for bool expressions
        try self.emit("if (!(");
        try self.genExpr(assert_node.condition.*);
        try self.emit(")) {\n");
    } else {
        // Use runtime.toBool for proper Python truthiness (lists, strings, etc.)
        try self.emit("if (!runtime.toBool(");
        try self.genExpr(assert_node.condition.*);
        try self.emit(")) {\n");
    }

    self.indent();

    // Print Python-style error traceback before panic
    try self.emitIndent();
    if (assert_node.msg) |msg| {
        // assert x, "message"
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"AssertionError\", ");
        // Generate message expression - if it's a string literal, emit directly
        if (msg.* == .constant and msg.constant.value == .string) {
            try self.emit("\"");
            try self.emit(msg.constant.value.string);
            try self.emit("\"");
        } else {
            // For non-string messages, convert to string representation
            try self.emit("\"assertion failed\"");
        }
        try self.emit(", @src().line);\n");
        try self.emitIndent();
        try self.emit("std.debug.panic(\"AssertionError: {any}\", .{");
        try self.genExpr(msg.*);
        try self.emit("});\n");
    } else {
        // assert x
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"AssertionError\", \"assertion failed\", @src().line);\n");
        try self.emitIndent();
        try self.emit("std.debug.panic(\"AssertionError\", .{});\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}
