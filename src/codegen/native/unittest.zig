/// unittest module code generation
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for unittest.main()
/// Initializes test runner and runs all test methods
pub fn genUnittestMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args; // unused for now

    // Generate code to run all unittest TestCase classes and their test methods
    // This generates inline code that:
    // 1. Initializes the test runner
    // 2. Runs each test method (catching panics as test failures)
    // 3. Prints results

    try self.output.appendSlice(self.allocator, "{\n");
    self.indent();

    // Initialize test runner
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "_ = try runtime.unittest.initRunner(allocator);\n");

    // For each test class, instantiate and run test methods
    for (self.unittest_classes.items) |class_info| {
        // Create instance
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const _test_instance_{s} = {s}{{}};\n", .{ class_info.class_name, class_info.class_name });

        // Run each test method
        for (class_info.test_methods) |method_name| {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... \", .{{}});\n", .{ class_info.class_name, method_name });
            try self.emitIndent();
            try self.output.writer(self.allocator).print("_test_instance_{s}.{s}();\n", .{ class_info.class_name, method_name });
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "std.debug.print(\"ok\\n\", .{});\n");
        }
    }

    // Print results
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "runtime.unittest.finalize();\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for unittest.finalize() - called at end of tests
pub fn genUnittestFinalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.output.appendSlice(self.allocator, "runtime.unittest.finalize()");
}

/// Generate code for self.assertEqual(a, b)
pub fn genAssertEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj; // We ignore `self` - it's just a marker

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertEqual requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertEqual(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertTrue(x)
pub fn genAssertTrue(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 1) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertTrue requires 1 argument\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertTrue(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertFalse(x)
pub fn genAssertFalse(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 1) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertFalse requires 1 argument\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertFalse(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertIsNone(x)
pub fn genAssertIsNone(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 1) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertIsNone requires 1 argument\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertIsNone(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ")");
}
