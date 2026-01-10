//! asyncio.threads - Thread integration for asyncio
//! Reference: cpython/Lib/asyncio/threads.py

const std = @import("std");
const futures = @import("futures.zig");

/// Run a blocking function in a thread pool
/// CPython: async def to_thread(func, /, *args, **kwargs)
pub fn toThread(
    allocator: std.mem.Allocator,
    comptime T: type,
    comptime func: fn () T,
) !*futures.Future(T) {
    const future = try futures.Future(T).init(allocator);

    // Spawn thread to run function
    const thread = try std.Thread.spawn(.{}, struct {
        fn threadFn(fut: *futures.Future(T)) void {
            const result = func();
            fut.resolve(result);
        }
    }.threadFn, .{future});

    thread.detach();
    return future;
}

/// Run a function with error handling in thread pool
pub fn toThreadWithError(
    allocator: std.mem.Allocator,
    comptime T: type,
    comptime func: fn () anyerror!T,
) !*futures.Future(T) {
    const future = try futures.Future(T).init(allocator);

    const thread = try std.Thread.spawn(.{}, struct {
        fn threadFn(fut: *futures.Future(T)) void {
            const result = func() catch |err| {
                fut.reject(err);
                return;
            };
            fut.resolve(result);
        }
    }.threadFn, .{future});

    thread.detach();
    return future;
}

// Tests
test "to_thread types compile" {
    // Just verify the generic types compile
    const FutureInt = futures.Future(i64);
    try std.testing.expect(@sizeOf(FutureInt) > 0);
}
