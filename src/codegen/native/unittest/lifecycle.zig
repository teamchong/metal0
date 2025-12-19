/// unittest lifecycle code generation (main, finalize, setUp/tearDown)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const zig_keywords = @import("utils.zig_keywords");

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// Generate code for unittest.main()
/// Runs all test methods in parallel using metal0 scheduler (thread pool)
pub fn genUnittestMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;

    try emitConst(self,"{\n");
    self.indent();

    // Initialize test runner
    try self.emitIndent();
    try emitConst(self,"_ = try unittest.initRunner(__global_allocator);\n\n");

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
                try self.output.writer(self.allocator).print("runtime.print(\"test_{s}_{s} ... SKIP: {s}\\\\n\", .{{}});\n", .{ class_info.class_name, method_info.name, reason });
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
            // init() returns error union - use try to handle error
            try self.output.writer(self.allocator).print("var _test_instance_{s} = try {s}.init(__global_allocator);\n", .{ class_info.class_name, class_info.class_name });
        } else {
            // No runnable tests, but still need to instantiate for side effects
            // Use catch to discard error and value
            try self.output.writer(self.allocator).print("_ = {s}.init(__global_allocator) catch undefined;\n", .{class_info.class_name});
        }

        // Call setUpClass if exists
        if (class_info.has_setup_class and has_runnable_tests) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("{s}.setUpClass();\n", .{class_info.class_name});
        }
    }
    try emitConst(self,"\n");

    // metal0 parallel test execution (auto I/O-CPU switch)
    try self.emitIndent();
    try emitConst(self,"// metal0 async - auto switches between thread pool (CPU) and netpoller (I/O)\n");
    try self.emitIndent();
    try emitConst(self,"if (!runtime.scheduler_initialized) {\n");
    self.indent();
    try self.emitIndent();
    try emitConst(self,"runtime.scheduler = try runtime.Scheduler.init(__global_allocator, 0);\n");
    try self.emitIndent();
    try emitConst(self,"try runtime.scheduler.?.start();\n");
    try self.emitIndent();
    try emitConst(self,"runtime.scheduler_initialized = true;\n");
    self.dedent();
    try self.emitIndent();
    try emitConst(self,"}\n\n");

    // Test result tracking
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var test_results: [{d}]std.atomic.Value(u8) = undefined;\n", .{total_tests});
    try self.emitIndent();
    try emitConst(self,"for (&test_results) |*r| r.* = std.atomic.Value(u8).init(0);\n");
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
    try emitConst(self,"};\n\n");

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
            try emitConst(self,"result: *std.atomic.Value(u8),\n");
            try self.emitIndent();
            try self.output.writer(self.allocator).print("instance: *@TypeOf(_test_instance_{s}),\n", .{class_info.class_name});
            try self.emitIndent();
            try emitConst(self,"allocator: std.mem.Allocator,\n");
            try self.emitIndent();
            try emitConst(self,"pub fn run(ctx: *@This()) void {\n");
            self.indent();

            // setUp
            if (class_info.has_setUp) {
                try self.emitIndent();
                try emitConst(self,"ctx.instance.setUp(ctx.allocator) catch |err| {\n");
                self.indent();
                try self.emitIndent();
                try emitConst(self,"_ = err; ctx.result.store(2, .release); return;\n"); // Fail test on setUp error
                self.dedent();
                try self.emitIndent();
                try emitConst(self,"};\n");
            }

            // Run test - check if method returns error union
            try self.emitIndent();
            if (method_info.returns_error) {
                // Method returns error union - use catch block
                if (method_info.needs_allocator and !method_info.is_skipped) {
                    try emitConst(self,"ctx.instance.");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_info.name);
                    try emitConst(self,"(ctx.allocator");
                    for (method_info.default_params) |default_param| {
                        try emitConst(self,", ");
                        try emitConst(self,default_param.default_code);
                    }
                    try emitConst(self,") catch {\n");
                } else if (method_info.default_params.len > 0) {
                    try emitConst(self,"ctx.instance.");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_info.name);
                    try emitConst(self,"(");
                    for (method_info.default_params, 0..) |default_param, i| {
                        if (i > 0) try emitConst(self,", ");
                        try emitConst(self,default_param.default_code);
                    }
                    try emitConst(self,") catch {\n");
                } else {
                    try emitConst(self,"ctx.instance.");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_info.name);
                    try emitConst(self,"() catch {\n");
                }
                self.indent();
                // tearDown on failure
                if (class_info.has_tearDown) {
                    try self.emitIndent();
                    try emitConst(self,"ctx.instance.tearDown(ctx.allocator) catch |err| { _ = err; };\n");
                }
                try self.emitIndent();
                try emitConst(self,"ctx.result.store(2, .release);\n"); // 2 = failed
                try self.emitIndent();
                try emitConst(self,"return;\n");
                self.dedent();
                try self.emitIndent();
                try emitConst(self,"};\n");
            } else {
                // Method returns void - no catch needed
                try emitConst(self,"ctx.instance.");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method_info.name);
                try emitConst(self,"();\n");
            }

            // tearDown on success
            if (class_info.has_tearDown) {
                try self.emitIndent();
                try emitConst(self,"ctx.instance.tearDown(ctx.allocator) catch |err| {\n");
                self.indent();
                try self.emitIndent();
                try emitConst(self,"_ = err; ctx.result.store(2, .release); return;\n"); // Fail test on tearDown error
                self.dedent();
                try self.emitIndent();
                try emitConst(self,"};\n");
            }
            try self.emitIndent();
            try emitConst(self,"ctx.result.store(1, .release);\n"); // 1 = passed

            self.dedent();
            try self.emitIndent();
            try emitConst(self,"}\n");
            self.dedent();
            try self.emitIndent();
            try emitConst(self,"};\n");

            // Run the test sequentially to avoid green-thread TLS race conditions with exception messages
            // (Exception messages are stored in OS-thread-local storage, but green threads share the same OS thread)
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __test_ctx_{d} = TestCtx{d}{{ .result = &test_results[{d}], .instance = &_test_instance_{s}, .allocator = __global_allocator }};\n", .{ global_test_idx, global_test_idx, global_test_idx, class_info.class_name });
            try self.emitIndent();
            try self.output.writer(self.allocator).print("TestCtx{d}.run(&__test_ctx_{d});\n", .{ global_test_idx, global_test_idx });

            global_test_idx += 1;
        }
    }
    try emitConst(self,"\n");

    // Print results and record in unittest.global_result (tests already ran sequentially above)
    try self.emitIndent();
    try emitConst(self,"// Print results and record pass/fail counts\n");
    try self.emitIndent();
    try emitConst(self,"for (test_names, 0..) |name, i| {\n");
    self.indent();
    try self.emitIndent();
    try emitConst(self,"const result = test_results[i].load(.acquire);\n");
    try self.emitIndent();
    try emitConst(self,"if (result == 1) {\n");
    self.indent();
    try self.emitIndent();
    try emitConst(self,"runtime.print(\"{s} ... ok\\n\", .{name});\n");
    try self.emitIndent();
    try emitConst(self,"if (unittest.global_result.*) |r| r.addPass();\n");
    self.dedent();
    try self.emitIndent();
    try emitConst(self,"} else {\n");
    self.indent();
    try self.emitIndent();
    try emitConst(self,"runtime.print(\"{s} ... FAIL\\n\", .{name});\n");
    try self.emitIndent();
    try emitConst(self,"if (unittest.global_result.*) |r| r.addFail(name) catch unreachable;\n");
    self.dedent();
    try self.emitIndent();
    try emitConst(self,"}\n");
    self.dedent();
    try self.emitIndent();
    try emitConst(self,"}\n\n");

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
    try emitConst(self,"unittest.finalize();\n");

    self.dedent();
    try self.emitIndent();
    try emitConst(self,"}\n");
}

/// Generate code for unittest.finalize() - called at end of tests
pub fn genUnittestFinalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitConst(self,"unittest.finalize()");
}

/// Generate code for self.addCleanup(func, *args)
pub fn genAddCleanup(_: *NativeCodegen, _: ast.Node, _: []ast.Node) CodegenError!void {
    // addCleanup is a no-op in AOT compilation - cleanup happens automatically via defer/RAII
    // Don't emit anything - the unused self parameter is already suppressed by the method signature
}
