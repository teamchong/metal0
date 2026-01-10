//! asyncio.futures - Future class
//! Reference: cpython/Lib/asyncio/futures.py
//!
//! CPython __all__: ('Future', 'wrap_future', 'isfuture')

const std = @import("std");
const asyncio = @import("../asyncio.zig");
const exceptions = @import("exceptions.zig");

// Re-export Future type from main asyncio module (DRY)
pub const Future = asyncio.Future;
pub const FutureState = asyncio.FutureState;

// Re-export type checking function
pub const isfuture = asyncio.isfuture;

/// Wrap a concurrent.futures.Future or coroutine into asyncio.Future
/// CPython signature: wrap_future(future, *, loop=None)
pub fn wrapFuture(comptime T: type, allocator: std.mem.Allocator, value: T) !*Future(T) {
    const future = try Future(T).init(allocator);
    future.setResult(value);
    return future;
}

/// Alias for wrap_future - ensure we have a Future
/// CPython signature: ensure_future(coro_or_future, *, loop=None)
pub const ensureFuture = wrapFuture;

// Re-export exceptions for convenience
pub const CancelledError = exceptions.CancelledError;
pub const InvalidStateError = exceptions.InvalidStateError;

// Tests
test "Future create and resolve" {
    const allocator = std.testing.allocator;
    const IntFuture = Future(i64);
    const future = try IntFuture.init(allocator);
    defer future.deinit();

    try std.testing.expect(!future.done());
    future.setResult(42);
    try std.testing.expect(future.done());
    try std.testing.expectEqual(@as(i64, 42), try future.getResult());
}

test "Future cancel" {
    const allocator = std.testing.allocator;
    const IntFuture = Future(i64);
    const future = try IntFuture.init(allocator);
    defer future.deinit();

    try std.testing.expect(!future.cancelled());
    try std.testing.expect(future.cancel());
    try std.testing.expect(future.cancelled());
    try std.testing.expect(future.done());
}

test "isfuture" {
    const IntFuture = Future(i64);
    try std.testing.expect(isfuture(IntFuture));
    try std.testing.expect(!isfuture(i64));
}
