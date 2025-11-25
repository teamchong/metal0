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
        // Check if any tests are not skipped
        var has_runnable_tests = false;
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason == null) {
                has_runnable_tests = true;
                break;
            }
        }

        // Create instance using init() which initializes __dict__
        try self.emitIndent();
        if (has_runnable_tests) {
            try self.output.writer(self.allocator).print("var _test_instance_{s} = {s}.init(allocator);\n", .{ class_info.class_name, class_info.class_name });
        } else {
            // Use _ = to discard value when all tests are skipped
            try self.output.writer(self.allocator).print("_ = {s}.init(allocator);\n", .{class_info.class_name});
        }

        // Run each test method
        for (class_info.test_methods) |method_info| {
            const method_name = method_info.name;

            // Check if test should be skipped
            if (method_info.skip_reason) |reason| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... SKIP: {s}\\n\", .{{}});\n", .{ class_info.class_name, method_name, reason });
                continue; // Don't run setUp, tearDown, or the test
            }

            // Call setUp before each test if it exists
            if (class_info.has_setUp) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_test_instance_{s}.setUp();\n", .{class_info.class_name});
            }

            try self.emitIndent();
            try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... \", .{{}});\n", .{ class_info.class_name, method_name });
            try self.emitIndent();
            try self.output.writer(self.allocator).print("_test_instance_{s}.{s}();\n", .{ class_info.class_name, method_name });
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "std.debug.print(\"ok\\n\", .{});\n");

            // Call tearDown after each test if it exists
            if (class_info.has_tearDown) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_test_instance_{s}.tearDown();\n", .{class_info.class_name});
            }
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

/// Generate code for self.assertGreater(a, b)
pub fn genAssertGreater(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertGreater requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertGreater(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertLess(a, b)
pub fn genAssertLess(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertLess requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertLess(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertGreaterEqual(a, b)
pub fn genAssertGreaterEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertGreaterEqual requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertGreaterEqual(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertLessEqual(a, b)
pub fn genAssertLessEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertLessEqual requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertLessEqual(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertNotEqual(a, b)
pub fn genAssertNotEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertNotEqual requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertNotEqual(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertIs(a, b)
pub fn genAssertIs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertIs requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertIs(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertIsNot(a, b)
pub fn genAssertIsNot(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertIsNot requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertIsNot(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertIsNotNone(x)
pub fn genAssertIsNotNone(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 1) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertIsNotNone requires 1 argument\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertIsNotNone(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertIn(item, container)
pub fn genAssertIn(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertIn requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertIn(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertNotIn(item, container)
pub fn genAssertNotIn(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertNotIn requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertNotIn(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertAlmostEqual(a, b)
pub fn genAssertAlmostEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertAlmostEqual requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertAlmostEqual(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertNotAlmostEqual(a, b)
pub fn genAssertNotAlmostEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertNotAlmostEqual requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertNotAlmostEqual(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertCountEqual(a, b)
pub fn genAssertCountEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertCountEqual requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertCountEqual(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertRegex(text, pattern)
pub fn genAssertRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertRegex requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertRegex(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertNotRegex(text, pattern)
pub fn genAssertNotRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertNotRegex requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertNotRegex(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertRaises(exception_type, callable, *args)
/// Python: self.assertRaises(ValueError, func, arg1, arg2)
/// Zig: runtime.unittest.assertRaises(func, .{arg1, arg2})
pub fn genAssertRaises(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    // assertRaises needs at least exception_type and callable
    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertRaises requires at least 2 arguments: exception_type, callable\")");
        return;
    }

    const parent = @import("expressions.zig");

    // args[0] is exception type (ignored for now - we just check any error)
    // args[1] is the callable
    // args[2..] are arguments to pass to the callable

    try self.output.appendSlice(self.allocator, "runtime.unittest.assertRaises(");
    try parent.genExpr(self, args[1]); // callable
    try self.output.appendSlice(self.allocator, ", .{");

    // Generate tuple of remaining args
    if (args.len > 2) {
        for (args[2..], 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try parent.genExpr(self, arg);
        }
    }

    try self.output.appendSlice(self.allocator, "})");
}
