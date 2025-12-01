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
    try self.emit("_ = try runtime.unittest.initRunner(__global_allocator);\n");

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
                try self.output.writer(self.allocator).print("try _test_instance_{s}.setUp(__global_allocator);\n", .{class_info.class_name});
            }

            try self.emitIndent();
            try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... \", .{{}});\n", .{ class_info.class_name, method_name });
            try self.emitIndent();
            // Generate method call with try and allocator if needed
            // Note: Skipped methods don't have allocator param even if original body needed it
            if (method_info.needs_allocator and !method_info.is_skipped) {
                // Create mock variables before the call for @mock.patch.object decorators
                // Use unique names per method to avoid redeclaration errors
                for (0..method_info.mock_patch_count) |i| {
                    try self.output.writer(self.allocator).print("var __mock_{s}_{s}_{d} = runtime.unittest.Mock.init();\n", .{ class_info.class_name, method_name, i });
                    try self.emitIndent();
                }
                try self.output.writer(self.allocator).print("try _test_instance_{s}.{s}(__global_allocator", .{ class_info.class_name, method_name });
                // Pass mock pointers for @mock.patch.object decorators
                for (0..method_info.mock_patch_count) |i| {
                    try self.output.writer(self.allocator).print(", &__mock_{s}_{s}_{d}", .{ class_info.class_name, method_name, i });
                }
                // Pass default parameter values for test method
                for (method_info.default_params) |default_param| {
                    try self.emit(", ");
                    try self.emit(default_param.default_code);
                }
                try self.emit(");\n");
            } else if (method_info.mock_patch_count > 0) {
                // Method has mock params but no allocator
                for (0..method_info.mock_patch_count) |i| {
                    try self.output.writer(self.allocator).print("var __mock_{s}_{s}_{d} = runtime.unittest.Mock.init();\n", .{ class_info.class_name, method_name, i });
                    try self.emitIndent();
                }
                try self.output.writer(self.allocator).print("_test_instance_{s}.{s}(", .{ class_info.class_name, method_name });
                for (0..method_info.mock_patch_count) |i| {
                    if (i > 0) try self.emit(", ");
                    try self.output.writer(self.allocator).print("&__mock_{s}_{s}_{d}", .{ class_info.class_name, method_name, i });
                }
                // Pass default parameter values for test method
                for (method_info.default_params) |default_param| {
                    try self.emit(", ");
                    try self.emit(default_param.default_code);
                }
                try self.emit(");\n");
            } else if (method_info.default_params.len > 0) {
                // Method has default params but no allocator or mocks
                try self.output.writer(self.allocator).print("_test_instance_{s}.{s}(", .{ class_info.class_name, method_name });
                for (method_info.default_params, 0..) |default_param, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emit(default_param.default_code);
                }
                try self.emit(");\n");
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
                try self.output.writer(self.allocator).print("try _test_instance_{s}.tearDown(__global_allocator);\n", .{class_info.class_name});
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

/// Generate code for self.addCleanup(func, *args)
/// For now, this is a no-op - cleanups would need to be stored and called after test
/// TODO: Implement proper cleanup registration and execution
pub fn genAddCleanup(cg: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    // No-op: emit code that suppresses unused variable warnings
    // In proper implementation, we would register cleanup functions to be called after test
    // Reference the self/obj to prevent unused variable errors in caller
    if (obj == .name) {
        try cg.emit("_ = ");
        try cg.emit(obj.name.id);
    }
}
