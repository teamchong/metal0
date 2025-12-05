/// metal0 unittest module - test framework
/// Re-exports all unittest functionality from submodules
pub const runner = @import("unittest/runner.zig");
pub const assertions_basic = @import("unittest/assertions_basic.zig");
pub const assertions_type = @import("unittest/assertions_type.zig");
pub const subtest = @import("unittest/subtest.zig");

// Re-export runner functions
pub const TestResult = runner.TestResult;
pub const initRunner = runner.initRunner;
pub const printResults = runner.printResults;
pub const deinitRunner = runner.deinitRunner;
pub const main = runner.main;
pub const finalize = runner.finalize;
pub const Mock = runner.Mock;
pub const MockValue = runner.MockValue;

// Re-export basic assertions
pub const assertEqual = assertions_basic.assertEqual;
pub const assertTrue = assertions_basic.assertTrue;
pub const assertFalse = assertions_basic.assertFalse;
pub const assertIsNone = assertions_basic.assertIsNone;
pub const assertGreater = assertions_basic.assertGreater;
pub const assertLess = assertions_basic.assertLess;
pub const assertGreaterEqual = assertions_basic.assertGreaterEqual;
pub const assertLessEqual = assertions_basic.assertLessEqual;
pub const assertNotEqual = assertions_basic.assertNotEqual;
pub const assertIs = assertions_basic.assertIs;
pub const assertIsNot = assertions_basic.assertIsNot;
pub const assertIsNotNone = assertions_basic.assertIsNotNone;
pub const assertIn = assertions_basic.assertIn;
pub const assertNotIn = assertions_basic.assertNotIn;
pub const assertAlmostEqual = assertions_basic.assertAlmostEqual;
pub const assertNotAlmostEqual = assertions_basic.assertNotAlmostEqual;
pub const assertFloatsAreIdentical = assertions_basic.assertFloatsAreIdentical;
pub const assertHasAttr = assertions_basic.assertHasAttr;
pub const assertNotHasAttr = assertions_basic.assertNotHasAttr;
pub const assertStartsWith = assertions_basic.assertStartsWith;
pub const assertEndsWith = assertions_basic.assertEndsWith;
pub const assertTypeIs = assertions_basic.assertTypeIs;
pub const assertTypeIsStr = assertions_basic.assertTypeIsStr;
pub const assertNotStartsWith = assertions_basic.assertNotStartsWith;

// Re-export type/container assertions
pub const assertCountEqual = assertions_type.assertCountEqual;
pub const assertRegex = assertions_type.assertRegex;
pub const assertNotRegex = assertions_type.assertNotRegex;
pub const assertIsInstance = assertions_type.assertIsInstance;
pub const assertNotIsInstance = assertions_type.assertNotIsInstance;
pub const assertRaises = assertions_type.assertRaises;
pub const assertDictEqual = assertions_type.assertDictEqual;
pub const assertListEqual = assertions_type.assertListEqual;
pub const assertSetEqual = assertions_type.assertSetEqual;
pub const assertTupleEqual = assertions_type.assertTupleEqual;
pub const assertSequenceEqual = assertions_type.assertSequenceEqual;
pub const assertMultiLineEqual = assertions_type.assertMultiLineEqual;
pub const assertRaisesRegex = assertions_type.assertRaisesRegex;
pub const assertWarns = assertions_type.assertWarns;
pub const assertWarnsRegex = assertions_type.assertWarnsRegex;
pub const assertLogs = assertions_type.assertLogs;
pub const assertNoLogs = assertions_type.assertNoLogs;
pub const assertIsSubclass = assertions_type.assertIsSubclass;
pub const assertNotIsSubclass = assertions_type.assertNotIsSubclass;

// Re-export subtest
pub const subTest = subtest.subTest;
pub const subTestInt = subtest.subTestInt;

/// Helper for assertRaises codegen - returns true if value is NOT an error
/// For error unions: returns true if no error, false if error
/// For non-error types: returns true (no error possible)
pub fn expectError(value: anytype) bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    if (info == .error_union) {
        // Error union - check if it's an error
        if (value) |_| {
            return true; // No error - test should fail
        } else |_| {
            return false; // Error raised - test passes
        }
    } else {
        // Not an error union - no error possible
        return true;
    }
}

/// Base TestCase class with setUp/tearDown stubs
/// Python classes call super().setUp() which becomes unittest.TestCase.setUp()
pub const TestCase = struct {
    pub fn setUp(_: *anyopaque) void {
        // Base setUp - no-op
    }
    pub fn tearDown(_: *anyopaque) void {
        // Base tearDown - no-op
    }
};

/// Context manager for unittest assertions (e.g., with self.assertRaises(...) as cm)
/// This provides access to the captured exception message via cm.exception
/// The exception message is stored in thread-local storage by the error-raising code
pub const ContextManager = struct {
    /// Exception info captured by the context manager
    /// When str(cm.exception) is called, it retrieves from thread-local storage
    pub const Exception = struct {
        /// Exception arguments (like args[0])
        args: [8][]const u8 = .{""} ** 8,

        /// Python __str__ - returns the exception message from thread-local storage
        pub fn __str__(_: *const @This(), _: std.mem.Allocator) ![]const u8 {
            return exceptions.getExceptionMessage();
        }

        /// toStr for pyStr compatibility
        pub fn toStr(_: @This(), _: std.mem.Allocator) []const u8 {
            return exceptions.getExceptionMessage();
        }
    };

    exception: Exception = .{},

    /// Context manager __enter__ - returns self
    pub fn __enter__(self: *@This(), _: anytype) !*@This() {
        return self;
    }

    /// Context manager __exit__ - returns null/false to propagate exception
    pub fn __exit__(self: *@This(), _: anytype, _: anytype, _: anytype, _: anytype) !?bool {
        _ = self;
        return null;
    }
};

const exceptions = @import("runtime/exceptions.zig");

/// AssertRaises context manager type (returned by assertRaises/assertRaisesRegex)
pub const AssertRaisesContext = ContextManager;

/// AssertWarns context manager type (returned by assertWarns/assertWarnsRegex)
pub const AssertWarnsContext = ContextManager;

/// AssertLogs context manager type (returned by assertLogs/assertNoLogs)
pub const AssertLogsContext = ContextManager;

/// SkipTest exception - raised to skip a test
/// In Python: raise unittest.SkipTest("reason")
pub fn SkipTest(_: anytype, message: []const u8) error{SkipTest}!void {
    std.debug.print("Test skipped: {s}\n", .{message});
    return error.SkipTest;
}

const std = @import("std");

// Tests
test "assertEqual: integers" {
    assertEqual(@as(i64, 2 + 2), @as(i64, 4));
}

test "assertEqual: strings" {
    assertEqual("hello", "hello");
}

test "assertTrue" {
    assertTrue(true);
    assertTrue(1 == 1);
}

test "assertFalse" {
    assertFalse(false);
    assertFalse(1 == 2);
}
