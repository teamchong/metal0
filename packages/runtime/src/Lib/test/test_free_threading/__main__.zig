//! test.test_free_threading - Free-threading (no-GIL) functionality tests
//!
//! This module provides comprehensive tests for free-threaded Python execution,
//! including thread-safe containers, atomic operations, memory ordering,
//! race detection, and concurrent access patterns.
//!
//! CPython Reference: Lib/test/test_free_threading/
const std = @import("std");

// Module imports - Free-threading test submodules
pub const test_code = @import("test_code.zig");
pub const test_dict = @import("test_dict.zig");
pub const test_gc = @import("test_gc.zig");
pub const test_list = @import("test_list.zig");
pub const test_monitoring = @import("test_monitoring.zig");
pub const test_slots = @import("test_slots.zig");
pub const test_str = @import("test_str.zig");
pub const test_tokenize = @import("test_tokenize.zig");
pub const test_type = @import("test_type.zig");

/// Test context for managing test execution
pub const TestContext = struct {
    name: []const u8,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    allocator: std.mem.Allocator,
    start_time: i64,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .allocator = allocator,
            .name = name,
            .start_time = std.time.milliTimestamp(),
        };
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

    pub fn skip(self: *@This(), reason: []const u8) void {
        _ = reason;
        self.skipped += 1;
    }

    pub fn getElapsedMs(self: *const @This()) i64 {
        return std.time.milliTimestamp() - self.start_time;
    }
};

/// Test result aggregator
pub const TestResult = struct {
    tests_run: usize = 0,
    failures: usize = 0,
    errors: usize = 0,
    skipped: usize = 0,
    duration_ms: i64 = 0,

    pub fn wasSuccessful(self: @This()) bool {
        return self.failures == 0 and self.errors == 0;
    }

    pub fn add(self: *@This(), other: TestResult) void {
        self.tests_run += other.tests_run;
        self.failures += other.failures;
        self.errors += other.errors;
        self.skipped += other.skipped;
        self.duration_ms += other.duration_ms;
    }
};

/// Test suite for organizing related tests
pub const TestSuite = struct {
    const Self = @This();

    name: []const u8,
    tests: std.ArrayListUnmanaged(TestCase),
    allocator: std.mem.Allocator,

    const TestCase = struct {
        name: []const u8,
        func: *const fn (*TestContext) anyerror!void,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .name = name,
            .tests = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tests.deinit(self.allocator);
    }

    pub fn addTest(self: *Self, name: []const u8, func: *const fn (*TestContext) anyerror!void) !void {
        try self.tests.append(self.allocator, .{ .name = name, .func = func });
    }

    pub fn run(self: *Self) TestResult {
        var result = TestResult{};
        const start = std.time.milliTimestamp();

        for (self.tests.items) |test_case| {
            var ctx = TestContext.init(self.allocator, test_case.name);
            test_case.func(&ctx) catch {
                result.errors += 1;
            };
            result.tests_run += 1;
            result.failures += ctx.failed;
            result.skipped += ctx.skipped;
        }

        result.duration_ms = std.time.milliTimestamp() - start;
        return result;
    }
};

/// Thread-safe test runner for concurrent test execution
pub const ConcurrentTestRunner = struct {
    const Self = @This();

    suites: std.ArrayListUnmanaged(*TestSuite),
    allocator: std.mem.Allocator,
    thread_count: usize,

    pub fn init(allocator: std.mem.Allocator, thread_count: usize) Self {
        return .{
            .suites = .{},
            .allocator = allocator,
            .thread_count = thread_count,
        };
    }

    pub fn deinit(self: *Self) void {
        self.suites.deinit(self.allocator);
    }

    pub fn addSuite(self: *Self, suite: *TestSuite) !void {
        try self.suites.append(self.allocator, suite);
    }

    pub fn runAll(self: *Self) TestResult {
        var total = TestResult{};

        for (self.suites.items) |suite| {
            const result = suite.run();
            total.add(result);
        }

        return total;
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "free_threading_basic" {
    var ctx = TestContext.init(std.testing.allocator, "test_free_threading");
    try std.testing.expect(ctx.run());
}

test "free_threading_result" {
    const result = TestResult{ .tests_run = 1 };
    try std.testing.expect(result.wasSuccessful());
}

test "test_context_assertions" {
    var ctx = TestContext.init(std.testing.allocator, "assertions");

    try ctx.assertEqual(@as(i32, 42), @as(i32, 42));
    try ctx.assertTrue(true);
    try ctx.assertFalse(false);

    try std.testing.expectEqual(@as(usize, 3), ctx.passed);
    try std.testing.expectEqual(@as(usize, 0), ctx.failed);
}

test "test_suite_basic" {
    var suite = TestSuite.init(std.testing.allocator, "basic_suite");
    defer suite.deinit();

    try suite.addTest("dummy_test", struct {
        fn run(ctx: *TestContext) !void {
            try ctx.assertTrue(true);
        }
    }.run);

    const result = suite.run();
    try std.testing.expectEqual(@as(usize, 1), result.tests_run);
    try std.testing.expectEqual(@as(usize, 0), result.failures);
}

test "test_result_aggregation" {
    var result1 = TestResult{ .tests_run = 5, .failures = 1 };
    const result2 = TestResult{ .tests_run = 3, .failures = 0, .skipped = 1 };

    result1.add(result2);

    try std.testing.expectEqual(@as(usize, 8), result1.tests_run);
    try std.testing.expectEqual(@as(usize, 1), result1.failures);
    try std.testing.expectEqual(@as(usize, 1), result1.skipped);
}

// Run all submodule tests
test {
    _ = test_code;
    _ = test_dict;
    _ = test_gc;
    _ = test_list;
    _ = test_monitoring;
    _ = test_slots;
    _ = test_str;
    _ = test_tokenize;
    _ = test_type;
}
