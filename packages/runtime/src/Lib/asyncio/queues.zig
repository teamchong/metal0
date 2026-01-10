//! asyncio.queues - Queue implementations
//! Reference: cpython/Lib/asyncio/queues.py
//!
//! CPython __all__: ('Queue', 'PriorityQueue', 'LifoQueue', 'QueueFull', 'QueueEmpty', 'QueueShutDown')

const std = @import("std");
const asyncio = @import("../asyncio.zig");

// Re-export queue types from asyncio.zig (DRY)
pub const Queue = asyncio.Queue;
pub const PriorityQueue = asyncio.PriorityQueue;
pub const LifoQueue = asyncio.LifoQueue;

// Re-export queue errors
pub const QueueEmpty = asyncio.QueueEmpty;
pub const QueueFull = asyncio.QueueFull;
pub const QueueShutDown = asyncio.QueueShutDown;

// Tests
test "Queue basic operations" {
    const allocator = std.testing.allocator;
    var queue = Queue(i64).init(allocator, 10);
    defer queue.deinit();

    try std.testing.expect(queue.empty());
    try std.testing.expectEqual(@as(usize, 0), queue.qsize());

    try queue.putNowait(42);
    try std.testing.expectEqual(@as(usize, 1), queue.qsize());

    const val = try queue.getNowait();
    try std.testing.expectEqual(@as(i64, 42), val);
    try std.testing.expect(queue.empty());
}

test "Queue full/empty" {
    const allocator = std.testing.allocator;
    var queue = Queue(i64).init(allocator, 2);
    defer queue.deinit();

    try std.testing.expect(!queue.full());

    try queue.putNowait(1);
    try queue.putNowait(2);

    try std.testing.expect(queue.full());

    const err = queue.putNowait(3);
    try std.testing.expectError(error.QueueFull, err);
}

test "LifoQueue LIFO order" {
    const allocator = std.testing.allocator;
    var queue = LifoQueue(i64).init(allocator, 10);
    defer queue.deinit();

    try queue.queue.putNowait(1);
    try queue.queue.putNowait(2);
    try queue.queue.putNowait(3);

    try std.testing.expectEqual(@as(i64, 3), try queue.get());
    try std.testing.expectEqual(@as(i64, 2), try queue.get());
    try std.testing.expectEqual(@as(i64, 1), try queue.get());
}
