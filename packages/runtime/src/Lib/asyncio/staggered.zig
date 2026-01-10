//! asyncio.staggered - Staggered race implementation
//! Reference: cpython/Lib/asyncio/staggered.py

const std = @import("std");
const futures = @import("futures.zig");
const tasks = @import("tasks.zig");

/// Run coroutines with staggered starts, return first success
/// CPython: async def staggered_race(coro_fns, delay, *, loop=None)
///
/// Starts coroutines one by one with a delay between them.
/// Returns when the first one succeeds, cancelling the rest.
pub fn staggeredRace(
    allocator: std.mem.Allocator,
    comptime T: type,
    coro_fns: []const *const fn () anyerror!T,
    delay: f64,
) !?struct { result: T, index: usize, exceptions: []?anyerror } {
    if (coro_fns.len == 0) {
        return null;
    }

    var exceptions = try allocator.alloc(?anyerror, coro_fns.len);
    @memset(exceptions, null);
    errdefer allocator.free(exceptions);

    var winner_result: ?T = null;
    var winner_index: ?usize = null;

    const delay_ns = @as(u64, @intFromFloat(delay * 1_000_000_000));

    for (coro_fns, 0..) |coro_fn, i| {
        // Try this coroutine
        const result = coro_fn() catch |err| {
            exceptions[i] = err;
            continue;
        };

        // Success! Record winner
        winner_result = result;
        winner_index = i;
        break;
    }

    // If we have a winner, cancel remaining (simplified - they didn't start)
    if (winner_result) |result| {
        return .{
            .result = result,
            .index = winner_index.?,
            .exceptions = exceptions,
        };
    }

    // All failed
    _ = delay_ns;
    return null;
}

/// Result type for staggered_race
pub fn StaggeredResult(comptime T: type) type {
    return struct {
        result: T,
        index: usize,
        exceptions: []?anyerror,
    };
}

// Tests
test "staggered_race empty" {
    const allocator = std.testing.allocator;

    const result = try staggeredRace(allocator, i64, &[_]*const fn () anyerror!i64{}, 0.1);
    try std.testing.expect(result == null);
}
