//! asyncio.locks - Synchronization primitives
//! Reference: cpython/Lib/asyncio/locks.py
//!
//! CPython __all__: ('Lock', 'Event', 'Condition', 'Semaphore', 'BoundedSemaphore', 'Barrier')

const std = @import("std");
const asyncio = @import("../asyncio.zig");

// Re-export all synchronization primitives from asyncio.zig (DRY)
pub const Lock = asyncio.Lock;
pub const Event = asyncio.Event;
pub const Condition = asyncio.Condition;
pub const Semaphore = asyncio.Semaphore;
pub const BoundedSemaphore = asyncio.BoundedSemaphore;
pub const Barrier = asyncio.Barrier;

// Re-export error types
pub const BrokenBarrierError = asyncio.BrokenBarrierError;

// Tests
test "Lock basic operations" {
    const allocator = std.testing.allocator;
    var lock = Lock.init(allocator);

    try std.testing.expect(!lock.locked());
    lock.acquire();
    try std.testing.expect(lock.locked());
    lock.release();
    try std.testing.expect(!lock.locked());
}

test "Event set and clear" {
    var event = Event.init();

    try std.testing.expect(!event.isSet());
    event.set();
    try std.testing.expect(event.isSet());
    event.clear();
    try std.testing.expect(!event.isSet());
}

test "Semaphore acquire and release" {
    var sem = Semaphore.init(2);

    try std.testing.expect(!sem.locked());
    sem.acquire();
    try std.testing.expect(!sem.locked());
    sem.acquire();
    try std.testing.expect(sem.locked());
    sem.release();
    try std.testing.expect(!sem.locked());
}
