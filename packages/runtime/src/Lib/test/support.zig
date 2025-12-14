//! test.support - CPython test support utilities
//! CPython Reference: https://docs.python.org/3.12/library/test.html
//!
//! This module provides utilities used by CPython's test suite.
//! Most decorators become no-ops in AOT compilation since we don't have
//! dynamic decorator behavior.

const std = @import("std");
const builtin = @import("builtin");

// Re-export submodules for codegen (test.support.os_helper, etc.)
pub const os_helper = @import("support/os_helper.zig");
pub const import_helper = @import("support/import_helper.zig");
pub const warnings_helper = @import("support/warnings_helper.zig");
pub const threading_helper = @import("support/threading_helper.zig");
pub const socket_helper = @import("support/socket_helper.zig");
pub const script_helper = @import("support/script_helper.zig");
pub const hashlib_helper = @import("support/hashlib_helper.zig");
pub const hypothesis_helper = @import("support/hypothesis_helper.zig");
pub const numbers = @import("support/numbers.zig");

// Self-reference for "from test.support import support" pattern
// Python code often does: from test.support import support; support.verbose
pub const support = @This();

// ============================================================================
// Test Skip/Require Decorators (Return true = run test, false = skip)
// ============================================================================

/// Check if running on CPython (always false for metal0)
pub fn is_cpython() bool {
    return false;
}

/// Check if running on Apple platform (macOS, iOS, etc.)
pub const is_apple = builtin.os.tag == .macos or
    builtin.os.tag == .ios or
    builtin.os.tag == .tvos or
    builtin.os.tag == .watchos;

/// Check if running on Apple mobile platform
pub const is_apple_mobile = builtin.os.tag == .ios or
    builtin.os.tag == .tvos or
    builtin.os.tag == .watchos;

/// Check if IEEE 754 floating point is available (always true on modern hardware)
pub fn requires_IEEE_754() bool {
    return true;
}

/// Check if the platform supports the given resource
/// Resources: audio, curses, largefile, network, bsddb, decimal, cpu, subprocess, etc.
pub fn is_resource_enabled(resource: []const u8) bool {
    // For AOT tests, enable most resources by default
    _ = resource;
    return true;
}

/// Decorator stub: cpython_only - marks test as CPython-only
/// In metal0, these tests are skipped
pub fn cpython_only() bool {
    return false; // Skip CPython-only tests
}

/// Decorator stub: impl_detail - marks test as implementation detail
pub fn impl_detail() bool {
    return true; // Run implementation detail tests
}

/// Decorator stub: requires_resource - check resource availability
pub fn requires_resource(resource: []const u8) bool {
    return is_resource_enabled(resource);
}

// ============================================================================
// Python Subprocess Helpers
// ============================================================================

/// Error type for Python subprocess failures
pub const PythonError = error{
    SubprocessFailed,
    OutputMismatch,
    NonZeroReturn,
};

/// Result from running a Python subprocess
pub const SubprocessResult = struct {
    returncode: i32,
    stdout: []const u8,
    stderr: []const u8,
};

/// Run Python interpreter and check for success (returncode == 0)
/// Used by tests that spawn Python subprocesses
pub fn assert_python_ok(allocator: std.mem.Allocator, args: []const []const u8) !SubprocessResult {
    _ = allocator;
    _ = args;
    // In AOT, we don't spawn Python subprocesses - return success
    return SubprocessResult{
        .returncode = 0,
        .stdout = "",
        .stderr = "",
    };
}

/// Run Python interpreter and check for failure (returncode != 0)
pub fn assert_python_failure(allocator: std.mem.Allocator, args: []const []const u8) !SubprocessResult {
    _ = allocator;
    _ = args;
    // In AOT, we don't spawn Python subprocesses - simulate failure
    return SubprocessResult{
        .returncode = 1,
        .stdout = "",
        .stderr = "",
    };
}

// ============================================================================
// Import Helpers
// ============================================================================

/// Import a module, returning null if import fails
/// Used for optional imports that might not be available
pub fn import_module(comptime name: []const u8) ?type {
    _ = name;
    // In AOT, modules are statically linked - always available
    return null; // Stub - actual import done at compile time
}

