//! test.test_asyncio.test_locks - Tests for asyncio synchronization primitives
//! Reference: cpython/Lib/test/test_asyncio/test_locks.py
//!
//! Tests for Lock, Event, Condition, Semaphore, BoundedSemaphore, Barrier

const std = @import("std");
const utils = @import("utils.zig");

// ============================================================================
// Lock Implementation for Testing
// ============================================================================

/// An asyncio-style Lock for mutual exclusion
pub const Lock = struct {
    const Self = @This();

    _locked: bool = false,
    _waiters: std.ArrayList(*Waiter),
    allocator: std.mem.Allocator,

    pub const Waiter = struct {
        resolved: bool = false,
        result: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._waiters = std.ArrayList(*Waiter).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._waiters.deinit();
    }

    pub fn locked(self: *const Self) bool {
        return self._locked;
    }

    /// Acquire the lock (blocking)
    pub fn acquire(self: *Self) !bool {
        if (!self._locked) {
            self._locked = true;
            return true;
        }

        // Create waiter and wait
        var waiter = Waiter{};
        try self._waiters.append(&waiter);

        // In real async, we'd suspend here
        // For testing, we simulate immediate acquisition
        while (!waiter.resolved) {
            // Spin wait (in real impl, this would be async suspension)
            std.atomic.spinLoopHint();
        }

        return waiter.result;
    }

    /// Try to acquire without blocking
    pub fn acquire_nowait(self: *Self) bool {
        if (!self._locked) {
            self._locked = true;
            return true;
        }
        return false;
    }

    /// Release the lock
    pub fn release(self: *Self) void {
        if (!self._locked) {
            @panic("Lock.release: lock is not acquired");
        }

        if (self._waiters.items.len > 0) {
            const waiter = self._waiters.orderedRemove(0);
            waiter.result = true;
            waiter.resolved = true;
        } else {
            self._locked = false;
        }
    }
};

// ============================================================================
// Event Implementation
// ============================================================================

/// An asyncio-style Event for signaling between coroutines
pub const Event = struct {
    const Self = @This();

    _value: bool = false,
    _waiters: std.ArrayList(*EventWaiter),
    allocator: std.mem.Allocator,

    pub const EventWaiter = struct {
        resolved: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._waiters = std.ArrayList(*EventWaiter).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._waiters.deinit();
    }

    pub fn is_set(self: *const Self) bool {
        return self._value;
    }

    pub fn set(self: *Self) void {
        if (!self._value) {
            self._value = true;
            // Wake all waiters
            for (self._waiters.items) |waiter| {
                waiter.resolved = true;
            }
            self._waiters.clearRetainingCapacity();
        }
    }

    pub fn clear(self: *Self) void {
        self._value = false;
    }

    pub fn wait(self: *Self) !void {
        if (self._value) {
            return;
        }

        var waiter = EventWaiter{};
        try self._waiters.append(&waiter);

        while (!waiter.resolved and !self._value) {
            std.atomic.spinLoopHint();
        }
    }
};

// ============================================================================
// Condition Implementation
// ============================================================================

