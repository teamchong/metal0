//! test.test_module - Module functionality tests
//! Tests for Python's import system and module handling
//! Reference: CPython Lib/test/test_module.py

const std = @import("std");

// Import all test modules
pub const test_api = @import("test_api.zig");
pub const test_spec = @import("test_spec.zig");
pub const test_loader = @import("test_loader.zig");
pub const test_finder = @import("test_finder.zig");
pub const test_meta = @import("test_meta.zig");
pub const test_pkg = @import("test_pkg.zig");
pub const test_relative = @import("test_relative.zig");
pub const test_circular = @import("test_circular.zig");
pub const test_reload = @import("test_reload.zig");
pub const test_path = @import("test_path.zig");

// ============================================================================
// Test Context for Integration
// ============================================================================

pub const TestContext = struct {
    name: []const u8,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{ .allocator = allocator, .name = name };
    }

    pub fn run(self: *Self) bool {
        self.passed += 1;
        return self.failed == 0;
    }

    pub fn assertEqual(self: *Self, expected: anytype, actual: anytype) !void {
        if (expected != actual) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn assertTrue(self: *Self, value: bool) !void {
        if (!value) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn assertFalse(self: *Self, value: bool) !void {
        if (value) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn skip(self: *Self, reason: []const u8) void {
        _ = reason;
        self.skipped += 1;
    }

    pub fn summary(self: *const Self) void {
        std.debug.print("Test {s}: {} passed, {} failed, {} skipped\n", .{
            self.name,
            self.passed,
            self.failed,
            self.skipped,
        });
    }
};

// ============================================================================
// Test Result Aggregation
// ============================================================================

pub const TestResult = struct {
    tests_run: usize = 0,
    failures: usize = 0,
    errors: usize = 0,
    skipped: usize = 0,

    pub fn wasSuccessful(self: @This()) bool {
        return self.failures == 0 and self.errors == 0;
    }

    pub fn addPass(self: *@This()) void {
        self.tests_run += 1;
    }

    pub fn addFail(self: *@This()) void {
        self.tests_run += 1;
        self.failures += 1;
    }

    pub fn addError(self: *@This()) void {
        self.tests_run += 1;
        self.errors += 1;
    }

    pub fn addSkip(self: *@This()) void {
        self.skipped += 1;
    }

    pub fn merge(self: *@This(), other: TestResult) void {
        self.tests_run += other.tests_run;
        self.failures += other.failures;
        self.errors += other.errors;
        self.skipped += other.skipped;
    }
};

// ============================================================================
// Test Suite Information
// ============================================================================

pub const TestSuiteInfo = struct {
    name: []const u8,
    description: []const u8,
    module_count: usize,

    pub fn format(self: TestSuiteInfo, writer: anytype) !void {
        try writer.print("Test Suite: {s}\n", .{self.name});
        try writer.print("  Description: {s}\n", .{self.description});
        try writer.print("  Modules: {}\n", .{self.module_count});
    }
};

/// Get test suite info
pub fn getSuiteInfo() TestSuiteInfo {
    return .{
        .name = "test_module",
        .description = "Python module import system tests",
        .module_count = 10,
    };
}

// ============================================================================
// Zig Tests
// ============================================================================

test "module_basic" {
    var ctx = TestContext.init(std.testing.allocator, "test_module");
    try std.testing.expect(ctx.run());
}

test "module_result" {
    const result = TestResult{ .tests_run = 1 };
    try std.testing.expect(result.wasSuccessful());
}

test "module_result_failure" {
    const result = TestResult{ .tests_run = 2, .failures = 1 };
    try std.testing.expect(!result.wasSuccessful());
}

test "test_context_assertEqual" {
    var ctx = TestContext.init(std.testing.allocator, "equal_test");
    try ctx.assertEqual(@as(i32, 42), @as(i32, 42));
    try std.testing.expectEqual(@as(usize, 1), ctx.passed);
}

test "test_context_assertTrue" {
    var ctx = TestContext.init(std.testing.allocator, "true_test");
    try ctx.assertTrue(true);
    try std.testing.expectEqual(@as(usize, 1), ctx.passed);
}

test "test_context_assertFalse" {
    var ctx = TestContext.init(std.testing.allocator, "false_test");
    try ctx.assertFalse(false);
    try std.testing.expectEqual(@as(usize, 1), ctx.passed);
}

test "test_result_addPass" {
    var result = TestResult{};
    result.addPass();
    try std.testing.expectEqual(@as(usize, 1), result.tests_run);
    try std.testing.expect(result.wasSuccessful());
}

test "test_result_addFail" {
    var result = TestResult{};
    result.addFail();
    try std.testing.expectEqual(@as(usize, 1), result.failures);
    try std.testing.expect(!result.wasSuccessful());
}

test "test_result_addError" {
    var result = TestResult{};
    result.addError();
    try std.testing.expectEqual(@as(usize, 1), result.errors);
    try std.testing.expect(!result.wasSuccessful());
}

test "test_result_merge" {
    var result1 = TestResult{ .tests_run = 5, .failures = 1 };
    const result2 = TestResult{ .tests_run = 3, .failures = 0 };
    result1.merge(result2);
    try std.testing.expectEqual(@as(usize, 8), result1.tests_run);
    try std.testing.expectEqual(@as(usize, 1), result1.failures);
}

test "suite_info" {
    const info = getSuiteInfo();
    try std.testing.expectEqualStrings("test_module", info.name);
    try std.testing.expectEqual(@as(usize, 10), info.module_count);
}

// Reference all submodule tests to ensure they're compiled
test {
    _ = test_api;
    _ = test_spec;
    _ = test_loader;
    _ = test_finder;
    _ = test_meta;
    _ = test_pkg;
    _ = test_relative;
    _ = test_circular;
    _ = test_reload;
    _ = test_path;
}
