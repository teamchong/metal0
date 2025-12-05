/// doctest - Test interactive Python examples in docstrings
/// Note: In AOT compilation, doctest is a stub since we can't dynamically
/// execute docstrings at runtime. Tests should use unittest instead.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Output checker for comparing expected vs actual output
pub const OutputChecker = struct {
    optionflags: u32 = 0,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Check if want matches got
    pub fn check_output(self: *Self, want: []const u8, got: []const u8, optionflags: u32) bool {
        _ = optionflags;
        _ = self;
        // Simple comparison - real doctest has complex matching
        return std.mem.eql(u8, std.mem.trim(u8, want, " \n\r\t"), std.mem.trim(u8, got, " \n\r\t"));
    }

    /// Get diff between want and got
    pub fn output_difference(self: *Self, example: []const u8, got: []const u8, optionflags: u32) []const u8 {
        _ = self;
        _ = example;
        _ = got;
        _ = optionflags;
        return ""; // Stub
    }
};

/// Example - a single doctest example
pub const Example = struct {
    source: []const u8,
    want: []const u8,
    lineno: usize = 0,
    indent: usize = 0,
    options: u32 = 0,

    pub fn init(source: []const u8, want: []const u8) Example {
        return .{
            .source = source,
            .want = want,
        };
    }
};

/// DocTest - a collection of examples extracted from a docstring
pub const DocTest = struct {
    examples: std.ArrayList(Example),
    name: []const u8,
    filename: []const u8,
    lineno: usize,
    docstring: []const u8,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, docstring: []const u8, name: []const u8) Self {
        return .{
            .examples = std.ArrayList(Example){},
            .name = name,
            .filename = "<doctest>",
            .lineno = 0,
            .docstring = docstring,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.examples.deinit(self.allocator);
    }
};

/// DocTestParser - parses examples from docstrings
pub const DocTestParser = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Parse docstring and extract examples
    pub fn parse(self: *Self, allocator: Allocator, docstring: []const u8, name: []const u8) DocTest {
        _ = self;
        var test_obj = DocTest.init(allocator, docstring, name);

        // Simple parsing: look for >>> and expected output
        var lines = std.mem.splitScalar(u8, docstring, '\n');
        var current_source: ?[]const u8 = null;
        var collecting_output = false;
        var output_lines = std.ArrayList(u8){};
        defer output_lines.deinit(allocator);

        while (lines.next()) |line| {
            const trimmed = std.mem.trimLeft(u8, line, " \t");

            if (std.mem.startsWith(u8, trimmed, ">>> ")) {
                // New example - save previous if any
                if (current_source) |src| {
                    const want = output_lines.toOwnedSlice(allocator) catch "";
                    test_obj.examples.append(allocator, Example.init(src, want)) catch {};
                    output_lines.clearRetainingCapacity();
                }
                current_source = trimmed[4..];
                collecting_output = true;
            } else if (std.mem.startsWith(u8, trimmed, "... ")) {
                // Continuation line - append to source
                if (current_source) |_| {
                    // Would need to concat, skip for simplicity
                }
            } else if (collecting_output and trimmed.len > 0) {
                // Output line
                output_lines.appendSlice(allocator, trimmed) catch {};
                output_lines.append(allocator, '\n') catch {};
            } else if (trimmed.len == 0) {
                collecting_output = false;
            }
        }

        // Save last example
        if (current_source) |src| {
            const want = output_lines.toOwnedSlice(allocator) catch "";
            test_obj.examples.append(allocator, Example.init(src, want)) catch {};
        }

        return test_obj;
    }
};

