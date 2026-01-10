//! asyncio.exceptions - Exception types
//! Reference: cpython/Lib/asyncio/exceptions.py
//!
//! CPython __all__:
//!   ('BrokenBarrierError', 'CancelledError', 'InvalidStateError', 'TimeoutError',
//!    'IncompleteReadError', 'LimitOverrunError', 'SendfileNotAvailableError')

const std = @import("std");
const asyncio = @import("../asyncio.zig");

// Re-export error types from main asyncio module (DRY)
pub const CancelledError = asyncio.CancelledError;
pub const InvalidStateError = asyncio.InvalidStateError;
pub const TimeoutError = asyncio.TimeoutError;
pub const BrokenBarrierError = asyncio.BrokenBarrierError;
pub const SendfileNotAvailableError = asyncio.SendfileNotAvailableError;

/// IncompleteReadError - Incomplete read error
/// Raised when read() with n bytes requested returns fewer bytes before EOF
/// Attributes:
///   - partial: read bytes before end of stream was reached
///   - expected: total number of expected bytes (or null if unknown)
pub const IncompleteReadError = struct {
    partial: []const u8,
    expected: ?usize,

    pub fn init(partial: []const u8, expected: ?usize) IncompleteReadError {
        return .{ .partial = partial, .expected = expected };
    }
};

/// LimitOverrunError - Reached the buffer limit while looking for a separator
/// Attributes:
///   - consumed: total number of bytes to be consumed
pub const LimitOverrunError = struct {
    message: []const u8,
    consumed: usize,

    pub fn init(message: []const u8, consumed: usize) LimitOverrunError {
        return .{ .message = message, .consumed = consumed };
    }
};

// Tests
test "IncompleteReadError creation" {
    const err = IncompleteReadError.init("hello", 10);
    try std.testing.expectEqual(@as(usize, 5), err.partial.len);
    try std.testing.expectEqual(@as(?usize, 10), err.expected);
}

test "LimitOverrunError creation" {
    const err = LimitOverrunError.init("buffer exceeded", 100);
    try std.testing.expectEqual(@as(usize, 100), err.consumed);
}
