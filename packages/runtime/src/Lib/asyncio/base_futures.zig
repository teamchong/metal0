//! asyncio.base_futures - Future base implementation and constants
//! Reference: cpython/Lib/asyncio/base_futures.py
//!
//! CPython exports: _PENDING, _CANCELLED, _FINISHED, isfuture

const std = @import("std");
const asyncio = @import("../asyncio.zig");

// Re-export FutureState from main asyncio module (DRY)
pub const FutureState = asyncio.FutureState;

// CPython-compatible state constants (numeric for compatibility)
pub const PENDING: u8 = 0;
pub const CANCELLED: u8 = 1;
pub const FINISHED: u8 = 2;

// Map to enum
pub fn stateFromInt(value: u8) FutureState {
    return switch (value) {
        PENDING => .pending,
        CANCELLED => .cancelled,
        FINISHED => .finished,
        else => .pending,
    };
}

pub fn stateToInt(state: FutureState) u8 {
    return switch (state) {
        .pending => PENDING,
        .cancelled => CANCELLED,
        .finished => FINISHED,
    };
}

/// Check if an object is a Future
/// CPython: isfuture(obj)
pub const isfuture = asyncio.isfuture;

// Tests
test "state constants" {
    try std.testing.expectEqual(@as(u8, 0), PENDING);
    try std.testing.expectEqual(@as(u8, 1), CANCELLED);
    try std.testing.expectEqual(@as(u8, 2), FINISHED);
}

test "state conversion" {
    try std.testing.expectEqual(FutureState.pending, stateFromInt(PENDING));
    try std.testing.expectEqual(FutureState.cancelled, stateFromInt(CANCELLED));
    try std.testing.expectEqual(FutureState.finished, stateFromInt(FINISHED));

    try std.testing.expectEqual(PENDING, stateToInt(.pending));
    try std.testing.expectEqual(CANCELLED, stateToInt(.cancelled));
    try std.testing.expectEqual(FINISHED, stateToInt(.finished));
}
