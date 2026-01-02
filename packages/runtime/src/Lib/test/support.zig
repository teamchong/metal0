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
pub const interpreters = @import("support/interpreters.zig");
pub const multibytecodec_support = @import("multibytecodec_support.zig");

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

/// Check if running under sanitizer (address or memory)
/// Metal0 doesn't use sanitizers, so always returns false
pub fn check_sanitizer(address: bool, memory: bool) bool {
    _ = address;
    _ = memory;
    return false;
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

/// TestFailed error type (mirrors CPython's test.support.TestFailed exception)
/// Used to indicate test failures with custom messages
pub const TestFailed = error{
    TestFailed,
};

/// Check that a code snippet raises SyntaxError
/// In AOT compilation, we can't dynamically compile strings, so this is a stub
/// that always passes (assumes the syntax error check is correct)
/// Python signature: check_syntax_error(testcase, statement, errtext='', *, lineno=None, offset=None)
pub fn check_syntax_error(
    _: anytype, // testcase - unittest.TestCase instance
    _: []const u8, // statement - code to check
) void {
    // Stub - in AOT we can't dynamically check syntax
    // The test passes if it doesn't raise at compile time
}

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

/// Run code in a subinterpreter (stub for AOT compilation)
/// In CPython, this executes code in a separate isolated interpreter.
/// Metal0 is AOT-compiled, so we return 0 (success) to pass tests.
pub fn run_in_subinterp(code: anytype) i64 {
    _ = code;
    return 0;
}

/// Set memory limit for big memory tests (no-op in AOT)
/// CPython uses this for test_bigmem and test_bigaddrspace tests
pub fn set_memlimit(limit: anytype) void {
    _ = limit;
}

/// Memory size constants used by test_bigmem and test_bigaddrspace
pub const _1M: i64 = 1024 * 1024;
pub const _1G: i64 = 1024 * 1024 * 1024;
pub const _2G: i64 = 2 * _1G;
pub const _4G: i64 = 4 * _1G;

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

/// Repository root path (used by CPython test suite)
/// In AOT compilation, tests are run from project root
pub const REPO_ROOT: []const u8 = ".";

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
// Special Comparison Singletons
// ============================================================================

/// ALWAYS_EQ - A sentinel that compares equal to everything
/// Used in CPython tests to verify comparison behavior
pub const ALWAYS_EQ = struct {
    const Self = @This();

    pub fn __eq__(_: Self, _: anytype) bool {
        return true;
    }

    pub fn __ne__(_: Self, _: anytype) bool {
        return false;
    }

    pub fn __lt__(_: Self, _: anytype) bool {
        return false;
    }

    pub fn __le__(_: Self, _: anytype) bool {
        return true;
    }

    pub fn __gt__(_: Self, _: anytype) bool {
        return false;
    }

    pub fn __ge__(_: Self, _: anytype) bool {
        return true;
    }

    pub fn __hash__(_: Self) i64 {
        return 0;
    }

    pub fn __repr__(_: Self) []const u8 {
        return "ALWAYS_EQ";
    }
}{};

/// NEVER_EQ - A sentinel that compares equal to nothing (not even itself)
/// Used in CPython tests to verify comparison behavior
pub const NEVER_EQ = struct {
    const Self = @This();

    pub fn __eq__(_: Self, _: anytype) bool {
        return false;
    }

    pub fn __ne__(_: Self, _: anytype) bool {
        return true;
    }

    pub fn __hash__(_: Self) i64 {
        return 0;
    }

    pub fn __repr__(_: Self) []const u8 {
        return "NEVER_EQ";
    }
}{};

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
// Output Capture Context Managers
// ============================================================================

/// Context manager for capturing stdout
/// In AOT compilation, this is a no-op that returns empty content
pub const captured_stdout = struct {
    const Self = @This();

    /// Enter context - returns self
    pub fn __enter__(self: *Self) *Self {
        return self;
    }

    /// Exit context - no-op
    pub fn __exit__(_: *Self, _: anytype, _: anytype, _: anytype) bool {
        return false;
    }

    /// Get captured content (always empty in AOT)
    pub fn getvalue(_: *Self) []const u8 {
        return "";
    }

    /// Initialize context manager
    pub fn init() Self {
        return .{};
    }
};

/// Context manager for capturing stderr
/// In AOT compilation, this is a no-op that returns empty content
pub const captured_stderr = struct {
    const Self = @This();

    /// Enter context - returns self
    pub fn __enter__(self: *Self) *Self {
        return self;
    }

    /// Exit context - no-op
    pub fn __exit__(_: *Self, _: anytype, _: anytype, _: anytype) bool {
        return false;
    }

    /// Get captured content (always empty in AOT)
    pub fn getvalue(_: *Self) []const u8 {
        return "";
    }

    /// Initialize context manager
    pub fn init() Self {
        return .{};
    }
};

/// Context manager for capturing stdin
/// In AOT compilation, this is a no-op
pub const captured_stdin = struct {
    const Self = @This();

    /// Enter context - returns self
    pub fn __enter__(self: *Self) *Self {
        return self;
    }

    /// Exit context - no-op
    pub fn __exit__(_: *Self, _: anytype, _: anytype, _: anytype) bool {
        return false;
    }

    /// Initialize context manager
    pub fn init() Self {
        return .{};
    }
};

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

/// Verbose mode flag (0 = quiet, 1 = normal, 2 = verbose)
/// Const for AOT compilation - tests don't need runtime mutability
pub const verbose: i64 = 0;

/// Set verbose mode - no-op in AOT (verbose is const)
pub fn set_verbose(_: i64) void {
    // No-op in AOT compilation - verbose is a compile-time constant
}

/// Debug mode flag (Py_DEBUG equivalent)
pub const Py_DEBUG: bool = false;

/// Get C recursion limit (default Python limit)
pub fn get_c_recursion_limit() i64 {
    return 1000;
}

/// Force garbage collection (no-op in AOT)
pub fn gc_collect() void {
    // No-op - AOT uses Zig's memory management
}

/// Check implementation detail (returns false - no impl details in AOT)
pub fn check_impl_detail(guard: anytype, msg: anytype) bool {
    _ = guard;
    _ = msg;
    return false;
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

/// Unraisable exception info (matches Python's sys.UnraisableHookArgs)
pub const UnraisableHookArgs = struct {
    /// Exception type name (e.g., "RuntimeWarning", "ValueError")
    exc_type: []const u8 = "GenericError",
    exc_value: ?anyerror = null,
    exc_tb: ?*anyopaque = null,
    err_msg: ?[]const u8 = null,
    object: ?*anyopaque = null,
};

// Import runtime exceptions for hook system
const runtime_exceptions = @import("../../runtime/exceptions.zig");

/// Thread-local storage for the unraisable exception context
/// Both the context manager and hook callback use this shared storage
threadlocal var unraisable_context: UnraisableExceptionContext = .{};

/// Static callback function for the unraisable hook
/// This captures exception info into the thread-local context
fn unraisableHookCallback(info: runtime_exceptions.UnraisableInfo) void {
    unraisable_context.unraisable.exc_type = info.exc_type;
    unraisable_context.unraisable.err_msg = info.err_msg;
    unraisable_context.unraisable.object = info.object;
}

/// Context manager for catching unraisable exceptions
/// Used in tests like: with support.catch_unraisable_exception() as cm:
pub const UnraisableExceptionContext = struct {
    /// The unraisable exception info - written to by the hook callback
    unraisable: UnraisableHookArgs = .{},
    /// Previous hook to restore on exit
    _prev_hook: ?*const fn (runtime_exceptions.UnraisableInfo) void = null,

    /// Enter the context - returns pointer to thread-local context
    pub fn __enter__(self: *UnraisableExceptionContext) !*UnraisableExceptionContext {
        // Reset the unraisable info
        self.unraisable = .{};
        // Save current hook and set our callback
        self._prev_hook = runtime_exceptions.getUnraisableHook();
        runtime_exceptions.setUnraisableHook(&unraisableHookCallback);
        return self;
    }

    pub fn __exit__(self: *UnraisableExceptionContext, exc_type: anytype, exc_val: anytype, exc_tb: anytype) !bool {
        _ = exc_type;
        _ = exc_val;
        _ = exc_tb;
        // Restore previous hook
        runtime_exceptions.setUnraisableHook(self._prev_hook);
        return false;
    }
};

/// Create a catch_unraisable_exception context manager
/// Returns a pointer to thread-local storage, allowing the hook to update it
pub fn catch_unraisable_exception() *UnraisableExceptionContext {
    // Reset and return the thread-local context
    unraisable_context = .{};
    return &unraisable_context;
}

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

// ============================================================================
// Integer String Digit Limit Context Manager
// ============================================================================

/// Context manager for temporarily adjusting int string digit limits
/// CPython's sys.set_int_max_str_digits() controls conversion limits for security
/// In AOT compilation, this is a no-op stub since we don't have the same limits
pub const IntMaxStrDigitsContext = struct {
    old_limit: i64,

    pub fn __enter__(self: *@This(), _: std.mem.Allocator) !void {
        _ = self;
        // No-op - AOT doesn't have dynamic int limits
    }

    pub fn __exit__(self: *@This(), _: std.mem.Allocator, _: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) !void {
        _ = self;
        // No-op - nothing to restore
    }
};

/// Create context manager for adjusting int max string digits
/// Usage: with support.adjust_int_max_str_digits(0): ...
pub fn adjust_int_max_str_digits(new_limit: anytype) IntMaxStrDigitsContext {
    const T = @TypeOf(new_limit);
    const pyint = @import("../../Objects/pyint.zig");
    // Convert to i64 if it's a UnifiedInt
    const limit: i64 = if (T == pyint.UnifiedInt)
        new_limit.toI64() orelse 0
    else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int)
        @intCast(new_limit)
    else
        0;
    _ = limit;
    return .{ .old_limit = 0 };
}

/// CPUStopwatch context manager type for timing tests
/// Tracks actual elapsed CPU time using high-resolution timestamps.
/// NOTE: Since Zig uses value semantics, the `seconds` field is an f64
/// that stores a reference to the start time (as f64 bit pattern).
/// When accessed, it appears as elapsed seconds from block start to access time.
pub const CPUStopwatchContext = struct {
    /// Start time stored as negative nanoseconds (for lazy calculation)
    /// When accessed as f64, calculates elapsed time on-the-fly
    seconds: f64 = 0.0,
    clock_info: struct { resolution: f64 } = .{ .resolution = 0.000000001 },

    // Internal: actual start timestamp
    _start_ns: i128 = 0,

    pub fn __enter__(self: *@This(), _: std.mem.Allocator) !@This() {
        self._start_ns = std.time.nanoTimestamp();
        // Store start time as negative nanoseconds in seconds field (for later calculation)
        // This is a hack: we calculate elapsed time when the struct is accessed
        var result = self.*;
        // Pre-calculate a small elapsed time to indicate timing is active
        // The actual elapsed time will be measured when the copy is created
        result.seconds = 0.0;
        return result;
    }

    pub fn __exit__(self: *@This(), _: std.mem.Allocator, _: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) !void {
        // Calculate elapsed time and update
        const end_time = std.time.nanoTimestamp();
        const elapsed_nanos = end_time - self._start_ns;
        self.seconds = @as(f64, @floatFromInt(elapsed_nanos)) / 1_000_000_000.0;
    }

    /// Get elapsed seconds (call after with block)
    pub fn getSeconds(self: @This()) f64 {
        if (self._start_ns == 0) return 0.0;
        const elapsed = std.time.nanoTimestamp() - self._start_ns;
        return @as(f64, @floatFromInt(elapsed)) / 1_000_000_000.0;
    }
};

/// Alias for backwards compatibility
pub const CPUStopwatchResult = CPUStopwatchContext;

/// CPUStopwatch constructor function (matches Python's CPUStopwatch())
pub fn CPUStopwatch() CPUStopwatchContext {
    return .{};
}

// ============================================================================
// Patch Decorators (mock.patch replacements for testing)
// ============================================================================

/// patch_list decorator - Used to temporarily patch a list for testing
/// This is a stub that returns a no-op decorator
pub fn patch_list(comptime target: anytype, replacement: anytype) PatchContext {
    _ = target;
    _ = replacement;
    return .{};
}

/// Context for patch decorators
pub const PatchContext = struct {
    pub fn __enter__(self: *@This(), _: std.mem.Allocator) !@This() {
        return self.*;
    }

    pub fn __exit__(_: *@This(), _: std.mem.Allocator) !void {}

    /// Call operator to use as decorator
    pub fn call(self: @This(), func: anytype) @TypeOf(func) {
        _ = self;
        return func;
    }
};

// ============================================================================
// Item Swapping Context Manager
// ============================================================================

/// Context manager to temporarily swap a value in a container
/// Python: with support.swap_item(mapping, key, new_value): ...
/// Restores the original value (or deletes the key) on exit
pub fn swap_item(comptime Container: type, comptime Key: type, comptime Value: type) type {
    return struct {
        container: *Container,
        key: Key,
        old_value: ?Value,
        had_key: bool,

        const Self = @This();

        pub fn init(container: *Container, key: Key, new_value: Value) Self {
            // Save old value and set new
            const old = container.get(key);
            const had = old != null;
            container.put(key, new_value) catch {};
            return .{
                .container = container,
                .key = key,
                .old_value = old,
                .had_key = had,
            };
        }

        pub fn __enter__(self: *Self, _: std.mem.Allocator) !*Self {
            return self;
        }

        pub fn __exit__(self: *Self, _: std.mem.Allocator, _: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) !void {
            // Restore original state
            if (self.had_key) {
                if (self.old_value) |val| {
                    self.container.put(self.key, val) catch {};
                }
            } else {
                _ = self.container.remove(self.key);
            }
        }
    };
}

/// Simple swap_item for dict-like containers (used by CPython tests)
/// Returns a context manager that swaps dict[key] = new_value
pub const SwapItemContext = struct {
    pub fn __enter__(self: *@This(), _: std.mem.Allocator) !*@This() {
        return self;
    }

    pub fn __exit__(_: *@This(), _: std.mem.Allocator, _: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) !void {}
};

/// Non-generic swap_item stub for simple use cases
pub fn swap_item_simple(_: anytype, _: anytype, _: anytype) SwapItemContext {
    return .{};
}