/// An asyncio-style Condition variable
pub const Condition = struct {
    const Self = @This();

    _lock: ?*Lock = null,
    _waiters: std.ArrayList(*CondWaiter),
    allocator: std.mem.Allocator,
    _owns_lock: bool = false,

    pub const CondWaiter = struct {
        resolved: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, lock: ?*Lock) Self {
        return .{
            .allocator = allocator,
            ._lock = lock,
            ._waiters = std.ArrayList(*CondWaiter).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._waiters.deinit();
    }

    pub fn locked(self: *const Self) bool {
        if (self._lock) |l| {
            return l.locked();
        }
        return false;
    }

    pub fn acquire(self: *Self) !bool {
        if (self._lock) |l| {
            return l.acquire();
        }
        return true;
    }

    pub fn release(self: *Self) void {
        if (self._lock) |l| {
            l.release();
        }
    }

    pub fn wait(self: *Self) !void {
        if (self._lock) |l| {
            if (!l.locked()) {
                return error.NotAcquired;
            }
        }

        var waiter = CondWaiter{};
        try self._waiters.append(&waiter);

        // Release lock while waiting
        self.release();

        while (!waiter.resolved) {
            std.atomic.spinLoopHint();
        }

        // Reacquire lock
        _ = try self.acquire();
    }

    pub fn notify(self: *Self, n: usize) void {
        var count: usize = 0;
        while (count < n and self._waiters.items.len > 0) {
            const waiter = self._waiters.orderedRemove(0);
            waiter.resolved = true;
            count += 1;
        }
    }

    pub fn notify_all(self: *Self) void {
        for (self._waiters.items) |waiter| {
            waiter.resolved = true;
        }
        self._waiters.clearRetainingCapacity();
    }
};

// ============================================================================
// Semaphore Implementation
// ============================================================================

/// An asyncio-style Semaphore
pub const Semaphore = struct {
    const Self = @This();

    _value: i64,
    _waiters: std.ArrayList(*SemWaiter),
    allocator: std.mem.Allocator,

    pub const SemWaiter = struct {
        resolved: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, value: i64) Self {
        return .{
            .allocator = allocator,
            ._value = value,
            ._waiters = std.ArrayList(*SemWaiter).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._waiters.deinit();
    }

    pub fn locked(self: *const Self) bool {
        return self._value == 0;
    }

    pub fn acquire(self: *Self) !bool {
        if (self._value > 0) {
            self._value -= 1;
            return true;
        }

        var waiter = SemWaiter{};
        try self._waiters.append(&waiter);

        while (!waiter.resolved) {
            std.atomic.spinLoopHint();
        }

        return true;
    }

    pub fn release(self: *Self) void {
        self._value += 1;
        if (self._waiters.items.len > 0) {
            const waiter = self._waiters.orderedRemove(0);
            waiter.resolved = true;
            self._value -= 1;
        }
    }
};

/// A bounded semaphore that raises on over-release
pub const BoundedSemaphore = struct {
    const Self = @This();

    _value: i64,
    _bound: i64,
    _waiters: std.ArrayList(*Semaphore.SemWaiter),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, value: i64) Self {
        return .{
            .allocator = allocator,
            ._value = value,
            ._bound = value,
            ._waiters = std.ArrayList(*Semaphore.SemWaiter).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._waiters.deinit();
    }

    pub fn locked(self: *const Self) bool {
        return self._value == 0;
    }

    pub fn acquire(self: *Self) !bool {
        if (self._value > 0) {
            self._value -= 1;
            return true;
        }

        var waiter = Semaphore.SemWaiter{};
        try self._waiters.append(&waiter);

        while (!waiter.resolved) {
            std.atomic.spinLoopHint();
        }

        return true;
    }

    pub fn release(self: *Self) !void {
        if (self._value >= self._bound) {
            return error.ValueError;
        }
        self._value += 1;
        if (self._waiters.items.len > 0) {
            const waiter = self._waiters.orderedRemove(0);
            waiter.resolved = true;
            self._value -= 1;
        }
    }
};

// ============================================================================
// Barrier Implementation
// ============================================================================

/// An asyncio-style Barrier for synchronizing multiple coroutines
pub const Barrier = struct {
    const Self = @This();

    _parties: usize,
    _count: usize = 0,
    _state: State = .filling,
    _waiters: std.ArrayList(*BarrierWaiter),
    allocator: std.mem.Allocator,

    pub const State = enum {
        filling,
        draining,
        resetting,
        broken,
    };

    pub const BarrierWaiter = struct {
        resolved: bool = false,
        index: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator, parties: usize) Self {
        return .{
            .allocator = allocator,
            ._parties = parties,
            ._waiters = std.ArrayList(*BarrierWaiter).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._waiters.deinit();
    }

    pub fn parties(self: *const Self) usize {
        return self._parties;
    }

    pub fn n_waiting(self: *const Self) usize {
        return self._count;
    }

    pub fn broken(self: *const Self) bool {
        return self._state == .broken;
    }

    pub fn wait(self: *Self) !usize {
        if (self._state == .broken) {
            return error.BrokenBarrierError;
        }

        self._count += 1;
        const index = self._count - 1;

        if (self._count == self._parties) {
            // Last one in, release all
            self._state = .draining;
            for (self._waiters.items) |waiter| {
                waiter.resolved = true;
            }
            self._waiters.clearRetainingCapacity();
            self._count = 0;
            self._state = .filling;
            return index;
        }

        var waiter = BarrierWaiter{ .index = index };
        try self._waiters.append(&waiter);

        while (!waiter.resolved) {
            if (self._state == .broken) {
                return error.BrokenBarrierError;
            }
            std.atomic.spinLoopHint();
        }

        return index;
    }

    pub fn reset(self: *Self) void {
        self._state = .resetting;
        for (self._waiters.items) |waiter| {
            waiter.resolved = true;
        }
        self._waiters.clearRetainingCapacity();
        self._count = 0;
        self._state = .filling;
    }

    pub fn abort(self: *Self) void {
        self._state = .broken;
        for (self._waiters.items) |waiter| {
            waiter.resolved = true;
        }
        self._waiters.clearRetainingCapacity();
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testLockBasic() !void {
    const allocator = std.testing.allocator;
    var lock = Lock.init(allocator);
    defer lock.deinit();

    try std.testing.expect(!lock.locked());
    try std.testing.expect(lock.acquire_nowait());
    try std.testing.expect(lock.locked());
    lock.release();
    try std.testing.expect(!lock.locked());
}

fn testLockAcquireNowait() !void {
    const allocator = std.testing.allocator;
    var lock = Lock.init(allocator);
    defer lock.deinit();

    try std.testing.expect(lock.acquire_nowait());
    try std.testing.expect(!lock.acquire_nowait()); // Already locked
    lock.release();
    try std.testing.expect(lock.acquire_nowait()); // Available again
    lock.release();
}

fn testEventBasic() !void {
    const allocator = std.testing.allocator;
    var event = Event.init(allocator);
    defer event.deinit();

    try std.testing.expect(!event.is_set());
    event.set();
    try std.testing.expect(event.is_set());
    event.clear();
    try std.testing.expect(!event.is_set());
}

fn testEventWaitSet() !void {
    const allocator = std.testing.allocator;
    var event = Event.init(allocator);
    defer event.deinit();

    event.set();
    try event.wait(); // Should return immediately
    try std.testing.expect(event.is_set());
}

fn testSemaphoreBasic() !void {
    const allocator = std.testing.allocator;
    var sem = Semaphore.init(allocator, 2);
    defer sem.deinit();

    try std.testing.expect(!sem.locked());
    _ = try sem.acquire();
    try std.testing.expect(!sem.locked());
    _ = try sem.acquire();
    try std.testing.expect(sem.locked());
    sem.release();
    try std.testing.expect(!sem.locked());
}

fn testBoundedSemaphoreOverRelease() !void {
    const allocator = std.testing.allocator;
    var sem = BoundedSemaphore.init(allocator, 1);
    defer sem.deinit();

    const err = sem.release();
    try std.testing.expectError(error.ValueError, err);
}

fn testBarrierBasic() !void {
    const allocator = std.testing.allocator;
    var barrier = Barrier.init(allocator, 1);
    defer barrier.deinit();

    try std.testing.expectEqual(@as(usize, 1), barrier.parties());
    try std.testing.expectEqual(@as(usize, 0), barrier.n_waiting());
    try std.testing.expect(!barrier.broken());
}

fn testBarrierAbort() !void {
    const allocator = std.testing.allocator;
    var barrier = Barrier.init(allocator, 3);
    defer barrier.deinit();

    barrier.abort();
    try std.testing.expect(barrier.broken());

    const err = barrier.wait();
    try std.testing.expectError(error.BrokenBarrierError, err);
}

fn testConditionBasic() !void {
    const allocator = std.testing.allocator;
    var lock = Lock.init(allocator);
    defer lock.deinit();

    var cond = Condition.init(allocator, &lock);
    defer cond.deinit();

    try std.testing.expect(!cond.locked());
    _ = try cond.acquire();
    try std.testing.expect(cond.locked());
    cond.release();
    try std.testing.expect(!cond.locked());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "Lock basic" {
    try testLockBasic();
}

test "Lock acquire_nowait" {
    try testLockAcquireNowait();
}

test "Event basic" {
    try testEventBasic();
}

test "Event wait when set" {
    try testEventWaitSet();
}

test "Semaphore basic" {
    try testSemaphoreBasic();
}

test "BoundedSemaphore over-release" {
    try testBoundedSemaphoreOverRelease();
}

test "Barrier basic" {
    try testBarrierBasic();
}

test "Barrier abort" {
    try testBarrierAbort();
}

test "Condition basic" {
    try testConditionBasic();
}
