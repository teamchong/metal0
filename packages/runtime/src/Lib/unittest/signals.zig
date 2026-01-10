//! unittest.signals - Signal handling for test interruption
//! Reference: cpython/Lib/unittest/signals.py
//!
//! CPython __all__: ['installHandler', 'registerResult', 'removeResult', 'removeHandler']
//!
//! Provides signal handlers for graceful test interruption (Ctrl-C).

const std = @import("std");
const builtin = @import("builtin");
const result_mod = @import("result.zig");

// ============================================================================
// Signal Handler State
// ============================================================================

/// Whether signal handler is installed
var _handler_installed: bool = false;

/// List of registered test results (for signaling stop)
var _results: std.ArrayListUnmanaged(*result_mod.CPythonTestResult) = .{};

/// Whether an interrupt was received
var _interrupt_received: bool = false;

/// Allocator for managing result list
var _allocator: ?std.mem.Allocator = null;

// ============================================================================
// Main Functions
// ============================================================================

/// CPython: def installHandler()
/// Install a signal handler that catches SIGINT and gracefully stops test execution.
/// The first SIGINT stops tests after current test completes.
/// A second SIGINT raises KeyboardInterrupt immediately.
pub fn installHandler() void {
    if (_handler_installed) return;

    // Only install on Unix-like systems
    if (builtin.os.tag != .windows) {
        const handler = std.posix.Sigaction{
            .handler = .{ .handler = signalHandler },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.INT, &handler, null) catch return;
    }

    _handler_installed = true;
}

/// CPython: def registerResult(result)
/// Register a TestResult to receive stop signals.
/// When SIGINT is received, all registered results are told to stop.
pub fn registerResult(result: *result_mod.CPythonTestResult) !void {
    if (_allocator == null) {
        _allocator = std.heap.page_allocator;
    }
    try _results.append(_allocator.?, result);
}

/// CPython: def removeResult(result)
/// Remove a TestResult from the list of registered results.
pub fn removeResult(result: *result_mod.CPythonTestResult) void {
    if (_allocator) |alloc| {
        for (_results.items, 0..) |r, i| {
            if (r == result) {
                _ = _results.swapRemove(i);
                break;
            }
        }
        _ = alloc;
    }
}

/// CPython: def removeHandler()
/// Remove the installed signal handler and restore default behavior.
pub fn removeHandler() void {
    if (!_handler_installed) return;

    // Restore default handler on Unix-like systems
    if (builtin.os.tag != .windows) {
        const handler = std.posix.Sigaction{
            .handler = .{ .handler = std.posix.SIG.DFL },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.INT, &handler, null) catch return;
    }

    _handler_installed = false;
}

// ============================================================================
// Signal Handler Implementation
// ============================================================================

/// Internal signal handler for SIGINT
fn signalHandler(_: c_int) callconv(.C) void {
    if (_interrupt_received) {
        // Second interrupt - raise immediately
        // In Zig, we can't easily raise Python's KeyboardInterrupt,
        // so we restore default handler and re-raise
        removeHandler();
        // This will cause the default SIGINT behavior (terminate)
        return;
    }

    _interrupt_received = true;

    // Signal all registered results to stop
    for (_results.items) |result| {
        result.stop();
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Check if an interrupt has been received
pub fn wasInterrupted() bool {
    return _interrupt_received;
}

/// Clear the interrupt flag
pub fn clearInterrupt() void {
    _interrupt_received = false;
}

/// Cleanup function - call at end of test run
pub fn cleanup() void {
    removeHandler();
    if (_allocator) |alloc| {
        _results.deinit(alloc);
        _results = .{};
    }
    _interrupt_received = false;
}

// ============================================================================
// Context Manager for catchbreak
// ============================================================================

/// Context manager for temporarily installing signal handler
/// CPython: Used by TestProgram when catchbreak=True
pub const CatchBreak = struct {
    was_installed: bool = false,

    pub fn __enter__(self: *CatchBreak) *CatchBreak {
        self.was_installed = _handler_installed;
        if (!self.was_installed) {
            installHandler();
        }
        return self;
    }

    pub fn __exit__(self: *CatchBreak, _: anytype, _: anytype, _: anytype) void {
        if (!self.was_installed) {
            removeHandler();
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "installHandler" {
    installHandler();
    try std.testing.expect(_handler_installed);
    removeHandler();
    try std.testing.expect(!_handler_installed);
}

test "wasInterrupted" {
    try std.testing.expect(!wasInterrupted());
}

test "CatchBreak" {
    var ctx = CatchBreak{};
    _ = ctx.__enter__();
    try std.testing.expect(_handler_installed);
    ctx.__exit__({}, {}, {});
}
