//! unittest.suite - Test suite collection
//! Reference: cpython/Lib/unittest/suite.py
//!
//! CPython __all__: ['BaseTestSuite', 'TestSuite']
//!
//! Provides test suite classes for grouping and running tests.

const std = @import("std");
const runner = @import("runner.zig");

// ============================================================================
// Re-export from runner (DRY)
// ============================================================================

/// TestSuite - A test suite that aggregates tests
/// CPython: class TestSuite(BaseTestSuite)
pub const TestSuite = runner.TestSuite;

// ============================================================================
// BaseTestSuite
// ============================================================================

/// BaseTestSuite - Base class for test suites
/// CPython: class BaseTestSuite
/// A simple test suite that doesn't provide extended functionality
pub const BaseTestSuite = struct {
    tests: std.ArrayListUnmanaged(TestEntry) = .{},
    allocator: std.mem.Allocator,

    pub const TestEntry = union(enum) {
        test_func: *const fn () void,
        suite: *BaseTestSuite,
    };

    pub fn init(allocator: std.mem.Allocator) BaseTestSuite {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BaseTestSuite) void {
        self.tests.deinit(self.allocator);
    }

    /// CPython: def __iter__(self)
    /// Iterate over tests in the suite
    pub fn iterator(self: *const BaseTestSuite) []const TestEntry {
        return self.tests.items;
    }

    /// CPython: def countTestCases(self)
    /// Count total test cases (recursive)
    pub fn countTestCases(self: *const BaseTestSuite) usize {
        var count: usize = 0;
        for (self.tests.items) |entry| {
            switch (entry) {
                .test_func => count += 1,
                .suite => |suite| count += suite.countTestCases(),
            }
        }
        return count;
    }

    /// CPython: def addTest(self, test)
    /// Add a test to the suite
    pub fn addTest(self: *BaseTestSuite, test_func: *const fn () void) !void {
        try self.tests.append(self.allocator, .{ .test_func = test_func });
    }

    /// CPython: def addTests(self, tests)
    /// Add multiple tests to the suite
    pub fn addTests(self: *BaseTestSuite, test_funcs: []const *const fn () void) !void {
        for (test_funcs) |func| {
            try self.addTest(func);
        }
    }

    /// CPython: def run(self, result)
    /// Run all tests in the suite
    pub fn run(self: *BaseTestSuite, result: *runner.TestResult) void {
        for (self.tests.items) |entry| {
            switch (entry) {
                .test_func => |func| {
                    func();
                    _ = result;
                },
                .suite => |suite| {
                    suite.run(result);
                },
            }
        }
    }

    /// CPython: def __eq__(self, other)
    /// Check equality with another suite
    pub fn eql(self: *const BaseTestSuite, other: *const BaseTestSuite) bool {
        if (self.tests.items.len != other.tests.items.len) return false;
        // Deep comparison would require test identity tracking
        return true;
    }

    /// CPython: def __call__(self, result)
    /// Make suite callable (alias for run)
    pub fn call(self: *BaseTestSuite, result: *runner.TestResult) void {
        self.run(result);
    }

    /// CPython: def debug(self)
    /// Run without collecting results (for debugging)
    pub fn debug(self: *BaseTestSuite) void {
        for (self.tests.items) |entry| {
            switch (entry) {
                .test_func => |func| func(),
                .suite => |suite| suite.debug(),
            }
        }
    }
};

// ============================================================================
// Extended TestSuite with CPython Features
// ============================================================================

/// CPythonTestSuite - Full CPython-compatible TestSuite
/// Extends BaseTestSuite with class setup/teardown support
pub const CPythonTestSuite = struct {
    base: BaseTestSuite,
    /// Whether to run tests in debug mode (no result collection)
    debug_mode: bool = false,

    pub fn init(allocator: std.mem.Allocator) CPythonTestSuite {
        return .{ .base = BaseTestSuite.init(allocator) };
    }

    pub fn deinit(self: *CPythonTestSuite) void {
        self.base.deinit();
    }

    /// CPython: def countTestCases(self)
    pub fn countTestCases(self: *const CPythonTestSuite) usize {
        return self.base.countTestCases();
    }

    /// CPython: def addTest(self, test)
    pub fn addTest(self: *CPythonTestSuite, test_func: *const fn () void) !void {
        try self.base.addTest(test_func);
    }

    /// CPython: def addTests(self, tests)
    pub fn addTests(self: *CPythonTestSuite, test_funcs: []const *const fn () void) !void {
        try self.base.addTests(test_funcs);
    }

    /// CPython: def run(self, result)
    /// Run with class-level setUp/tearDown support
    pub fn run(self: *CPythonTestSuite, result: *runner.TestResult) void {
        // In AOT, class setup/teardown is handled by codegen
        self.base.run(result);
    }

    /// CPython: def debug(self)
    pub fn debug(self: *CPythonTestSuite) void {
        self.base.debug();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "BaseTestSuite basic" {
    const allocator = std.testing.allocator;
    var suite = BaseTestSuite.init(allocator);
    defer suite.deinit();

    try std.testing.expectEqual(@as(usize, 0), suite.countTestCases());
}

test "CPythonTestSuite basic" {
    const allocator = std.testing.allocator;
    var suite = CPythonTestSuite.init(allocator);
    defer suite.deinit();

    try std.testing.expectEqual(@as(usize, 0), suite.countTestCases());
}
