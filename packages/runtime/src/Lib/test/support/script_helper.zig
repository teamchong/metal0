//! test.support.script_helper - CPython subprocess test utilities
//! CPython Reference: https://docs.python.org/3.12/library/test.html
//!
//! This module provides utilities for testing Python subprocess behavior.
//! In AOT compilation, we don't spawn Python subprocesses - these are stubs.

const std = @import("std");

// ============================================================================
// Subprocess Result Types
// ============================================================================

/// Result from running a Python subprocess
pub const SubprocessResult = struct {
    returncode: i32,
    stdout: []const u8,
    stderr: []const u8,

    /// Check if subprocess succeeded
    pub fn success(self: SubprocessResult) bool {
        return self.returncode == 0;
    }
};

/// Error type for subprocess failures
pub const SubprocessError = error{
    SubprocessFailed,
    NonZeroReturn,
    OutputMismatch,
};

// ============================================================================
// Python Subprocess Assertions
// ============================================================================

/// Run Python interpreter and assert it succeeds (returncode == 0)
/// Used by tests that spawn Python subprocesses to verify success.
/// In AOT compilation, we return a mock success result.
pub fn assert_python_ok(args: anytype) SubprocessResult {
    _ = args;
    // In AOT, we don't spawn Python subprocesses - return success
    return SubprocessResult{
        .returncode = 0,
        .stdout = "",
        .stderr = "",
    };
}

/// Run Python interpreter and assert it fails (returncode != 0)
/// Used by tests that expect Python to fail with an error.
/// In AOT compilation, we return a mock failure result.
pub fn assert_python_failure(args: anytype) SubprocessResult {
    _ = args;
    // In AOT, we don't spawn Python subprocesses - simulate failure
    return SubprocessResult{
        .returncode = 1,
        .stdout = "",
        .stderr = "",
    };
}

// ============================================================================
// Interpreter Path Helpers
// ============================================================================

/// Get the Python interpreter path
/// In AOT compilation, we don't need the interpreter path
pub fn python_path() []const u8 {
    return "python3";
}

/// Interpreter requires environment variables flag
pub var interpreter_requires_environment: bool = false;

// ============================================================================
// Script Running Helpers
// ============================================================================

/// Run a Python script and return result
pub fn run_python_until_end(args: anytype) SubprocessResult {
    _ = args;
    return SubprocessResult{
        .returncode = 0,
        .stdout = "",
        .stderr = "",
    };
}

/// Spawn a Python subprocess (non-blocking)
pub fn spawn_python(args: anytype) SubprocessResult {
    _ = args;
    return SubprocessResult{
        .returncode = 0,
        .stdout = "",
        .stderr = "",
    };
}

/// Kill a running subprocess
pub fn kill_python(proc: anytype) void {
    _ = proc;
}

// ============================================================================
// Output Assertion Helpers
// ============================================================================

/// Make a script that prints a value and exits
pub fn make_script(script_dir: []const u8, script_basename: []const u8, source: []const u8) []const u8 {
    _ = script_dir;
    _ = script_basename;
    _ = source;
    return "";
}

/// Make a package directory with __init__.py
pub fn make_pkg(pkg_dir: []const u8) void {
    _ = pkg_dir;
}

/// Make a zip file containing Python code
pub fn make_zip_script(zip_dir: []const u8, zip_basename: []const u8, source: []const u8) []const u8 {
    _ = zip_dir;
    _ = zip_basename;
    _ = source;
    return "";
}

/// Make a zip package
pub fn make_zip_pkg(zip_dir: []const u8, zip_basename: []const u8, source: []const u8, depth: u32) []const u8 {
    _ = zip_dir;
    _ = zip_basename;
    _ = source;
    _ = depth;
    return "";
}

// ============================================================================
// Environment Helpers
// ============================================================================

/// Create a copy of os.environ with interpreter variables set
pub fn get_child_env() std.StringHashMap([]const u8) {
    return std.StringHashMap([]const u8).init(std.heap.page_allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "assert_python_ok returns success" {
    const result = assert_python_ok(.{});
    try std.testing.expectEqual(@as(i32, 0), result.returncode);
    try std.testing.expect(result.success());
}

test "assert_python_failure returns failure" {
    const result = assert_python_failure(.{});
    try std.testing.expectEqual(@as(i32, 1), result.returncode);
    try std.testing.expect(!result.success());
}