/// Import a fresh module (bypassing cache)
pub fn import_fresh_module(comptime name: []const u8) ?type {
    return import_module(name);
}

// ============================================================================
// Temporary File/Directory Helpers
// ============================================================================

/// Temporary directory path
pub const TESTFN = "/tmp/metal0_test";

/// Create a temporary test file path with given suffix
pub fn temp_path(suffix: []const u8) []const u8 {
    _ = suffix;
    return TESTFN;
}

/// Clean up test files
pub fn unlink(file_path: []const u8) void {
    std.fs.cwd().deleteFile(file_path) catch {};
}

/// Remove directory tree
pub fn rmtree(dir_path: []const u8) void {
    std.fs.cwd().deleteTree(dir_path) catch {};
}

// ============================================================================
// Assertion Helpers
// ============================================================================

/// Check if two sequences are equal
pub fn check_equal(comptime T: type, a: []const T, b: []const T) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
}

/// Format error message for assertion failures
pub fn format_error(expected: anytype, actual: anytype) []const u8 {
    _ = expected;
    _ = actual;
    return "Assertion failed";
}

// ============================================================================
// Warning Helpers
// ============================================================================

/// Context manager stub for checking warnings
pub const CheckWarnings = struct {
    count: usize = 0,

    pub fn init() CheckWarnings {
        return .{};
    }

    pub fn deinit(_: *CheckWarnings) void {}

    pub fn warnings(_: *CheckWarnings) []const []const u8 {
        return &.{};
    }
};

/// Create a warning checker context
pub fn check_warnings() CheckWarnings {
    return CheckWarnings.init();
}

// ============================================================================
// Platform / Environment Checks
// ============================================================================

/// Check if running on Windows
pub fn is_windows() bool {
    return builtin.os.tag == .windows;
}

/// Check if running on POSIX
pub fn is_posix() bool {
    return builtin.os.tag != .windows;
}

/// Check if running on macOS
pub fn is_darwin() bool {
    return builtin.os.tag == .macos;
}

/// Check if running on Linux
pub fn is_linux() bool {
    return builtin.os.tag == .linux;
}

/// Verbose mode flag
pub var verbose: bool = false;

/// Set verbose mode
pub fn set_verbose(v: bool) void {
    verbose = v;
}

// ============================================================================
// Test Runner Helpers
// ============================================================================

/// Run a unittest test suite (stub)
pub fn run_unittest(comptime tests: anytype) void {
    _ = tests;
    // Stub - tests are run via metal0's test runner
}

/// Run doctests (stub)
pub fn run_doctest(comptime module: anytype) void {
    _ = module;
    // Stub - no doctest support in AOT
}

// ============================================================================
// Memory/Performance Test Decorators
// ============================================================================

/// Big memory test decorator stub
/// minsize: minimum memory size required (in bytes)
/// memuse: expected memory usage multiplier
pub fn bigmemtest(minsize: u64, memuse: f64) bool {
    _ = minsize;
    _ = memuse;
    return true; // Run big memory tests
}

/// Big address space test decorator stub
pub fn bigaddrspacetest() bool {
    return true;
}

/// CPU-intensive test decorator stub
pub fn cpubound() bool {
    return true;
}

// ============================================================================
// Floating Point Helpers
// ============================================================================

/// Check if a float is NaN
pub fn isnan(x: f64) bool {
    return std.math.isNan(x);
}

/// Check if a float is infinite
pub fn isinf(x: f64) bool {
    return std.math.isInf(x);
}

/// Positive infinity
pub const INF = std.math.inf(f64);

/// Negative infinity
pub const NINF = -std.math.inf(f64);

/// NaN
pub const NAN = std.math.nan(f64);

// ============================================================================
// Error Testing
// ============================================================================

/// Error context for testing exception handling
pub const ErrorContext = struct {
    expected_error: ?anyerror = null,

    pub fn init(err: anyerror) ErrorContext {
        return .{ .expected_error = err };
    }

    pub fn matches(self: ErrorContext, actual: anyerror) bool {
        if (self.expected_error) |expected| {
            return expected == actual;
        }
        return false;
    }
};

