//! unittest.result - Test result tracking
//! Reference: cpython/Lib/unittest/result.py
//!
//! CPython __all__: ['TestResult']
//!
//! Provides TestResult class for tracking test execution outcomes.

const std = @import("std");
const runner = @import("runner.zig");

// ============================================================================
// Re-export from runner (DRY)
// ============================================================================

/// TestResult - Holder for test result information
/// CPython: class TestResult
pub const TestResult = runner.TestResult;

// ============================================================================
// Extended TestResult with Full CPython API
// ============================================================================

/// CPythonTestResult - Full CPython-compatible TestResult
/// Provides complete API matching Python's unittest.TestResult
pub const CPythonTestResult = struct {
    /// Number of tests run
    testsRun: usize = 0,
    /// List of (test, traceback) for failures
    failures: std.ArrayListUnmanaged(TestErrorInfo) = .{},
    /// List of (test, traceback) for errors
    errors: std.ArrayListUnmanaged(TestErrorInfo) = .{},
    /// List of (test, reason) for skipped tests
    skipped: std.ArrayListUnmanaged(TestSkipInfo) = .{},
    /// List of (test, traceback) for expected failures
    expectedFailures: std.ArrayListUnmanaged(TestErrorInfo) = .{},
    /// List of tests that passed unexpectedly
    unexpectedSuccesses: std.ArrayListUnmanaged(TestInfo) = .{},
    /// Stop on first failure/error
    shouldStop: bool = false,
    /// Buffer stdout/stderr during test runs
    buffer: bool = false,
    /// Stop on first failure
    failfast: bool = false,
    /// Include local variables in tracebacks
    tb_locals: bool = false,
    /// Allocator for dynamic lists
    allocator: std.mem.Allocator,

    pub const TestInfo = struct {
        test_name: []const u8,
        test_class: []const u8,
    };

    pub const TestErrorInfo = struct {
        test_name: []const u8,
        test_class: []const u8,
        traceback: []const u8,
    };

    pub const TestSkipInfo = struct {
        test_name: []const u8,
        test_class: []const u8,
        reason: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) CPythonTestResult {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CPythonTestResult) void {
        self.failures.deinit(self.allocator);
        self.errors.deinit(self.allocator);
        self.skipped.deinit(self.allocator);
        self.expectedFailures.deinit(self.allocator);
        self.unexpectedSuccesses.deinit(self.allocator);
    }

    /// CPython: def startTest(self, test)
    /// Called when a test is about to run
    pub fn startTest(self: *CPythonTestResult, _: anytype) void {
        self.testsRun += 1;
    }

    /// CPython: def stopTest(self, test)
    /// Called after a test has run
    pub fn stopTest(_: *CPythonTestResult, _: anytype) void {
        // Hook for subclasses
    }

    /// CPython: def startTestRun(self)
    /// Called once before any tests are run
    pub fn startTestRun(_: *CPythonTestResult) void {
        // Hook for subclasses
    }

    /// CPython: def stopTestRun(self)
    /// Called once after all tests are run
    pub fn stopTestRun(_: *CPythonTestResult) void {
        // Hook for subclasses
    }

    /// CPython: def addSuccess(self, test)
    /// Called when a test passes
    pub fn addSuccess(_: *CPythonTestResult, _: anytype) void {
        // Success doesn't need tracking (inferred from testsRun - failures - errors)
    }

    /// CPython: def addFailure(self, test, err)
    /// Called when a test fails with an assertion
    pub fn addFailure(self: *CPythonTestResult, test_name: []const u8, test_class: []const u8, traceback: []const u8) !void {
        try self.failures.append(self.allocator, .{
            .test_name = test_name,
            .test_class = test_class,
            .traceback = traceback,
        });
        if (self.failfast) {
            self.shouldStop = true;
        }
    }

    /// CPython: def addError(self, test, err)
    /// Called when a test raises an unexpected exception
    pub fn addError(self: *CPythonTestResult, test_name: []const u8, test_class: []const u8, traceback: []const u8) !void {
        try self.errors.append(self.allocator, .{
            .test_name = test_name,
            .test_class = test_class,
            .traceback = traceback,
        });
        if (self.failfast) {
            self.shouldStop = true;
        }
    }

    /// CPython: def addSkip(self, test, reason)
    /// Called when a test is skipped
    pub fn addSkip(self: *CPythonTestResult, test_name: []const u8, test_class: []const u8, reason: []const u8) !void {
        try self.skipped.append(self.allocator, .{
            .test_name = test_name,
            .test_class = test_class,
            .reason = reason,
        });
    }

    /// CPython: def addExpectedFailure(self, test, err)
    /// Called when an expected failure occurs
    pub fn addExpectedFailure(self: *CPythonTestResult, test_name: []const u8, test_class: []const u8, traceback: []const u8) !void {
        try self.expectedFailures.append(self.allocator, .{
            .test_name = test_name,
            .test_class = test_class,
            .traceback = traceback,
        });
    }

    /// CPython: def addUnexpectedSuccess(self, test)
    /// Called when a test expected to fail passes
    pub fn addUnexpectedSuccess(self: *CPythonTestResult, test_name: []const u8, test_class: []const u8) !void {
        try self.unexpectedSuccesses.append(self.allocator, .{
            .test_name = test_name,
            .test_class = test_class,
        });
        if (self.failfast) {
            self.shouldStop = true;
        }
    }

    /// CPython: def wasSuccessful(self)
    /// Returns True if all tests run so far passed
    pub fn wasSuccessful(self: *const CPythonTestResult) bool {
        return self.failures.items.len == 0 and
            self.errors.items.len == 0 and
            self.unexpectedSuccesses.items.len == 0;
    }

    /// CPython: def stop(self)
    /// Signal that tests should stop
    pub fn stop(self: *CPythonTestResult) void {
        self.shouldStop = true;
    }

    /// Get count of successful tests
    pub fn successCount(self: *const CPythonTestResult) usize {
        const failed = self.failures.items.len +
            self.errors.items.len +
            self.skipped.items.len +
            self.expectedFailures.items.len +
            self.unexpectedSuccesses.items.len;
        return if (self.testsRun > failed) self.testsRun - failed else 0;
    }

    /// Print summary to stderr (like Python's TextTestResult)
    pub fn printSummary(self: *const CPythonTestResult) void {
        const writer = std.io.getStdErr().writer();
        writer.print("\n", .{}) catch {};
        writer.print("----------------------------------------------------------------------\n", .{}) catch {};
        writer.print("Ran {d} test(s)\n\n", .{self.testsRun}) catch {};

        if (self.wasSuccessful()) {
            writer.print("OK", .{}) catch {};
        } else {
            writer.print("FAILED", .{}) catch {};
        }

        // Print details
        var infos = std.ArrayList(u8).init(self.allocator);
        defer infos.deinit();

        if (self.failures.items.len > 0) {
            writer.print(" (failures={d})", .{self.failures.items.len}) catch {};
        }
        if (self.errors.items.len > 0) {
            writer.print(" (errors={d})", .{self.errors.items.len}) catch {};
        }
        if (self.skipped.items.len > 0) {
            writer.print(" (skipped={d})", .{self.skipped.items.len}) catch {};
        }
        if (self.expectedFailures.items.len > 0) {
            writer.print(" (expected failures={d})", .{self.expectedFailures.items.len}) catch {};
        }
        if (self.unexpectedSuccesses.items.len > 0) {
            writer.print(" (unexpected successes={d})", .{self.unexpectedSuccesses.items.len}) catch {};
        }

        writer.print("\n", .{}) catch {};
    }
};

