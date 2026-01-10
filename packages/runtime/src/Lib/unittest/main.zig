//! unittest.main - Test program entry point
//! Reference: cpython/Lib/unittest/main.py
//!
//! CPython __all__: ['TestProgram', 'main', 'MAIN_EXAMPLES', 'MODULE_EXAMPLES']
//!
//! Provides the main entry point for running unittest from command line.

const std = @import("std");
const runner = @import("runner.zig");
const loader_mod = @import("loader.zig");
const result_mod = @import("result.zig");
const suite_mod = @import("suite.zig");

// ============================================================================
// Example Usage Strings (CPython compatibility)
// ============================================================================

/// CPython: MAIN_EXAMPLES
pub const MAIN_EXAMPLES =
    \\Examples:
    \\  %(prog)s test_module               - run tests from test_module
    \\  %(prog)s module.TestClass          - run tests from module.TestClass
    \\  %(prog)s module.Class.test_method  - run specified test method
    \\  %(prog)s path/to/test_file.py      - run tests from test_file.py
    \\
;

/// CPython: MODULE_EXAMPLES
pub const MODULE_EXAMPLES =
    \\Examples:
    \\  %(prog)s                           - run default set of tests
    \\  %(prog)s MyTestSuite               - run suite 'MyTestSuite'
    \\  %(prog)s MyTestCase.testSomething  - run MyTestCase.testSomething
    \\  %(prog)s MyTestCase                - run all 'test*' test methods in MyTestCase
    \\
;

// ============================================================================
// TestProgram
// ============================================================================

/// CPython: class TestProgram
/// Command-line program for running tests
pub const TestProgram = struct {
    allocator: std.mem.Allocator,
    /// Test module to run (None = __main__)
    module: ?[]const u8 = null,
    /// Verbosity level (0=quiet, 1=normal, 2=verbose)
    verbosity: u8 = 1,
    /// Stop on first failure
    failfast: bool = false,
    /// Catch Ctrl-C and display results so far
    catchbreak: bool = false,
    /// Buffer stdout/stderr during tests
    buffer: bool = false,
    /// Pattern for test discovery
    testNamePatterns: ?[]const []const u8 = null,
    /// Whether to exit after running
    exit: bool = true,
    /// Test names to run
    testNames: ?[]const []const u8 = null,
    /// The test loader to use
    testLoader: loader_mod.CPythonTestLoader,
    /// The test runner to use
    testRunner: ?runner.TextTestRunner = null,
    /// The result from running tests
    result: ?*result_mod.CPythonTestResult = null,
    /// Warnings filter
    warnings: ?[]const u8 = null,
    /// Start directory for discovery
    start_dir: []const u8 = ".",
    /// Top-level directory for discovery
    top_level_dir: ?[]const u8 = null,
    /// Discovery pattern
    pattern: []const u8 = "test*.py",
    /// Duration threshold for reporting slow tests
    durations: ?usize = null,

    pub fn init(allocator: std.mem.Allocator) TestProgram {
        return .{
            .allocator = allocator,
            .testLoader = loader_mod.CPythonTestLoader.init(allocator),
        };
    }

    pub fn deinit(self: *TestProgram) void {
        self.testLoader.deinit();
        if (self.result) |r| {
            r.deinit();
            self.allocator.destroy(r);
        }
    }

    /// CPython: def parseArgs(self, argv)
    /// Parse command line arguments
    pub fn parseArgs(self: *TestProgram, argv: []const []const u8) !void {
        var i: usize = 1; // Skip program name
        while (i < argv.len) : (i += 1) {
            const arg = argv[i];
            if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
                self.verbosity = 2;
            } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
                self.verbosity = 0;
            } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--failfast")) {
                self.failfast = true;
            } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--catch")) {
                self.catchbreak = true;
            } else if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--buffer")) {
                self.buffer = true;
            } else if (std.mem.eql(u8, arg, "--locals")) {
                // Enable tb_locals in result
            } else if (std.mem.startsWith(u8, arg, "-k")) {
                // Pattern matching (would need additional parsing)
            } else if (std.mem.startsWith(u8, arg, "--durations")) {
                // Duration tracking
            } else if (!std.mem.startsWith(u8, arg, "-")) {
                // Positional argument - test name
                // Would collect into testNames
            }
        }
    }

    /// CPython: def createTests(self, from_discovery=False, loader=None)
    /// Create the test suite
    pub fn createTests(self: *TestProgram, from_discovery: bool) runner.TestSuite {
        if (from_discovery) {
            return self.testLoader.discover(
                self.start_dir,
                self.pattern,
                self.top_level_dir,
            );
        }
        return runner.TestSuite.init(self.allocator);
    }

    /// CPython: def runTests(self)
    /// Run the tests
    pub fn runTests(self: *TestProgram) !void {
        var test_runner = runner.TextTestRunner.init(self.allocator);
        test_runner.verbosity = self.verbosity;
        test_runner.failfast = self.failfast;
        test_runner.buffer = self.buffer;

        var suite = self.createTests(false);
        defer suite.deinit();

        _ = test_runner.run(&suite);

        if (self.exit) {
            const has_failures = if (runner.global_result) |r| r.failed > 0 else false;
            if (has_failures) {
                std.process.exit(1);
            }
        }
    }
};

// ============================================================================
// Module-level main function
// ============================================================================

/// CPython: main = TestProgram
/// Run unittest.main() - the standard entry point
pub fn main(allocator: std.mem.Allocator) !void {
    // In AOT compilation, test execution is handled by codegen
    // This function exists for API compatibility
    _ = try runner.initRunner(allocator);
}

/// Alternative main that takes argv
pub fn mainWithArgs(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    var program = TestProgram.init(allocator);
    defer program.deinit();

    try program.parseArgs(argv);
    try program.runTests();
}

// ============================================================================
// Helper Functions
// ============================================================================

/// CPython: def _convert_select_pattern(pattern)
/// Convert a test selection pattern to regex
pub fn convertSelectPattern(pattern: []const u8) []const u8 {
    // Simple implementation - just return pattern as-is
    return pattern;
}

// ============================================================================
// Tests
// ============================================================================

test "TestProgram init" {
    const allocator = std.testing.allocator;
    var program = TestProgram.init(allocator);
    defer program.deinit();

    try std.testing.expectEqual(@as(u8, 1), program.verbosity);
    try std.testing.expect(!program.failfast);
}

test "TestProgram parseArgs verbose" {
    const allocator = std.testing.allocator;
    var program = TestProgram.init(allocator);
    defer program.deinit();

    try program.parseArgs(&[_][]const u8{ "test", "-v" });
    try std.testing.expectEqual(@as(u8, 2), program.verbosity);
}

test "TestProgram parseArgs failfast" {
    const allocator = std.testing.allocator;
    var program = TestProgram.init(allocator);
    defer program.deinit();

    try program.parseArgs(&[_][]const u8{ "test", "--failfast" });
    try std.testing.expect(program.failfast);
}
