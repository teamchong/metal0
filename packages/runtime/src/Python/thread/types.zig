/// types - Thread Types and Constants
/// Lock status, flags, and global constants for threading.

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Maximum timeout value in microseconds
pub const PY_TIMEOUT_MAX: i64 = std.math.maxInt(i64) / 1000;

/// Unset/infinite timeout marker
pub const UNSET_TIMEOUT: i64 = -1;

/// Default thread stack size (0 = use system default)
pub const DEFAULT_STACKSIZE: usize = 0;

// ============================================================================
// Lock Types
// ============================================================================

/// Lock acquisition status
pub const LockStatus = enum {
    acquired, // Lock was acquired
    failure, // Lock acquisition failed
    timeout, // Timed out waiting for lock
    interrupted, // Interrupted by signal
};

/// Lock flags
pub const LockFlags = packed struct(u8) {
    dont_detach: bool = false, // Don't detach on timeout
    fail_if_interrupted: bool = false, // Return on interrupt
    _padding: u6 = 0,
};

// ============================================================================
// Timeout Parsing
// ============================================================================

/// Parse timeout argument
pub fn parseTimeout(timeout_seconds: f64, blocking: bool) !i64 {
    if (!blocking and timeout_seconds >= 0) {
        return error.InvalidValue; // Can't specify timeout for non-blocking
    }

    if (timeout_seconds < 0) {
        return UNSET_TIMEOUT;
    }

    // Convert to microseconds
    const microseconds = @as(i64, @intFromFloat(timeout_seconds * 1_000_000));

    if (microseconds > PY_TIMEOUT_MAX) {
        return error.Overflow;
    }

    return microseconds;
}

// ============================================================================
// Stack Size
// ============================================================================

var thread_stacksize: usize = DEFAULT_STACKSIZE;

/// Get thread stack size
pub fn getStackSize() usize {
    return thread_stacksize;
}

/// Set thread stack size
pub fn setStackSize(size: usize) i32 {
    // Validate size
    if (size != 0 and size < 32768) {
        return -1; // Invalid size
    }

    thread_stacksize = size;
    return 0;
}

// ============================================================================
// Tests
// ============================================================================

test "timeout parsing" {
    // Blocking with timeout
    const timeout1 = try parseTimeout(1.5, true);
    try std.testing.expectEqual(@as(i64, 1500000), timeout1);

    // Blocking with no timeout
    const timeout2 = try parseTimeout(-1, true);
    try std.testing.expectEqual(UNSET_TIMEOUT, timeout2);

    // Non-blocking with negative should succeed
    const timeout3 = try parseTimeout(-1, false);
    try std.testing.expectEqual(UNSET_TIMEOUT, timeout3);
}

test "stack size" {
    try std.testing.expectEqual(DEFAULT_STACKSIZE, getStackSize());

    // Set valid size
    try std.testing.expectEqual(@as(i32, 0), setStackSize(1024 * 1024));
    try std.testing.expectEqual(@as(usize, 1024 * 1024), getStackSize());

    // Set invalid size
    try std.testing.expectEqual(@as(i32, -1), setStackSize(1000));

    // Reset
    _ = setStackSize(DEFAULT_STACKSIZE);
}
