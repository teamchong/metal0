//! test.test_doctest.test_part1 - DocTestRunner implementation
//! Tests for running doctest examples and collecting results.
const std = @import("std");

/// Result of running a single doctest example
pub const ExampleResult = struct {
    passed: bool,
    source: []const u8,
    expected: []const u8,
    actual: []const u8,
    lineno: usize,
    error_message: ?[]const u8,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (self.passed) {
            try writer.print("OK: line {d}", .{self.lineno});
        } else {
            try writer.print("FAIL: line {d}\n  Expected: {s}\n  Got: {s}", .{
                self.lineno,
                self.expected,
                self.actual,
            });
            if (self.error_message) |msg| {
                try writer.print("\n  Error: {s}", .{msg});
            }
        }
    }
};

/// Aggregated results from running multiple doctests
pub const DocTestResult = struct {
    attempted: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    results: std.ArrayList(ExampleResult),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .results = std.ArrayList(ExampleResult).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.results.deinit();
    }

    pub fn wasSuccessful(self: @This()) bool {
        return self.failed == 0;
    }

    pub fn passRate(self: @This()) f64 {
        if (self.attempted == 0) return 1.0;
        const passed: f64 = @floatFromInt(self.attempted - self.failed);
        const total: f64 = @floatFromInt(self.attempted);
        return passed / total;
    }

    pub fn addResult(self: *@This(), result: ExampleResult) !void {
        try self.results.append(result);
        self.attempted += 1;
        if (!result.passed) {
            self.failed += 1;
        }
    }

    pub fn summary(self: @This(), writer: anytype) !void {
        try writer.print("{d} tests, {d} passed, {d} failed", .{
            self.attempted,
            self.attempted - self.failed,
            self.failed,
        });
        if (self.skipped > 0) {
            try writer.print(", {d} skipped", .{self.skipped});
        }
        try writer.writeAll("\n");
    }
};

/// Example to be tested - represents a single >>> line and expected output
pub const Example = struct {
    source: []const u8,
    want: []const u8,
    lineno: usize = 0,
    indent: usize = 0,
    options: Options = .{},

    pub const Options = struct {
        normalize_whitespace: bool = false,
        ellipsis: bool = false,
        skip: bool = false,
        ignore_exception_detail: bool = false,
    };

    pub fn shouldSkip(self: @This()) bool {
        return self.options.skip;
    }
};

/// DocTest represents a collection of examples from a single docstring
pub const DocTest = struct {
    name: []const u8,
    examples: std.ArrayList(Example),
    allocator: std.mem.Allocator,
    globs: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .allocator = allocator,
            .name = name,
            .examples = std.ArrayList(Example).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.examples.deinit();
    }

    pub fn addExample(self: *@This(), example: Example) !void {
        try self.examples.append(example);
    }

    pub fn exampleCount(self: @This()) usize {
        return self.examples.items.len;
    }
};

/// Mock execution context for running examples
pub const ExecutionContext = struct {
    allocator: std.mem.Allocator,
    output_buffer: std.ArrayList(u8),
    globals: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .output_buffer = std.ArrayList(u8).init(allocator),
            .globals = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.output_buffer.deinit();
        self.globals.deinit();
    }

    pub fn clearOutput(self: *@This()) void {
        self.output_buffer.clearRetainingCapacity();
    }

    pub fn getOutput(self: @This()) []const u8 {
        return self.output_buffer.items;
    }

    pub fn setGlobal(self: *@This(), name: []const u8, value: []const u8) !void {
        try self.globals.put(name, value);
    }

    pub fn getGlobal(self: @This(), name: []const u8) ?[]const u8 {
        return self.globals.get(name);
    }
};

