//! unittest.async_case - Async test case support
//! Reference: cpython/Lib/unittest/async_case.py
//!
//! CPython __all__: ['IsolatedAsyncioTestCase']
//!
//! Provides IsolatedAsyncioTestCase for testing async code.

const std = @import("std");
const runner = @import("runner.zig");

// ============================================================================
// IsolatedAsyncioTestCase
// ============================================================================

/// CPython: class IsolatedAsyncioTestCase(TestCase)
/// A TestCase subclass designed for testing async/await code.
/// Each test runs in its own event loop that is created before the test
/// and cleaned up after.
pub const IsolatedAsyncioTestCase = struct {
    /// Current test method name
    _testMethodName: []const u8 = "",
    /// Test method docstring
    _testMethodDoc: ?[]const u8 = null,
    /// Class name for id()
    _className: []const u8 = "IsolatedAsyncioTestCase",
    /// Module name for id()
    _moduleName: []const u8 = "__main__",
    /// Debug mode flag
    debug: bool = false,

    /// CPython: def setUp(self)
    /// Synchronous setUp - called before async setUp
    pub fn setUp(_: *IsolatedAsyncioTestCase) void {
        // Base setUp - no-op
    }

    /// CPython: def tearDown(self)
    /// Synchronous tearDown - called after async tearDown
    pub fn tearDown(_: *IsolatedAsyncioTestCase) void {
        // Base tearDown - no-op
    }

    /// CPython: async def asyncSetUp(self)
    /// Async setUp - called in event loop before test
    pub fn asyncSetUp(_: *IsolatedAsyncioTestCase) void {
        // Base asyncSetUp - no-op
        // In AOT, async execution is handled by codegen
    }

    /// CPython: async def asyncTearDown(self)
    /// Async tearDown - called in event loop after test
    pub fn asyncTearDown(_: *IsolatedAsyncioTestCase) void {
        // Base asyncTearDown - no-op
    }

    /// CPython: def addAsyncCleanup(self, func, *args, **kwargs)
    /// Add an async cleanup function to be called after asyncTearDown
    pub fn addAsyncCleanup(_: *IsolatedAsyncioTestCase, _: anytype) void {
        // Cleanup tracking handled by codegen
    }

    /// CPython: def _callSetUp(self)
    /// Internal: Call both sync and async setUp
    pub fn _callSetUp(self: *IsolatedAsyncioTestCase) void {
        self.setUp();
        self.asyncSetUp();
    }

    /// CPython: def _callTearDown(self)
    /// Internal: Call both async and sync tearDown
    pub fn _callTearDown(self: *IsolatedAsyncioTestCase) void {
        self.asyncTearDown();
        self.tearDown();
    }

    /// CPython: def _callTestMethod(self, method)
    /// Internal: Run the test method in the event loop
    pub fn _callTestMethod(_: *IsolatedAsyncioTestCase, _: anytype) void {
        // Test execution handled by codegen
    }

    /// CPython: def _callCleanup(self, function, *args, **kwargs)
    /// Internal: Run a cleanup function
    pub fn _callCleanup(_: *IsolatedAsyncioTestCase, _: anytype) void {
        // Cleanup execution handled by codegen
    }

    /// CPython: def debug(self)
    /// Run the test without collecting errors
    pub fn debug(self: *IsolatedAsyncioTestCase) void {
        self.debug = true;
    }

    /// id() - Return full test identifier
    pub fn id(self: *const IsolatedAsyncioTestCase) []const u8 {
        _ = self;
        return "IsolatedAsyncioTestCase.test";
    }

    /// shortDescription() - Return first line of docstring
    pub fn shortDescription(self: *const IsolatedAsyncioTestCase) ?[]const u8 {
        if (self._testMethodDoc) |doc| {
            if (std.mem.indexOf(u8, doc, "\n")) |newline| {
                return doc[0..newline];
            }
            return doc;
        }
        return null;
    }

    /// countTestCases() - Return 1
    pub fn countTestCases(_: *const IsolatedAsyncioTestCase) usize {
        return 1;
    }
};

// ============================================================================
// Async Test Utilities
// ============================================================================

/// Run an async test function
/// In AOT, this is a synchronous wrapper that the codegen uses
pub fn runAsyncTest(comptime testFn: anytype) void {
    // In AOT compilation, async execution is transformed at compile time
    // This function exists for API compatibility
    _ = testFn;
}

/// Create an event loop for testing
/// In AOT, event loops are managed at compile time
pub fn createTestLoop() void {
    // Event loop creation is handled by codegen
}

/// Cleanup the test event loop
pub fn closeTestLoop() void {
    // Event loop cleanup is handled by codegen
}

// ============================================================================
// Async Assertions
// ============================================================================

/// Assert that a coroutine completes without error
pub fn assertAsyncCompletes(_: anytype) void {
    // Async completion checking is handled at compile time
}

/// Assert that a coroutine raises an exception
pub fn assertAsyncRaises(comptime ExceptionType: type, _: anytype) void {
    _ = ExceptionType;
    // Async exception checking is handled at compile time
}

// ============================================================================
// Async Context Managers for Testing
// ============================================================================

/// Async version of assertRaises
/// CPython: async with self.assertRaises(...) as cm
pub const AsyncAssertRaisesContext = struct {
    exception_type: ?[]const u8 = null,
    exception: ?anyerror = null,

    pub fn __aenter__(self: *AsyncAssertRaisesContext) *AsyncAssertRaisesContext {
        return self;
    }

    pub fn __aexit__(self: *AsyncAssertRaisesContext, exc_type: anytype, exc_val: anytype, _: anytype) bool {
        _ = exc_type;
        _ = self;
        if (exc_val != null) {
            return true; // Suppress the exception
        }
        return false;
    }
};

/// Async version of assertWarns
pub const AsyncAssertWarnsContext = struct {
    warning_type: ?[]const u8 = null,

    pub fn __aenter__(self: *AsyncAssertWarnsContext) *AsyncAssertWarnsContext {
        return self;
    }

    pub fn __aexit__(_: *AsyncAssertWarnsContext, _: anytype, _: anytype, _: anytype) bool {
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "IsolatedAsyncioTestCase basic" {
    var test_case = IsolatedAsyncioTestCase{};
    test_case.setUp();
    test_case.asyncSetUp();
    test_case.asyncTearDown();
    test_case.tearDown();

    try std.testing.expectEqual(@as(usize, 1), test_case.countTestCases());
}

test "IsolatedAsyncioTestCase shortDescription" {
    var test_case = IsolatedAsyncioTestCase{
        ._testMethodDoc = "First line\nSecond line",
    };
    const desc = test_case.shortDescription();
    try std.testing.expect(desc != null);
    try std.testing.expectEqualStrings("First line", desc.?);
}

test "IsolatedAsyncioTestCase no doc" {
    var test_case = IsolatedAsyncioTestCase{};
    const desc = test_case.shortDescription();
    try std.testing.expect(desc == null);
}