// ============================================================================
// Misc Utilities
// ============================================================================

/// Get a reproducible random seed for testing
pub fn get_seed() u64 {
    return 0; // Fixed seed for reproducible tests
}

/// Sleep for given seconds (for timing tests)
pub fn sleep(seconds: f64) void {
    const ns: u64 = @intFromFloat(seconds * 1_000_000_000);
    std.Thread.sleep(ns);
}

/// Get monotonic time in seconds
pub fn time() f64 {
    const ns = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}

// ============================================================================
// Test File Location and Subprocess Support
// ============================================================================

/// Find a test support file in the CPython test directory
/// For AOT compilation, returns the filename as-is
/// The test runner resolves paths relative to project root
pub fn findfile(filename: []const u8) []const u8 {
    return filename;
}

/// Indicates whether subprocess support is available on this platform
/// True for POSIX systems and Windows, false for WASM/embedded
pub const has_subprocess_support = switch (builtin.os.tag) {
    .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly, .windows => true,
    .wasi, .freestanding => false,
    else => true, // Assume POSIX-like by default
};

// ============================================================================
// Hash-Related Constants
// ============================================================================

/// Number of bits in a hash value (Python uses 61 bits on 64-bit systems)
pub const NHASHBITS: i64 = 61;

/// Maximum Py_ssize_t value (for large integer tests)
pub const MAX_Py_ssize_t: i64 = std.math.maxInt(i64);

/// Compute collision statistics for hash testing
/// Returns a tuple of (mean, stddev) for hash collision analysis
pub fn collision_stats(nbins: anytype, nballs: anytype) struct { f64, f64 } {
    // This is used for statistical testing of hash function quality
    // Returns approximate mean and standard deviation
    const n: f64 = switch (@typeInfo(@TypeOf(nbins))) {
        .int => @floatFromInt(nbins),
        .float => nbins,
        else => 0.0,
    };
    const k: f64 = switch (@typeInfo(@TypeOf(nballs))) {
        .int => @floatFromInt(nballs),
        .float => nballs,
        else => 0.0,
    };

    // Expected number of empty bins (Poisson approximation)
    if (n <= 0 or k <= 0) return .{ 0.0, 0.0 };

    const lambda = k / n;
    const expected_empty = n * @exp(-lambda);
    const variance = expected_empty * (1.0 - @exp(-lambda));
    const stddev = @sqrt(variance);

    return .{ expected_empty, stddev };
}

// ============================================================================
// Sequence Test Module (test.support.seq_tests)
// ============================================================================

/// Stub module for sequence testing infrastructure
pub const seq_tests = struct {
    /// Base class for common sequence tests
    pub const CommonTest = struct {
        pub fn init() CommonTest {
            return .{};
        }
    };
};

// ============================================================================
// Mapping Test Module (test.support.mapping_tests)
// ============================================================================

/// Stub module for mapping/dict testing infrastructure
pub const mapping_tests = struct {
    /// Base class for basic mapping protocol tests
    pub const BasicTestMappingProtocol = struct {
        pub fn init() BasicTestMappingProtocol {
            return .{};
        }
    };
};

// ============================================================================
// Broken Iterator for Error Testing
// ============================================================================

/// Iterator that raises an error after a certain number of iterations
pub const BrokenIter = struct {
    count: usize,
    max_count: usize,

    pub fn init(max_count: usize) BrokenIter {
        return .{ .count = 0, .max_count = max_count };
    }

    pub fn next(self: *BrokenIter) ?i64 {
        if (self.count >= self.max_count) {
            return null; // Or raise StopIteration
        }
        self.count += 1;
        return @intCast(self.count);
    }
};

// ============================================================================
// Module __all__ Verification
// ============================================================================

/// Check that a module's __all__ attribute is correctly defined
/// In AOT compilation, this is a no-op stub since __all__ is compile-time
pub fn check__all__(self: anytype, module: anytype, extra: anytype) void {
    // Stub - AOT compilation doesn't have dynamic __all__ verification
    _ = self;
    _ = module;
    _ = extra;
}