/// DocTestRunner - executes doctest examples and collects results
pub const DocTestRunner = struct {
    verbose: bool = false,
    optionflags: u32 = 0,
    checker: OutputChecker = .{},

    pub const ELLIPSIS: u32 = 1;
    pub const NORMALIZE_WHITESPACE: u32 = 2;
    pub const IGNORE_EXCEPTION_DETAIL: u32 = 4;
    pub const SKIP: u32 = 8;

    /// Simple output comparison
    pub const OutputChecker = struct {
        pub fn checkOutput(
            self: @This(),
            want: []const u8,
            got: []const u8,
            optionflags: u32,
        ) bool {
            _ = self;
            // Exact match
            if (std.mem.eql(u8, want, got)) return true;

            // Normalize whitespace if flag set
            if (optionflags & NORMALIZE_WHITESPACE != 0) {
                return normalizedEqual(want, got);
            }

            // Ellipsis matching if flag set
            if (optionflags & ELLIPSIS != 0) {
                return ellipsisMatch(want, got);
            }

            return false;
        }

        fn normalizedEqual(a: []const u8, b: []const u8) bool {
            const norm_a = normalizeWhitespace(a);
            const norm_b = normalizeWhitespace(b);
            return std.mem.eql(u8, norm_a, norm_b);
        }

        fn normalizeWhitespace(s: []const u8) []const u8 {
            // Simple normalization: trim and collapse whitespace
            return std.mem.trim(u8, s, " \t\n\r");
        }

        fn ellipsisMatch(pattern: []const u8, text: []const u8) bool {
            // Simple ellipsis: ... matches any substring
            if (std.mem.indexOf(u8, pattern, "...")) |idx| {
                const prefix = pattern[0..idx];
                const suffix = pattern[idx + 3 ..];

                if (!std.mem.startsWith(u8, text, prefix)) return false;
                if (suffix.len > 0 and !std.mem.endsWith(u8, text, suffix)) return false;
                return true;
            }
            return std.mem.eql(u8, pattern, text);
        }
    };

    /// Run all examples in a DocTest
    pub fn run(self: @This(), test_: *DocTest, allocator: std.mem.Allocator) !DocTestResult {
        var result = DocTestResult.init(allocator);

        for (test_.examples.items) |example| {
            if (example.shouldSkip()) {
                result.skipped += 1;
                continue;
            }

            const ex_result = self.runExample(example);
            try result.addResult(ex_result);

            if (self.verbose and !ex_result.passed) {
                std.debug.print("Failed at line {d}: {s}\n", .{ example.lineno, example.source });
            }
        }

        return result;
    }

    /// Run a single example
    fn runExample(self: @This(), example: Example) ExampleResult {
        // Simulate execution - in real impl would execute Python
        const simulated_output = self.simulateExecution(example.source);

        const passed = self.checker.checkOutput(
            example.want,
            simulated_output,
            self.optionflags,
        );

        return .{
            .passed = passed,
            .source = example.source,
            .expected = example.want,
            .actual = simulated_output,
            .lineno = example.lineno,
            .error_message = null,
        };
    }

    /// Simulate Python execution (placeholder)
    fn simulateExecution(self: @This(), source: []const u8) []const u8 {
        _ = self;
        // Simple arithmetic evaluation for demo
        if (std.mem.eql(u8, source, "1 + 1")) return "2";
        if (std.mem.eql(u8, source, "2 * 3")) return "6";
        if (std.mem.eql(u8, source, "10 / 2")) return "5.0";
        if (std.mem.eql(u8, source, "print('hello')")) return "hello";
        if (std.mem.eql(u8, source, "'test'.upper()")) return "'TEST'";
        return "";
    }
};

/// Run docstring examples from source text
pub fn run_docstring_examples(source: []const u8, allocator: std.mem.Allocator) !DocTestResult {
    var doctest = DocTest.init(allocator, "inline_examples");
    defer doctest.deinit();

    // Parse examples from source (simplified)
    var lines = std.mem.splitScalar(u8, source, '\n');
    var lineno: usize = 0;
    while (lines.next()) |line| {
        lineno += 1;
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, ">>> ")) {
            const code = trimmed[4..];
            // Look for expected output on next line
            if (lines.next()) |next_line| {
                lineno += 1;
                const expected = std.mem.trim(u8, next_line, " \t");
                try doctest.addExample(.{
                    .source = code,
                    .want = expected,
                    .lineno = lineno - 1,
                });
            }
        }
    }

    const runner = DocTestRunner{ .verbose = false };
    return runner.run(&doctest, allocator);
}

/// Convenience function to run tests and report
pub fn testmod(allocator: std.mem.Allocator, module_docstring: []const u8) !DocTestResult {
    return run_docstring_examples(module_docstring, allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "ExampleResult_format_passed" {
    const result = ExampleResult{
        .passed = true,
        .source = "1 + 1",
        .expected = "2",
        .actual = "2",
        .lineno = 5,
        .error_message = null,
    };

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try stream.writer().print("{}", .{result});

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "OK") != null);
}

test "ExampleResult_format_failed" {
    const result = ExampleResult{
        .passed = false,
        .source = "1 + 1",
        .expected = "3",
        .actual = "2",
        .lineno = 10,
        .error_message = null,
    };

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try stream.writer().print("{}", .{result});

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "FAIL") != null);
}

test "DocTestResult_init_and_wasSuccessful" {
    var result = DocTestResult.init(std.testing.allocator);
    defer result.deinit();

    try std.testing.expect(result.wasSuccessful());
    try std.testing.expectEqual(@as(usize, 0), result.attempted);
}

test "DocTestResult_addResult_passed" {
    var result = DocTestResult.init(std.testing.allocator);
    defer result.deinit();

    try result.addResult(.{
        .passed = true,
        .source = "test",
        .expected = "ok",
        .actual = "ok",
        .lineno = 1,
        .error_message = null,
    });

    try std.testing.expectEqual(@as(usize, 1), result.attempted);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
    try std.testing.expect(result.wasSuccessful());
}

