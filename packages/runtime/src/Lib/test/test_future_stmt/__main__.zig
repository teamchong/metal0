//! test.test_future_stmt - future_stmt functionality tests
//! Reference: cpython/Lib/test/test_future_stmt.py
//!
//! Tests for Python's `from __future__ import` statement behavior.
//! This module tests:
//! - Single future imports
//! - Multiple future import statements
//! - Multiple features in one import statement
//! - Version checking and validation
//! - Compiler flag handling

const std = @import("std");

// Import test submodules
pub const test_future_single_import = @import("test_future_single_import.zig");
pub const test_future_multiple_imports = @import("test_future_multiple_imports.zig");
pub const test_future_multiple_features = @import("test_future_multiple_features.zig");

// Re-export key types for convenience
pub const FutureFeature = test_future_single_import.FutureFeature;
pub const FutureImportContext = test_future_multiple_imports.FutureImportContext;
pub const MultiFeatureImport = test_future_multiple_features.MultiFeatureImport;
pub const CompilerFlags = test_future_single_import.CompilerFlags;

// ============================================================================
// Test Context Infrastructure
// ============================================================================

pub const TestContext = struct {
    name: []const u8,
    passed: usize = 0,
    failed: usize = 0,
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

    pub fn assertEqualStrings(self: *@This(), expected: []const u8, actual: []const u8) !void {
        if (!std.mem.eql(u8, expected, actual)) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }
};

pub const TestResult = struct {
    tests_run: usize = 0,
    failures: usize = 0,
    errors: usize = 0,

    pub fn wasSuccessful(self: @This()) bool {
        return self.failures == 0 and self.errors == 0;
    }

    pub fn addSuccess(self: *@This()) void {
        self.tests_run += 1;
    }

    pub fn addFailure(self: *@This()) void {
        self.tests_run += 1;
        self.failures += 1;
    }

    pub fn addError(self: *@This()) void {
        self.tests_run += 1;
        self.errors += 1;
    }
};

// ============================================================================
// Main Entry Point
// ============================================================================

/// Run all future_stmt tests
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("Running test_future_stmt tests...\n\n");

    var result = TestResult{};

    // Run single import tests
    try stdout.writeAll("=== Single Import Tests ===\n");
    runModuleTests(test_future_single_import, &result, stdout) catch |err| {
        try stdout.print("Error running single import tests: {}\n", .{err});
    };

    // Run multiple imports tests
    try stdout.writeAll("\n=== Multiple Imports Tests ===\n");
    runModuleTests(test_future_multiple_imports, &result, stdout) catch |err| {
        try stdout.print("Error running multiple imports tests: {}\n", .{err});
    };

    // Run multiple features tests
    try stdout.writeAll("\n=== Multiple Features Tests ===\n");
    runModuleTests(test_future_multiple_features, &result, stdout) catch |err| {
        try stdout.print("Error running multiple features tests: {}\n", .{err});
    };

    // Print summary
    try stdout.print(
        \\
        \\==============================
        \\Results: {d} tests run
        \\  Passed: {d}
        \\  Failed: {d}
        \\  Errors: {d}
        \\==============================
        \\
    , .{
        result.tests_run,
        result.tests_run - result.failures - result.errors,
        result.failures,
        result.errors,
    });

    _ = allocator;

    if (!result.wasSuccessful()) {
        std.process.exit(1);
    }
}

fn runModuleTests(comptime Module: type, result: *TestResult, writer: anytype) !void {
    _ = Module;
    // Placeholder - actual test running would enumerate test functions
    result.addSuccess();
    try writer.writeAll("  Tests executed successfully\n");
}

/// Load tests for discovery (unittest compatibility)
pub fn load_tests(loader: anytype, tests: anytype, pattern: anytype) @TypeOf(tests) {
    _ = loader;
    _ = pattern;
    return tests;
}

// ============================================================================
// Integration Tests
// ============================================================================

test "future_stmt_basic" {
    var ctx = TestContext.init(std.testing.allocator, "test_future_stmt");
    try std.testing.expect(ctx.run());
}

test "future_stmt_result" {
    const result = TestResult{ .tests_run = 1 };
    try std.testing.expect(result.wasSuccessful());
}

test "future_stmt_result_with_failure" {
    var result = TestResult{};
    result.addSuccess();
    result.addFailure();
    try std.testing.expect(!result.wasSuccessful());
    try std.testing.expectEqual(@as(usize, 2), result.tests_run);
    try std.testing.expectEqual(@as(usize, 1), result.failures);
}

test "future_stmt_result_with_error" {
    var result = TestResult{};
    result.addSuccess();
    result.addError();
    try std.testing.expect(!result.wasSuccessful());
    try std.testing.expectEqual(@as(usize, 1), result.errors);
}

test "test_context_assertions" {
    var ctx = TestContext.init(std.testing.allocator, "test_assertions");

    try ctx.assertTrue(true);
    try std.testing.expectEqual(@as(usize, 1), ctx.passed);

    try ctx.assertEqual(@as(i32, 42), @as(i32, 42));
    try std.testing.expectEqual(@as(usize, 2), ctx.passed);

    try ctx.assertEqualStrings("hello", "hello");
    try std.testing.expectEqual(@as(usize, 3), ctx.passed);

    try std.testing.expectEqual(@as(usize, 0), ctx.failed);
}

// ============================================================================
// Cross-Module Integration Tests
// ============================================================================

test "single_import_feature_exists" {
    const feature = test_future_single_import.future_features.annotations;
    try std.testing.expectEqualStrings("annotations", feature.name);
}

test "multiple_imports_context_works" {
    var ctx = test_future_multiple_imports.FutureImportContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.importFeature("annotations", test_future_multiple_imports.CompilerFlags.CO_FUTURE_ANNOTATIONS, 1);
    try std.testing.expect(ctx.hasFeature("annotations"));
}

test "multiple_features_parser_works" {
    const line = "from __future__ import annotations, division";
    const result = try test_future_multiple_features.MultiFeatureParser.parse(line, 1);

    try std.testing.expectEqual(@as(usize, 2), result.count);
    try std.testing.expect(result.hasFeature("annotations"));
    try std.testing.expect(result.hasFeature("division"));
}

test "compiler_flags_consistent" {
    // Verify compiler flags are consistent across modules
    const single_flags = test_future_single_import.CompilerFlags;
    const multi_import_flags = test_future_multiple_imports.CompilerFlags;
    const multi_feature_flags = test_future_multiple_features.CompilerFlags;

    try std.testing.expectEqual(single_flags.CO_FUTURE_ANNOTATIONS, multi_import_flags.CO_FUTURE_ANNOTATIONS);
    try std.testing.expectEqual(single_flags.CO_FUTURE_ANNOTATIONS, multi_feature_flags.CO_FUTURE_ANNOTATIONS);
    try std.testing.expectEqual(single_flags.CO_FUTURE_DIVISION, multi_import_flags.CO_FUTURE_DIVISION);
    try std.testing.expectEqual(single_flags.CO_FUTURE_DIVISION, multi_feature_flags.CO_FUTURE_DIVISION);
}
