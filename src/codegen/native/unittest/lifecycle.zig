/// unittest lifecycle code generation (main, finalize, setUp/tearDown)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const zig_keywords = @import("zig_keywords");

/// Generate code for unittest.main()
/// Runs all test methods in parallel using metal0 scheduler (thread pool)
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

    // Print skipped tests first
    for (self.unittest_classes.items) |class_info| {
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason) |reason| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... SKIP: {s}\\\\n\", .{{}});\n", .{ class_info.class_name, method_info.name, reason });
            }
        }
    }

    // Create test class instances
    for (self.unittest_classes.items) |class_info| {
        var has_runnable_tests = false;
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason == null) {
                has_runnable_tests = true;
                break;
            }
        }

        try self.emitIndent();
        if (has_runnable_tests) {
            try self.output.writer(self.allocator).print("var _test_instance_{s} = {s}.init(__global_allocator);\n", .{ class_info.class_name, class_info.class_name });
        } else {
            try self.output.writer(self.allocator).print("_ = {s}.init(__global_allocator);\n", .{class_info.class_name});
        }

        // Call setUpClass if exists
        if (class_info.has_setup_class and has_runnable_tests) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("{s}.setUpClass();\n", .{class_info.class_name});
        }
    }
    try self.emit("\n");

    // metal0 parallel test execution (auto I/O-CPU switch)
    try self.emitIndent();
    try self.emit("// metal0 async - auto switches between thread pool (CPU) and netpoller (I/O)\n");
    try self.emitIndent();
    try self.emit("if (!runtime.scheduler_initialized) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("runtime.scheduler = try runtime.Scheduler.init(__global_allocator, 0);\n");
    try self.emitIndent();
    try self.emit("try runtime.scheduler.start();\n");
    try self.emitIndent();
    try self.emit("runtime.scheduler_initialized = true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n\n");

    // Test result tracking
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var test_results: [{d}]std.atomic.Value(u8) = undefined;\n", .{total_tests});
    try self.emitIndent();
    try self.emit("for (&test_results) |*r| r.* = std.atomic.Value(u8).init(0);\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const test_names: [{d}][]const u8 = .{{\n", .{total_tests});
    self.indent();

    // Initialize test names array
    for (self.unittest_classes.items) |class_info| {
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason != null) continue;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("\"test_{s}_{s}\",\n", .{ class_info.class_name, method_info.name });
        }
    }
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n\n");

    // Spawn test threads
    var global_test_idx: usize = 0;
    for (self.unittest_classes.items) |class_info| {
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason != null) continue;

            // Create context struct for this test
            try self.emitIndent();
            try self.output.writer(self.allocator).print("const TestCtx{d} = struct {{\n", .{global_test_idx});
            self.indent();
            try self.emitIndent();
            try self.emit("result: *std.atomic.Value(u8),\n");
            try self.emitIndent();
            try self.output.writer(self.allocator).print("instance: *@TypeOf(_test_instance_{s}),\n", .{class_info.class_name});
            try self.emitIndent();
            try self.emit("allocator: std.mem.Allocator,\n");
            try self.emitIndent();
            try self.emit("pub fn run(ctx: *@This()) void {\n");
            self.indent();

            // setUp
            if (class_info.has_setUp) {
                try self.emitIndent();
                try self.emit("ctx.instance.setUp(ctx.allocator) catch {};\n");
            }

            // Run test - check if method returns error union
            try self.emitIndent();
            if (method_info.returns_error) {
                // Method returns error union - use catch block
                if (method_info.needs_allocator and !method_info.is_skipped) {
                    try self.emit("ctx.instance.");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_info.name);
                    try self.emit("(ctx.allocator");
                    for (method_info.default_params) |default_param| {
                        try self.emit(", ");
                        try self.emit(default_param.default_code);
                    }
                    try self.emit(") catch {\n");
                } else if (method_info.default_params.len > 0) {
                    try self.emit("ctx.instance.");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_info.name);
                    try self.emit("(");
                    for (method_info.default_params, 0..) |default_param, i| {
                        if (i > 0) try self.emit(", ");
                        try self.emit(default_param.default_code);
                    }
                    try self.emit(") catch {\n");
                } else {
                    try self.emit("ctx.instance.");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_info.name);
                    try self.emit("() catch {\n");
                }
                self.indent();
                // tearDown on failure
                if (class_info.has_tearDown) {
                    try self.emitIndent();
                    try self.emit("ctx.instance.tearDown(ctx.allocator) catch {};\n");
                }
                try self.emitIndent();
                try self.emit("ctx.result.store(2, .release);\n"); // 2 = failed
                try self.emitIndent();
                try self.emit("return;\n");
                self.dedent();
                try self.emitIndent();
                try self.emit("};\n");
            } else {
                // Method returns void - no catch needed
                try self.emit("ctx.instance.");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_info.name);
                try self.emit("();\n");
            }

            // tearDown on success
            if (class_info.has_tearDown) {
                try self.emitIndent();
                try self.emit("ctx.instance.tearDown(ctx.allocator) catch {};\n");
            }
            try self.emitIndent();
            try self.emit("ctx.result.store(1, .release);\n"); // 1 = passed

            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("};\n");

            // Run the test sequentially to avoid green-thread TLS race conditions with exception messages
            // (Exception messages are stored in OS-thread-local storage, but green threads share the same OS thread)
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __test_ctx_{d} = TestCtx{d}{{ .result = &test_results[{d}], .instance = &_test_instance_{s}, .allocator = __global_allocator }};\n", .{ global_test_idx, global_test_idx, global_test_idx, class_info.class_name });
            try self.emitIndent();
            try self.output.writer(self.allocator).print("TestCtx{d}.run(&__test_ctx_{d});\n", .{ global_test_idx, global_test_idx });

            global_test_idx += 1;
        }
    }
    try self.emit("\n");

    // Print results (tests already ran sequentially above)
    try self.emitIndent();
    try self.emit("// Print results\n");
    try self.emitIndent();
    try self.emit("for (test_names, 0..) |name, i| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const result = test_results[i].load(.acquire);\n");
    try self.emitIndent();
    try self.emit("if (result == 1) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.debug.print(\"{s} ... ok\\n\", .{name});\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.debug.print(\"{s} ... FAIL\\n\", .{name});\n");
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
pub fn genAddCleanup(_: *NativeCodegen, _: ast.Node, _: []ast.Node) CodegenError!void {
    // addCleanup is a no-op in AOT compilation - cleanup happens automatically via defer/RAII
    // Don't emit anything - the unused self parameter is already suppressed by the method signature
}
