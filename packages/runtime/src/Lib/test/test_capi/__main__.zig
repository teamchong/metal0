//! test.test_capi - Python C API functionality tests
//!
//! This module provides comprehensive tests for the Python C API bindings,
//! including object types, memory management, and type checking.

const std = @import("std");

// Import all submodules for testing
pub const test_buffer = @import("test_buffer.zig");
pub const test_call = @import("test_call.zig");
pub const test_dict = @import("test_dict.zig");
pub const test_float = @import("test_float.zig");
pub const test_list = @import("test_list.zig");
pub const test_long = @import("test_long.zig");
pub const test_misc = @import("test_misc.zig");
pub const test_object = @import("test_object.zig");
pub const test_tuple = @import("test_tuple.zig");
pub const test_unicode = @import("test_unicode.zig");

/// Test context for running C API tests
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

    pub fn skip(self: *@This(), reason: []const u8) void {
        _ = reason;
        self.skipped += 1;
    }

    pub fn report(self: *const @This()) TestResult {
        return .{
            .tests_run = self.passed + self.failed,
            .failures = self.failed,
            .skipped = self.skipped,
        };
    }
};

/// Test result summary
pub const TestResult = struct {
    tests_run: usize = 0,
    failures: usize = 0,
    errors: usize = 0,
    skipped: usize = 0,

    pub fn wasSuccessful(self: @This()) bool {
        return self.failures == 0 and self.errors == 0;
    }

    pub fn merge(self: *@This(), other: TestResult) void {
        self.tests_run += other.tests_run;
        self.failures += other.failures;
        self.errors += other.errors;
        self.skipped += other.skipped;
    }
};

/// Test suite runner
pub const TestSuite = struct {
    name: []const u8,
    results: TestResult = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) TestSuite {
        return .{
            .allocator = allocator,
            .name = name,
        };
    }

    pub fn addResult(self: *TestSuite, result: TestResult) void {
        self.results.merge(result);
    }

    pub fn wasSuccessful(self: *const TestSuite) bool {
        return self.results.wasSuccessful();
    }

    pub fn summary(self: *const TestSuite) struct { passed: usize, failed: usize, skipped: usize } {
        return .{
            .passed = self.results.tests_run - self.results.failures,
            .failed = self.results.failures,
            .skipped = self.results.skipped,
        };
    }
};

// ============================================================================
// Comptime test references - ensure all submodule tests are included
// ============================================================================

comptime {
    _ = test_buffer;
    _ = test_call;
    _ = test_dict;
    _ = test_float;
    _ = test_list;
    _ = test_long;
    _ = test_misc;
    _ = test_object;
    _ = test_tuple;
    _ = test_unicode;
}

// ============================================================================
// Integration Tests
// ============================================================================

test "capi_basic" {
    var ctx = TestContext.init(std.testing.allocator, "test_capi");
    try std.testing.expect(ctx.run());
}

test "capi_result" {
    const result = TestResult{ .tests_run = 1 };
    try std.testing.expect(result.wasSuccessful());
}

test "capi_suite" {
    var suite = TestSuite.init(std.testing.allocator, "test_capi_suite");

    suite.addResult(.{ .tests_run = 10, .failures = 0 });
    suite.addResult(.{ .tests_run = 5, .failures = 1 });

    try std.testing.expect(!suite.wasSuccessful());
    try std.testing.expectEqual(@as(usize, 15), suite.results.tests_run);
    try std.testing.expectEqual(@as(usize, 1), suite.results.failures);
}

test "capi_context_assertions" {
    var ctx = TestContext.init(std.testing.allocator, "test_assertions");

    try ctx.assertEqual(42, 42);
    try ctx.assertTrue(true);
    try ctx.assertFalse(false);

    try std.testing.expectEqual(@as(usize, 3), ctx.passed);
    try std.testing.expectEqual(@as(usize, 0), ctx.failed);
}

test "capi_context_skip" {
    var ctx = TestContext.init(std.testing.allocator, "test_skip");

    ctx.skip("not implemented");
    try std.testing.expectEqual(@as(usize, 1), ctx.skipped);
}
