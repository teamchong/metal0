/// metal0 unittest runner - test result tracking and lifecycle
const std = @import("std");

/// Test result tracking
pub const TestResult = struct {
    passed: usize = 0,
    failed: usize = 0,
    errors: std.ArrayListUnmanaged([]const u8) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestResult {
        return .{
            .passed = 0,
            .failed = 0,
            .errors = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestResult) void {
        for (self.errors.items) |err| {
            self.allocator.free(err);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn addPass(self: *TestResult) void {
        self.passed += 1;
    }

    pub fn addFail(self: *TestResult, msg: []const u8) !void {
        self.failed += 1;
        const duped = try self.allocator.dupe(u8, msg);
        try self.errors.append(self.allocator, duped);
    }
};

/// Global test result for current test run
pub var global_result: ?*TestResult = null;
pub var global_allocator: ?std.mem.Allocator = null;

/// Initialize test runner
pub fn initRunner(allocator: std.mem.Allocator) !*TestResult {
    const result = try allocator.create(TestResult);
    result.* = TestResult.init(allocator);
    global_result = result;
    global_allocator = allocator;
    return result;
}

/// Print test results summary
pub fn printResults() void {
    if (global_result) |result| {
        std.debug.print("\n", .{});
        std.debug.print("----------------------------------------------------------------------\n", .{});
        std.debug.print("Ran {d} test(s)\n\n", .{result.passed + result.failed});
        if (result.failed == 0) {
            std.debug.print("OK\n", .{});
        } else {
            std.debug.print("FAILED (failures={d})\n", .{result.failed});
            for (result.errors.items) |err| {
                std.debug.print("  - {s}\n", .{err});
            }
        }
    }
}

/// Cleanup test runner
pub fn deinitRunner() void {
    if (global_result) |result| {
        if (global_allocator) |alloc| {
            result.deinit();
            alloc.destroy(result);
        }
    }
    global_result = null;
    global_allocator = null;
}

/// Main entry point - called by unittest.main()
pub fn main(allocator: std.mem.Allocator) !void {
    _ = try initRunner(allocator);
}

/// Finalize and print results - called after all tests run
pub fn finalize() void {
    printResults();
    deinitRunner();
}

/// Mock value - can be null, string, int, bool, or error
pub const MockValue = union(enum) {
    none: void,
    string: []const u8,
    bytes: []const u8,
    int: i64,
    boolean: bool,
    err: []const u8, // Error type name for side_effect
};

/// Mock object for unittest.mock support
/// Used by @mock.patch.object decorator
pub const Mock = struct {
    return_value: MockValue = .{ .none = {} },
    side_effect: ?MockValue = null,
    called: bool = false,
    call_count: i64 = 0,

    pub fn init() Mock {
        return .{};
    }

    /// Call the mock - increments call_count and returns return_value
    pub fn call(self: *Mock, _: anytype) MockValue {
        self.called = true;
        self.call_count += 1;
        if (self.side_effect) |effect| {
            // For side_effect errors, we'd normally throw an error here
            // For now just return the effect
            return effect;
        }
        return self.return_value;
    }

    /// Reset mock state
    pub fn reset(self: *Mock) void {
        self.called = false;
        self.call_count = 0;
    }
};

// ============================================================================
// TestCase methods for 100% CPython alignment
// ============================================================================

/// Maximum number of characters in diff output (None = unlimited in Python)
/// Default is 80*8 characters
pub var maxDiff: ?usize = 640;

/// fail(msg) - Fail immediately with the given message
pub fn fail(msg: []const u8) noreturn {
    std.debug.print("AssertionError: {s}\n", .{msg});
    if (global_result) |result| {
        result.addFail(msg) catch {};
    }
    @panic("Test failed");
}

/// failUnlessEqual - Alias for assertEqual (deprecated but still in CPython)
pub const failUnlessEqual = @import("assertions_basic.zig").assertEqual;

/// failIfEqual - Alias for assertNotEqual (deprecated but still in CPython)
pub const failIfEqual = @import("assertions_basic.zig").assertNotEqual;

/// failUnless - Alias for assertTrue (deprecated but still in CPython)
pub const failUnless = @import("assertions_basic.zig").assertTrue;

/// failIf - Alias for assertFalse (deprecated but still in CPython)
pub const failIf = @import("assertions_basic.zig").assertFalse;

// ============================================================================
// TestSuite - Collection of test cases
// ============================================================================

/// TestSuite - A collection of test cases and test suites
pub const TestSuite = struct {
    tests: std.ArrayListUnmanaged(TestEntry) = .{},
    allocator: std.mem.Allocator,

    pub const TestEntry = union(enum) {
        test_func: *const fn () void,
        suite: *TestSuite,
    };

    pub fn init(allocator: std.mem.Allocator) TestSuite {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TestSuite) void {
        self.tests.deinit(self.allocator);
    }

    /// Add a test function to the suite
    pub fn addTest(self: *TestSuite, test_func: *const fn () void) !void {
        try self.tests.append(self.allocator, .{ .test_func = test_func });
    }

    /// Add a nested test suite
    pub fn addSuite(self: *TestSuite, suite: *TestSuite) !void {
        try self.tests.append(self.allocator, .{ .suite = suite });
    }

    /// Add multiple tests from a slice
    pub fn addTests(self: *TestSuite, test_funcs: []const *const fn () void) !void {
        for (test_funcs) |func| {
            try self.addTest(func);
        }
    }

    /// Run all tests in the suite
    pub fn run(self: *TestSuite, result: *TestResult) void {
        for (self.tests.items) |entry| {
            switch (entry) {
                .test_func => |func| {
                    func();
                },
                .suite => |suite| {
                    suite.run(result);
                },
            }
        }
    }

    /// Count total number of tests (including nested suites)
    pub fn countTestCases(self: *const TestSuite) usize {
        var count: usize = 0;
        for (self.tests.items) |entry| {
            switch (entry) {
                .test_func => count += 1,
                .suite => |suite| count += suite.countTestCases(),
            }
        }
        return count;
    }
};

// ============================================================================
// TestLoader - Load tests from modules/classes
// ============================================================================

/// TestLoader - Load and discover test cases
pub const TestLoader = struct {
    allocator: std.mem.Allocator,
    testMethodPrefix: []const u8 = "test",
    sortTestMethodsUsing: ?*const fn ([]const u8, []const u8) bool = null,
    suiteClass: type = TestSuite,

    pub fn init(allocator: std.mem.Allocator) TestLoader {
        return .{ .allocator = allocator };
    }

    /// Load tests from a test case class (compile-time)
    /// In AOT, this is handled by codegen - this is a runtime stub
    pub fn loadTestsFromTestCase(self: *TestLoader, comptime TestClass: type) TestSuite {
        const suite = TestSuite.init(self.allocator);
        // In AOT compilation, test discovery happens at compile time
        // This is a stub for API compatibility
        _ = TestClass;
        return suite;
    }

    /// Load tests from a module (compile-time)
    pub fn loadTestsFromModule(self: *TestLoader, comptime Module: type) TestSuite {
        const suite = TestSuite.init(self.allocator);
        _ = Module;
        return suite;
    }

    /// Load tests from test names
    pub fn loadTestsFromNames(self: *TestLoader, names: []const []const u8) TestSuite {
        const suite = TestSuite.init(self.allocator);
        _ = names;
        return suite;
    }

    /// Discover tests in a directory (not applicable to AOT - compile-time discovery)
    pub fn discover(self: *TestLoader, start_dir: []const u8, pattern: []const u8, top_level_dir: ?[]const u8) TestSuite {
        _ = start_dir;
        _ = pattern;
        _ = top_level_dir;
        return TestSuite.init(self.allocator);
    }
};

// ============================================================================
// TextTestRunner - Run tests with text output
// ============================================================================

/// TextTestRunner - A test runner that displays results in textual form
pub const TextTestRunner = struct {
    allocator: std.mem.Allocator,
    verbosity: u8 = 1,
    failfast: bool = false,
    buffer: bool = false,

    pub fn init(allocator: std.mem.Allocator) TextTestRunner {
        return .{ .allocator = allocator };
    }

    /// Run the test suite
    pub fn run(self: *TextTestRunner, suite: *TestSuite) *TestResult {
        const result = global_result orelse blk: {
            const r = self.allocator.create(TestResult) catch @panic("OOM");
            r.* = TestResult.init(self.allocator);
            global_result = r;
            break :blk r;
        };

        suite.run(result);
        printResults();
        return result;
    }
};
