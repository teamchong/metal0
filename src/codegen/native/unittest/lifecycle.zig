/// unittest lifecycle code generation (main, finalize, setUp/tearDown)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for unittest.main()
/// Initializes test runner and runs all test methods
pub fn genUnittestMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("{\n");
    self.indent();

    // Initialize test runner
    try self.emitIndent();
    try self.emit("_ = try runtime.unittest.initRunner(allocator);\n");

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
            try self.output.writer(self.allocator).print("var _test_instance_{s} = {s}.init(__global_allocator);\n", .{ class_info.class_name, class_info.class_name });
        } else {
            try self.output.writer(self.allocator).print("_ = {s}.init(__global_allocator);\n", .{class_info.class_name});
        }

        // Call setUpClass BEFORE all test methods (class-level fixture)
        if (class_info.has_setup_class and has_runnable_tests) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("{s}.setUpClass();\n", .{class_info.class_name});
        }

        // Run each test method
        for (class_info.test_methods) |method_info| {
            const method_name = method_info.name;

            // Check if test should be skipped
            if (method_info.skip_reason) |reason| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... SKIP: {s}\\n\", .{{}});\n", .{ class_info.class_name, method_name, reason });
                continue;
            }

            // Call setUp before each test if it exists
            // Use try since setUp may assign to self.attr which uses __dict__.put()
            // Pass allocator since setUp may need it for __dict__ operations
            if (class_info.has_setUp) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("try _test_instance_{s}.setUp(allocator);\n", .{class_info.class_name});
            }

            try self.emitIndent();
            try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... \", .{{}});\n", .{ class_info.class_name, method_name });
            try self.emitIndent();
            // Generate method call with try and allocator if needed
            if (method_info.needs_allocator) {
                try self.output.writer(self.allocator).print("try _test_instance_{s}.{s}(allocator);\n", .{ class_info.class_name, method_name });
            } else {
                try self.output.writer(self.allocator).print("_test_instance_{s}.{s}();\n", .{ class_info.class_name, method_name });
            }
            try self.emitIndent();
            try self.emit("std.debug.print(\"ok\\n\", .{});\n");

            // Call tearDown after each test if it exists
            // Use try since tearDown may assign to self.attr which uses __dict__.put()
            // Pass allocator since tearDown may need it for __dict__ operations
            if (class_info.has_tearDown) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("try _test_instance_{s}.tearDown(allocator);\n", .{class_info.class_name});
            }
        }

        // Call tearDownClass AFTER all test methods (class-level fixture)
        if (class_info.has_teardown_class and has_runnable_tests) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("{s}.tearDownClass();\n", .{class_info.class_name});
        }
    }

    // Print results
    try self.emitIndent();
    try self.emit("runtime.unittest.finalize();\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n"); // unittest.main() handled specially, no semicolon needed
}

/// Generate code for unittest.finalize() - called at end of tests
pub fn genUnittestFinalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.unittest.finalize()");
}