// ============================================================================
// Tests
// ============================================================================

test "CPythonTestResult basic" {
    const allocator = std.testing.allocator;
    var result = CPythonTestResult.init(allocator);
    defer result.deinit();

    result.startTestRun();
    result.startTest({});
    result.addSuccess({});
    result.stopTest({});
    result.stopTestRun();

    try std.testing.expectEqual(@as(usize, 1), result.testsRun);
    try std.testing.expect(result.wasSuccessful());
}

test "CPythonTestResult failure" {
    const allocator = std.testing.allocator;
    var result = CPythonTestResult.init(allocator);
    defer result.deinit();

    result.startTest({});
    try result.addFailure("test_foo", "TestClass", "AssertionError");
    result.stopTest({});

    try std.testing.expectEqual(@as(usize, 1), result.testsRun);
    try std.testing.expect(!result.wasSuccessful());
    try std.testing.expectEqual(@as(usize, 1), result.failures.items.len);
}

test "CPythonTestResult skip" {
    const allocator = std.testing.allocator;
    var result = CPythonTestResult.init(allocator);
    defer result.deinit();

    result.startTest({});
    try result.addSkip("test_skip", "TestClass", "not implemented");
    result.stopTest({});

    try std.testing.expectEqual(@as(usize, 1), result.skipped.items.len);
}
