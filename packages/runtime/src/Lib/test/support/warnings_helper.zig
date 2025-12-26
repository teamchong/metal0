//! Python stdlib module: test.support.warnings_helper
//! Provides warning capture utilities for testing
const std = @import("std");

/// Context manager for checking warnings
/// In metal0, this is a no-op struct that implements Python's context manager protocol
pub const check_warnings = struct {
    /// Enter context - no-op
    pub fn __enter__(self: *@This()) *@This() {
        return self;
    }

    /// Exit context - no-op
    pub fn __exit__(self: *@This(), exc_type: anytype, exc_val: anytype, exc_tb: anytype) bool {
        _ = self;
        _ = exc_type;
        _ = exc_val;
        _ = exc_tb;
        return false;
    }

    /// Initialize context manager
    pub fn init() @This() {
        return .{};
    }
};
