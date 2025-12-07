//! Python 'test' module - Test support for Python stdlib
//!
//! Internal package containing tests and test support utilities
//! for the Python standard library.
//!
//! Mirrors: CPython Lib/test/

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const TestError = error{
    TestFailed,
    TestSkipped,
    ResourceDenied,
    SetupError,
    TeardownError,
    OutOfMemory,
};

// ============================================================================
// Test Support
// ============================================================================

/// Test result status
pub const Status = enum {
    passed,
    failed,
    skipped,
    error_status,
};

/// Individual test result
pub const TestResult = struct {
    name: []const u8,
    status: Status = .passed,
    message: ?[]const u8 = null,
    duration_ns: i64 = 0,
};

/// Test suite results
pub const SuiteResult = struct {
    name: []const u8,
    passed: u32 = 0,
    failed: u32 = 0,
    skipped: u32 = 0,
    errors: u32 = 0,
    total_duration_ns: i64 = 0,
};

// ============================================================================
// Test Resources
// ============================================================================

/// Resource types that may not be available
pub const Resource = enum {
    audio,
    cpu,
    curses,
    decimal,
    extralargefile,
    gui,
    largefile,
    network,
    subprocess,
    tzdata,
    urlfetch,
    walltime,
};

/// Check if a resource is available
pub fn isResourceEnabled(resource: Resource) bool {
    _ = resource;
    // In practice, would check environment/configuration
    return false;
}

/// Require a resource, skip test if not available
pub fn requiresResource(resource: Resource) !void {
    if (!isResourceEnabled(resource)) {
        return error.ResourceDenied;
    }
}

// ============================================================================
// Test Assertions
// ============================================================================

/// Assert that two values are equal
pub fn assertEqual(comptime T: type, expected: T, actual: T) !void {
    if (expected != actual) {
        return error.TestFailed;
    }
}

/// Assert that a value is true
pub fn assertTrue(value: bool) !void {
    if (!value) {
        return error.TestFailed;
    }
}

/// Assert that a value is false
pub fn assertFalse(value: bool) !void {
    if (value) {
        return error.TestFailed;
    }
}

/// Assert that a value is null
pub fn assertIsNone(value: anytype) !void {
    if (value != null) {
        return error.TestFailed;
    }
}

/// Assert that a value is not null
pub fn assertIsNotNone(value: anytype) !void {
    if (value == null) {
        return error.TestFailed;
    }
}

/// Assert that a slice contains a value
pub fn assertIn(comptime T: type, needle: T, haystack: []const T) !void {
    for (haystack) |item| {
        if (item == needle) return;
    }
    return error.TestFailed;
}

/// Assert that two slices are equal
pub fn assertSequenceEqual(comptime T: type, expected: []const T, actual: []const T) !void {
    if (expected.len != actual.len) return error.TestFailed;
    for (expected, actual) |e, a| {
        if (e != a) return error.TestFailed;
    }
}

// ============================================================================
// Test Utilities
// ============================================================================

/// Temporary directory for tests
pub fn createTempDir(allocator: std.mem.Allocator) ![]u8 {
    const random_bytes = blk: {
        var buf: [8]u8 = undefined;
        std.crypto.random.bytes(&buf);
        break :blk buf;
    };

    var hex_buf: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&hex_buf, "{x}", .{std.fmt.fmtSliceHexLower(&random_bytes)}) catch unreachable;

    const path = try std.fmt.allocPrint(allocator, "/tmp/python_test_{s}", .{hex_buf});
    std.fs.makeDirAbsolute(path) catch |err| {
        allocator.free(path);
        return err;
    };

    return path;
}

/// Clean up temporary directory
pub fn removeTempDir(allocator: std.mem.Allocator, path: []const u8) void {
    std.fs.deleteTreeAbsolute(path) catch {};
    allocator.free(path);
}

/// Get test data directory
pub fn getTestDataDir() []const u8 {
    return "Lib/test/data";
}

/// Skip test with message
pub fn skip(message: []const u8) TestError {
    _ = message;
    return error.TestSkipped;
}

// ============================================================================
// Test Decorators (metadata)
// ============================================================================

/// Test metadata
pub const TestMeta = struct {
    requires_gui: bool = false,
    requires_network: bool = false,
    requires_subprocess: bool = false,
    slow: bool = false,
    expected_failure: bool = false,
    skip_reason: ?[]const u8 = null,
};

// ============================================================================
// Module State
// ============================================================================

var verbose: bool = false;
var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    verbose = false;
    initialized = false;
}

/// Set verbose mode
pub fn setVerbose(v: bool) void {
    verbose = v;
}

/// Get verbose mode
pub fn isVerbose() bool {
    return verbose;
}

// ============================================================================
// Tests
// ============================================================================

test "Status enum" {
    try std.testing.expectEqual(Status.passed, Status.passed);
    try std.testing.expect(Status.failed != Status.passed);
}

test "assertEqual" {
    try assertEqual(i32, 42, 42);

    const err = assertEqual(i32, 1, 2);
    try std.testing.expectError(error.TestFailed, err);
}

test "assertTrue" {
    try assertTrue(true);
    try std.testing.expectError(error.TestFailed, assertTrue(false));
}

test "assertFalse" {
    try assertFalse(false);
    try std.testing.expectError(error.TestFailed, assertFalse(true));
}

test "assertIn" {
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    try assertIn(i32, 3, &arr);
    try std.testing.expectError(error.TestFailed, assertIn(i32, 10, &arr));
}

test "assertSequenceEqual" {
    const a = [_]i32{ 1, 2, 3 };
    const b = [_]i32{ 1, 2, 3 };
    const c = [_]i32{ 1, 2, 4 };

    try assertSequenceEqual(i32, &a, &b);
    try std.testing.expectError(error.TestFailed, assertSequenceEqual(i32, &a, &c));
}

test "isResourceEnabled" {
    // Resources disabled by default
    try std.testing.expect(!isResourceEnabled(.gui));
    try std.testing.expect(!isResourceEnabled(.network));
}

test "TestResult" {
    const result = TestResult{
        .name = "test_example",
        .status = .passed,
    };
    try std.testing.expectEqualStrings("test_example", result.name);
    try std.testing.expectEqual(Status.passed, result.status);
}

test "verbose" {
    try std.testing.expect(!isVerbose());
    setVerbose(true);
    try std.testing.expect(isVerbose());
    setVerbose(false);
}