/// DocTestRunner - runs doctests
pub const DocTestRunner = struct {
    verbose: bool = false,
    optionflags: u32 = 0,
    checker: OutputChecker,

    // Results
    tries: usize = 0,
    failures: usize = 0,

    const Self = @This();

    pub fn init() Self {
        return .{
            .checker = OutputChecker.init(),
        };
    }

    /// Run a doctest
    pub fn run(self: *Self, test_obj: *DocTest) void {
        for (test_obj.examples.items) |example| {
            self.tries += 1;
            // In AOT, we can't actually execute the code
            // Mark as success if no expected output, otherwise skip
            if (example.want.len == 0) {
                // No expected output - consider it passed
            } else {
                // Has expected output but we can't execute
                self.failures += 1;
            }
        }
    }

    /// Summarize results
    pub fn summarize(self: *Self) void {
        if (self.verbose) {
            std.debug.print("{d} tests, {d} failures\n", .{ self.tries, self.failures });
        }
    }
};

/// DocTestFinder - finds doctests in modules
pub const DocTestFinder = struct {
    verbose: bool = false,
    recurse: bool = true,
    exclude_empty: bool = true,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Find doctests (stub - returns empty in AOT)
    pub fn find(self: *Self, allocator: Allocator, module: anytype) std.ArrayList(DocTest) {
        _ = self;
        _ = allocator;
        _ = module;
        return std.ArrayList(DocTest){};
    }
};

/// Run doctests on a module (stub for AOT)
pub fn testmod(allocator: Allocator, module: anytype, verbose: bool) struct { failures: usize, tests: usize } {
    _ = allocator;
    _ = module;
    _ = verbose;
    // In AOT, we can't dynamically extract and run doctests
    return .{ .failures = 0, .tests = 0 };
}

/// Run doctests from a file (stub for AOT)
pub fn testfile(allocator: Allocator, filename: []const u8, verbose: bool) struct { failures: usize, tests: usize } {
    _ = allocator;
    _ = filename;
    _ = verbose;
    return .{ .failures = 0, .tests = 0 };
}

/// Run a single doctest string
pub fn run_docstring_examples(allocator: Allocator, docstring: []const u8, name: []const u8, verbose: bool) struct { failures: usize, tests: usize } {
    var parser = DocTestParser.init();
    var test_obj = parser.parse(allocator, docstring, name);
    defer test_obj.deinit();

    var runner = DocTestRunner.init();
    runner.verbose = verbose;
    runner.run(&test_obj);

    return .{ .failures = runner.failures, .tests = runner.tries };
}

// Option flags
pub const OPTIONFLAGS = struct {
    pub const DONT_ACCEPT_TRUE_FOR_1: u32 = 1 << 0;
    pub const DONT_ACCEPT_BLANKLINE: u32 = 1 << 1;
    pub const NORMALIZE_WHITESPACE: u32 = 1 << 2;
    pub const ELLIPSIS: u32 = 1 << 3;
    pub const SKIP: u32 = 1 << 4;
    pub const IGNORE_EXCEPTION_DETAIL: u32 = 1 << 5;
    pub const REPORT_UDIFF: u32 = 1 << 6;
    pub const REPORT_CDIFF: u32 = 1 << 7;
    pub const REPORT_NDIFF: u32 = 1 << 8;
    pub const REPORT_ONLY_FIRST_FAILURE: u32 = 1 << 9;
    pub const FAIL_FAST: u32 = 1 << 10;
};

// ============================================================================
// Tests
// ============================================================================

test "DocTestParser parse" {
    const testing = std.testing;
    var parser = DocTestParser.init();

    const docstring =
        \\This is a docstring.
        \\
        \\>>> 1 + 1
        \\2
        \\>>> "hello"
        \\'hello'
    ;

    var test_obj = parser.parse(testing.allocator, docstring, "test");
    defer {
        // Free the want strings that were allocated
        for (test_obj.examples.items) |example| {
            if (example.want.len > 0) {
                testing.allocator.free(example.want);
            }
        }
        test_obj.deinit();
    }

    try testing.expectEqual(@as(usize, 2), test_obj.examples.items.len);
}

test "OutputChecker" {
    var checker = OutputChecker.init();

    try std.testing.expect(checker.check_output("hello", "hello", 0));
    try std.testing.expect(checker.check_output("  hello  ", "hello", 0));
    try std.testing.expect(!checker.check_output("hello", "world", 0));
}
