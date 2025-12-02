/// unittest lifecycle code generation (main, finalize, setUp/tearDown)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for unittest.main()
/// Runs all test methods in parallel using metal0 async (scheduler + GreenThreads)
pub fn genUnittestMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("{\n");
    self.indent();

    // Initialize test runner
    try self.emitIndent();
    try self.emit("_ = try runtime.unittest.initRunner(__global_allocator);\n\n");

    // Count total runnable tests
    var total_tests: usize = 0;
    for (self.unittest_classes.items) |class_info| {
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason == null) {
                total_tests += 1;
            }
        }
    }

    // Generate test result struct for collecting parallel results
    try self.emitIndent();
    try self.emit("// Test result for parallel execution\n");
    try self.emitIndent();
    try self.emit("const TestResult = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8,\n");
    try self.emitIndent();
    try self.emit("passed: bool,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n\n");

    // Create results array and threads list
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var test_results: [{d}]TestResult = undefined;\n", .{total_tests});
    try self.emitIndent();
    try self.emit("var test_threads = std.ArrayList(*runtime.GreenThread){};\n");
    try self.emitIndent();
    try self.emit("defer test_threads.deinit(__global_allocator);\n\n");

    // For each test class, create instances and spawn test threads
    var global_test_idx: usize = 0;
    for (self.unittest_classes.items, 0..) |class_info, class_idx| {
        _ = class_idx;

        // Check if any tests are not skipped
        var has_runnable_tests = false;
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason == null) {
                has_runnable_tests = true;
                break;
            }
        }

        // Create instance
        try self.emitIndent();
        if (has_runnable_tests) {
            try self.output.writer(self.allocator).print("var _test_instance_{s} = {s}.init(__global_allocator);\n", .{ class_info.class_name, class_info.class_name });
        } else {
            try self.output.writer(self.allocator).print("_ = {s}.init(__global_allocator);\n", .{class_info.class_name});
        }

        // Call setUpClass before spawning threads
        if (class_info.has_setup_class and has_runnable_tests) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("{s}.setUpClass();\n", .{class_info.class_name});
        }

        // Spawn threads for each test method
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason) |reason| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... SKIP: {s}\\n\", .{{}});\n", .{ class_info.class_name, method_info.name, reason });
                continue;
            }

            // Generate async test wrapper and spawn
            try self.emitIndent();
            try self.emit("{\n");
            self.indent();

            // Store test name in result
            try self.emitIndent();
            try self.output.writer(self.allocator).print("test_results[{d}].name = \"test_{s}_{s}\";\n", .{ global_test_idx, class_info.class_name, method_info.name });

            // Generate test wrapper struct for closure capture
            try self.emitIndent();
            try self.output.writer(self.allocator).print("const TestWrapper_{d} = struct {{\n", .{global_test_idx});
            self.indent();
            try self.emitIndent();
            try self.emit("result_ptr: *bool,\n");
            try self.emitIndent();
            try self.output.writer(self.allocator).print("instance: *@TypeOf(_test_instance_{s}),\n", .{class_info.class_name});
            try self.emitIndent();
            try self.emit("\n");
            try self.emitIndent();
            try self.emit("pub fn run(ctx: *@This()) void {\n");
            self.indent();

            // Call setUp if exists
            if (class_info.has_setUp) {
                try self.emitIndent();
                try self.emit("ctx.instance.setUp(__global_allocator) catch {\n");
                self.indent();
                try self.emitIndent();
                try self.emit("ctx.result_ptr.* = false;\n");
                try self.emitIndent();
                try self.emit("return;\n");
                self.dedent();
                try self.emitIndent();
                try self.emit("};\n");
            }

            // Call test method
            try self.emitIndent();
            if (method_info.needs_allocator and !method_info.is_skipped) {
                try self.output.writer(self.allocator).print("ctx.instance.{s}(__global_allocator", .{method_info.name});
                for (method_info.default_params) |default_param| {
                    try self.emit(", ");
                    try self.emit(default_param.default_code);
                }
                try self.emit(") catch {\n");
            } else if (method_info.default_params.len > 0) {
                try self.output.writer(self.allocator).print("ctx.instance.{s}(", .{method_info.name});
                for (method_info.default_params, 0..) |default_param, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emit(default_param.default_code);
                }
                try self.emit(") catch {\n");
            } else {
                try self.output.writer(self.allocator).print("ctx.instance.{s}() catch {{\n", .{method_info.name});
            }
            self.indent();
            try self.emitIndent();
            try self.emit("ctx.result_ptr.* = false;\n");

            // Call tearDown even on failure
            if (class_info.has_tearDown) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("ctx.instance.tearDown(__global_allocator) catch {{}};\n", .{});
            }

            try self.emitIndent();
            try self.emit("return;\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("};\n");

            // Success path
            try self.emitIndent();
            try self.emit("ctx.result_ptr.* = true;\n");

            // Call tearDown on success
            if (class_info.has_tearDown) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("ctx.instance.tearDown(__global_allocator) catch {{}};\n", .{});
            }

            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("};\n\n");

            // Spawn using scheduler - pass struct contents directly (scheduler copies to heap)
            try self.emitIndent();
            try self.output.writer(self.allocator).print("const thread_{d} = try runtime.scheduler.spawn(TestWrapper_{d}.run, .{{\n", .{ global_test_idx, global_test_idx });
            self.indent();
            try self.emitIndent();
            try self.output.writer(self.allocator).print(".result_ptr = &test_results[{d}].passed,\n", .{global_test_idx});
            try self.emitIndent();
            try self.output.writer(self.allocator).print(".instance = &_test_instance_{s},\n", .{class_info.class_name});
            self.dedent();
            try self.emitIndent();
            try self.emit("});\n");
            try self.emitIndent();
            try self.output.writer(self.allocator).print("try test_threads.append(__global_allocator, thread_{d});\n", .{global_test_idx});

            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");

            global_test_idx += 1;
        }
    }

    try self.emit("\n");

    // Wait for all tests to complete (gather pattern)
    try self.emitIndent();
    try self.emit("// Wait for all tests to complete\n");
    try self.emitIndent();
    try self.emit("for (test_threads.items) |t| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("runtime.scheduler.wait(t);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n\n");

    // Print results
    try self.emitIndent();
    try self.emit("// Print results\n");
    try self.emitIndent();
    try self.emit("for (&test_results) |*result| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (result.passed) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.debug.print(\"{s} ... ok\\n\", .{result.name});\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.debug.print(\"{s} ... FAIL\\n\", .{result.name});\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n\n");

    // Call tearDownClass for all classes
    for (self.unittest_classes.items) |class_info| {
        var has_runnable_tests = false;
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason == null) {
                has_runnable_tests = true;
                break;
            }
        }
        if (class_info.has_teardown_class and has_runnable_tests) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("{s}.tearDownClass();\n", .{class_info.class_name});
        }
    }

    // Finalize
    try self.emitIndent();
    try self.emit("runtime.unittest.finalize();\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate code for unittest.finalize() - called at end of tests
pub fn genUnittestFinalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.unittest.finalize()");
}

/// Generate code for self.addCleanup(func, *args)
pub fn genAddCleanup(cg: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    if (obj == .name) {
        try cg.emit("_ = ");
        try cg.emit(obj.name.id);
    }
}
