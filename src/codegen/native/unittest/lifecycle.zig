/// unittest lifecycle code generation (main, finalize, setUp/tearDown)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for unittest.main()
/// Runs all test methods in parallel using async state machine pattern
pub fn genUnittestMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("{\n");
    self.indent();

    // Initialize test runner
    try self.emitIndent();
    try self.emit("_ = try runtime.unittest.initRunner(__global_allocator);\n\n");

    // Count total runnable tests for frame array allocation
    var total_tests: usize = 0;
    for (self.unittest_classes.items) |class_info| {
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason == null) {
                total_tests += 1;
            }
        }
    }

    // Generate test frame struct for parallel execution
    try self.emitIndent();
    try self.emit("// Test frame for parallel execution\n");
    try self.emitIndent();
    try self.emit("const TestFrame = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("state: enum { pending, running, done } = .pending,\n");
    try self.emitIndent();
    try self.emit("class_idx: usize,\n");
    try self.emitIndent();
    try self.emit("method_idx: usize,\n");
    try self.emitIndent();
    try self.emit("name: []const u8,\n");
    try self.emitIndent();
    try self.emit("passed: bool = false,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n\n");

    // Create array of test frames
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var test_frames: [{d}]TestFrame = undefined;\n", .{total_tests});
    try self.emitIndent();
    try self.emit("var frame_idx: usize = 0;\n\n");

    // For each test class, create test instances and populate frames
    for (self.unittest_classes.items, 0..) |class_info, class_idx| {
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

        // Populate test frames for this class
        for (class_info.test_methods, 0..) |method_info, method_idx| {
            // Check if test should be skipped
            if (method_info.skip_reason) |reason| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("std.debug.print(\"test_{s}_{s} ... SKIP: {s}\\n\", .{{}});\n", .{ class_info.class_name, method_info.name, reason });
                continue;
            }

            try self.emitIndent();
            try self.output.writer(self.allocator).print("test_frames[frame_idx] = .{{ .class_idx = {d}, .method_idx = {d}, .name = \"test_{s}_{s}\" }};\n", .{ class_idx, method_idx, class_info.class_name, method_info.name });
            try self.emitIndent();
            try self.emit("frame_idx += 1;\n");
        }
    }

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const num_tests = {d};\n", .{total_tests});

    // Parallel execution loop using poll-based state machine
    try self.emitIndent();
    try self.emit("var completed: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var running: usize = 0;\n");
    try self.emitIndent();
    try self.emit("const max_concurrent: usize = 8; // Run up to 8 tests in parallel\n\n");

    try self.emitIndent();
    try self.emit("// Main poll loop - state machine style\n");
    try self.emitIndent();
    try self.emit("while (completed < num_tests) {\n");
    self.indent();

    // Start new tests up to concurrency limit
    try self.emitIndent();
    try self.emit("// Start pending tests up to concurrency limit\n");
    try self.emitIndent();
    try self.emit("for (&test_frames) |*frame| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (frame.state == .pending and running < max_concurrent) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("frame.state = .running;\n");
    try self.emitIndent();
    try self.emit("running += 1;\n");
    try self.emitIndent();
    try self.emit("std.debug.print(\"{s} ... \", .{frame.name});\n\n");

    // Execute test based on class_idx and method_idx
    try self.emitIndent();
    try self.emit("// Execute test synchronously (tests are fast)\n");
    try self.emitIndent();
    try self.emit("const success = blk: {\n");
    self.indent();

    // Generate switch on class_idx
    try self.emitIndent();
    try self.emit("switch (frame.class_idx) {\n");
    self.indent();

    for (self.unittest_classes.items, 0..) |class_info, class_idx| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("{d} => {{\n", .{class_idx});
        self.indent();

        // Generate switch on method_idx
        try self.emitIndent();
        try self.emit("switch (frame.method_idx) {\n");
        self.indent();

        var method_idx: usize = 0;
        for (class_info.test_methods) |method_info| {
            if (method_info.skip_reason != null) continue;

            try self.emitIndent();
            try self.output.writer(self.allocator).print("{d} => {{\n", .{method_idx});
            self.indent();

            // Call setUp before test if it exists
            if (class_info.has_setUp) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_test_instance_{s}.setUp(__global_allocator) catch break :blk false;\n", .{class_info.class_name});
            }

            // Generate method call
            try self.emitIndent();
            if (method_info.needs_allocator and !method_info.is_skipped) {
                // Create mock variables
                for (0..method_info.mock_patch_count) |i| {
                    try self.output.writer(self.allocator).print("var __mock_{s}_{s}_{d} = runtime.unittest.Mock.init();\n", .{ class_info.class_name, method_info.name, i });
                    try self.emitIndent();
                }
                try self.output.writer(self.allocator).print("_test_instance_{s}.{s}(__global_allocator", .{ class_info.class_name, method_info.name });
                for (0..method_info.mock_patch_count) |i| {
                    try self.output.writer(self.allocator).print(", &__mock_{s}_{s}_{d}", .{ class_info.class_name, method_info.name, i });
                }
                for (method_info.default_params) |default_param| {
                    try self.emit(", ");
                    try self.emit(default_param.default_code);
                }
                try self.emit(") catch break :blk false;\n");
            } else if (method_info.mock_patch_count > 0) {
                for (0..method_info.mock_patch_count) |i| {
                    try self.output.writer(self.allocator).print("var __mock_{s}_{s}_{d} = runtime.unittest.Mock.init();\n", .{ class_info.class_name, method_info.name, i });
                    try self.emitIndent();
                }
                try self.output.writer(self.allocator).print("_test_instance_{s}.{s}(", .{ class_info.class_name, method_info.name });
                for (0..method_info.mock_patch_count) |i| {
                    if (i > 0) try self.emit(", ");
                    try self.output.writer(self.allocator).print("&__mock_{s}_{s}_{d}", .{ class_info.class_name, method_info.name, i });
                }
                for (method_info.default_params) |default_param| {
                    try self.emit(", ");
                    try self.emit(default_param.default_code);
                }
                try self.emit(");\n");
            } else if (method_info.default_params.len > 0) {
                try self.output.writer(self.allocator).print("_test_instance_{s}.{s}(", .{ class_info.class_name, method_info.name });
                for (method_info.default_params, 0..) |default_param, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emit(default_param.default_code);
                }
                try self.emit(");\n");
            } else {
                try self.output.writer(self.allocator).print("_test_instance_{s}.{s}();\n", .{ class_info.class_name, method_info.name });
            }

            // Call tearDown after test if it exists
            if (class_info.has_tearDown) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_test_instance_{s}.tearDown(__global_allocator) catch {{}};\n", .{class_info.class_name});
            }

            try self.emitIndent();
            try self.emit("break :blk true;\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("},\n");
            method_idx += 1;
        }

        try self.emitIndent();
        try self.emit("else => break :blk false,\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("},\n");
    }

    try self.emitIndent();
    try self.emit("else => break :blk false,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n\n");

    // Mark test as complete
    try self.emitIndent();
    try self.emit("frame.passed = success;\n");
    try self.emitIndent();
    try self.emit("frame.state = .done;\n");
    try self.emitIndent();
    try self.emit("running -= 1;\n");
    try self.emitIndent();
    try self.emit("completed += 1;\n");
    try self.emitIndent();
    try self.emit("if (success) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.debug.print(\"ok\\n\", .{});\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.debug.print(\"FAIL\\n\", .{});\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Yield to allow other work (cooperative multitasking)
    try self.emitIndent();
    try self.emit("std.Thread.yield() catch {};\n");
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