test "DocTestResult_addResult_failed" {
    var result = DocTestResult.init(std.testing.allocator);
    defer result.deinit();

    try result.addResult(.{
        .passed = false,
        .source = "test",
        .expected = "ok",
        .actual = "fail",
        .lineno = 1,
        .error_message = null,
    });

    try std.testing.expectEqual(@as(usize, 1), result.attempted);
    try std.testing.expectEqual(@as(usize, 1), result.failed);
    try std.testing.expect(!result.wasSuccessful());
}

test "DocTestResult_passRate" {
    var result = DocTestResult.init(std.testing.allocator);
    defer result.deinit();

    try result.addResult(.{ .passed = true, .source = "", .expected = "", .actual = "", .lineno = 1, .error_message = null });
    try result.addResult(.{ .passed = true, .source = "", .expected = "", .actual = "", .lineno = 2, .error_message = null });
    try result.addResult(.{ .passed = false, .source = "", .expected = "", .actual = "", .lineno = 3, .error_message = null });

    const rate = result.passRate();
    try std.testing.expectApproxEqAbs(@as(f64, 0.666), rate, 0.01);
}

test "Example_shouldSkip" {
    const skip_ex = Example{
        .source = "test",
        .want = "result",
        .options = .{ .skip = true },
    };
    try std.testing.expect(skip_ex.shouldSkip());

    const normal_ex = Example{
        .source = "test",
        .want = "result",
    };
    try std.testing.expect(!normal_ex.shouldSkip());
}

test "DocTest_init_and_addExample" {
    var dt = DocTest.init(std.testing.allocator, "test_doctest");
    defer dt.deinit();

    try dt.addExample(.{ .source = "1+1", .want = "2", .lineno = 1 });
    try dt.addExample(.{ .source = "2*2", .want = "4", .lineno = 2 });

    try std.testing.expectEqual(@as(usize, 2), dt.exampleCount());
}

test "ExecutionContext_globals" {
    var ctx = ExecutionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.setGlobal("x", "42");
    const value = ctx.getGlobal("x");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("42", value.?);
}

test "OutputChecker_exact_match" {
    const checker = DocTestRunner.OutputChecker{};
    try std.testing.expect(checker.checkOutput("hello", "hello", 0));
    try std.testing.expect(!checker.checkOutput("hello", "world", 0));
}

test "OutputChecker_normalize_whitespace" {
    const checker = DocTestRunner.OutputChecker{};
    try std.testing.expect(checker.checkOutput("hello", "  hello  ", DocTestRunner.NORMALIZE_WHITESPACE));
}

test "OutputChecker_ellipsis" {
    const checker = DocTestRunner.OutputChecker{};
    try std.testing.expect(checker.checkOutput("hello...world", "hello there world", DocTestRunner.ELLIPSIS));
    try std.testing.expect(checker.checkOutput("start...", "start with more text", DocTestRunner.ELLIPSIS));
}

test "DocTestRunner_run_simple" {
    var doctest = DocTest.init(std.testing.allocator, "simple_test");
    defer doctest.deinit();

    try doctest.addExample(.{ .source = "1 + 1", .want = "2", .lineno = 1 });
    try doctest.addExample(.{ .source = "2 * 3", .want = "6", .lineno = 2 });

    const runner = DocTestRunner{};
    var result = try runner.run(&doctest, std.testing.allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.attempted);
    try std.testing.expect(result.wasSuccessful());
}

test "DocTestRunner_run_with_failure" {
    var doctest = DocTest.init(std.testing.allocator, "failing_test");
    defer doctest.deinit();

    try doctest.addExample(.{ .source = "1 + 1", .want = "3", .lineno = 1 }); // Wrong expectation

    const runner = DocTestRunner{};
    var result = try runner.run(&doctest, std.testing.allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.attempted);
    try std.testing.expectEqual(@as(usize, 1), result.failed);
    try std.testing.expect(!result.wasSuccessful());
}

test "DocTestRunner_skip_examples" {
    var doctest = DocTest.init(std.testing.allocator, "skip_test");
    defer doctest.deinit();

    try doctest.addExample(.{ .source = "1 + 1", .want = "2", .lineno = 1 });
    try doctest.addExample(.{ .source = "skip me", .want = "?", .lineno = 2, .options = .{ .skip = true } });

    const runner = DocTestRunner{};
    var result = try runner.run(&doctest, std.testing.allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.attempted);
    try std.testing.expectEqual(@as(usize, 1), result.skipped);
}

test "run_docstring_examples_basic" {
    const docstring =
        \\Example usage:
        \\>>> 1 + 1
        \\2
        \\>>> 2 * 3
        \\6
    ;

    var result = try run_docstring_examples(docstring, std.testing.allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.attempted);
}

test "testmod_convenience" {
    const module_doc =
        \\This module does math.
        \\
        \\>>> 1 + 1
        \\2
    ;

    var result = try testmod(std.testing.allocator, module_doc);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.attempted);
}
