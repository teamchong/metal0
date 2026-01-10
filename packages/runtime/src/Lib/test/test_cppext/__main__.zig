//! test.test_cppext - C++ extension functionality tests
//!
//! This module provides comprehensive testing for C++ extension interoperability,
//! including modules, exceptions, templates, overloads, namespaces, classes,
//! inheritance, STL containers, RAII, and operator overloading.

const std = @import("std");

// Import all submodules for testing
pub const test_cpp_module = @import("test_cpp_module.zig");
pub const test_exceptions = @import("test_exceptions.zig");
pub const test_templates = @import("test_templates.zig");
pub const test_overloads = @import("test_overloads.zig");
pub const test_namespaces = @import("test_namespaces.zig");
pub const test_classes = @import("test_classes.zig");
pub const test_inheritance = @import("test_inheritance.zig");
pub const test_stl = @import("test_stl.zig");
pub const test_raii = @import("test_raii.zig");
pub const test_operators = @import("test_operators.zig");

/// Test context for tracking test execution
pub const TestContext = struct {
    name: []const u8,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{ .allocator = allocator, .name = name };
    }

    pub fn run(self: *@This()) bool {
        self.passed += 1;
        return self.failed == 0;
    }

    pub fn assertEqual(self: *@This(), expected: anytype, actual: anytype) !void {
        if (expected != actual) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn assertTrue(self: *@This(), value: bool) !void {
        if (!value) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn assertFalse(self: *@This(), value: bool) !void {
        if (value) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn skip(self: *@This()) void {
        self.skipped += 1;
    }

    pub fn totalTests(self: @This()) usize {
        return self.passed + self.failed + self.skipped;
    }

    pub fn successRate(self: @This()) f64 {
        const total = self.passed + self.failed;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.passed)) / @as(f64, @floatFromInt(total));
    }
};

/// Test result aggregation
pub const TestResult = struct {
    tests_run: usize = 0,
    failures: usize = 0,
    errors: usize = 0,
    skipped: usize = 0,
    duration_ns: u64 = 0,

    pub fn wasSuccessful(self: @This()) bool {
        return self.failures == 0 and self.errors == 0;
    }

    pub fn merge(self: *@This(), other: TestResult) void {
        self.tests_run += other.tests_run;
        self.failures += other.failures;
        self.errors += other.errors;
        self.skipped += other.skipped;
        self.duration_ns += other.duration_ns;
    }

    pub fn format(self: @This(), buf: []u8) []const u8 {
        const result = std.fmt.bufPrint(buf, "Tests: {d}, Failures: {d}, Errors: {d}, Skipped: {d}", .{
            self.tests_run,
            self.failures,
            self.errors,
            self.skipped,
        }) catch return "";
        return result;
    }
};

/// Test suite for organizing related tests
pub const TestSuite = struct {
    name: []const u8,
    results: std.ArrayList(TestResult),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) TestSuite {
        return .{
            .name = name,
            .results = std.ArrayList(TestResult).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestSuite) void {
        self.results.deinit();
    }

    pub fn addResult(self: *TestSuite, result: TestResult) !void {
        try self.results.append(result);
    }

    pub fn aggregate(self: TestSuite) TestResult {
        var total = TestResult{};
        for (self.results.items) |result| {
            total.merge(result);
        }
        return total;
    }

    pub fn wasSuccessful(self: TestSuite) bool {
        return self.aggregate().wasSuccessful();
    }
};

// Reference all test declarations to ensure they're compiled
comptime {
    // test_cpp_module tests
    _ = test_cpp_module;
    _ = test_exceptions;
    _ = test_templates;
    _ = test_overloads;
    _ = test_namespaces;
    _ = test_classes;
    _ = test_inheritance;
    _ = test_stl;
    _ = test_raii;
    _ = test_operators;
}

test "cppext_basic" {
    var ctx = TestContext.init(std.testing.allocator, "test_cppext");
    try std.testing.expect(ctx.run());
}

test "cppext_result" {
    const result = TestResult{ .tests_run = 1 };
    try std.testing.expect(result.wasSuccessful());
}

test "cppext_suite" {
    const allocator = std.testing.allocator;
    var suite = TestSuite.init(allocator, "cppext");
    defer suite.deinit();

    try suite.addResult(TestResult{ .tests_run = 5, .failures = 0 });
    try suite.addResult(TestResult{ .tests_run = 3, .failures = 0 });

    const aggregate = suite.aggregate();
    try std.testing.expectEqual(@as(usize, 8), aggregate.tests_run);
    try std.testing.expect(suite.wasSuccessful());
}

test "test_context_assertions" {
    const allocator = std.testing.allocator;
    var ctx = TestContext.init(allocator, "assertions");

    try ctx.assertTrue(true);
    try std.testing.expectEqual(@as(usize, 1), ctx.passed);

    try ctx.assertFalse(false);
    try std.testing.expectEqual(@as(usize, 2), ctx.passed);

    try ctx.assertEqual(@as(i32, 42), @as(i32, 42));
    try std.testing.expectEqual(@as(usize, 3), ctx.passed);

    ctx.skip();
    try std.testing.expectEqual(@as(usize, 1), ctx.skipped);

    try std.testing.expectEqual(@as(usize, 4), ctx.totalTests());
}

test "test_result_merge" {
    var result1 = TestResult{ .tests_run = 5, .failures = 1, .errors = 0 };
    const result2 = TestResult{ .tests_run = 3, .failures = 0, .errors = 1 };

    result1.merge(result2);
    try std.testing.expectEqual(@as(usize, 8), result1.tests_run);
    try std.testing.expectEqual(@as(usize, 1), result1.failures);
    try std.testing.expectEqual(@as(usize, 1), result1.errors);
    try std.testing.expect(!result1.wasSuccessful());
}
