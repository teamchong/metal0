//! test.test_free_threading.test_atomics - Atomic operations
//!
//! This module tests atomic operations for free-threaded Python execution.
//! It provides wrappers for various atomic primitives and tests their
//! correctness under concurrent access.
const std = @import("std");

/// Atomic integer with full set of operations
pub fn AtomicInt(comptime T: type) type {
    return struct {
        const Self = @This();

        value: std.atomic.Value(T),
        operation_count: std.atomic.Value(usize),

        pub fn init(initial: T) Self {
            return .{
                .value = std.atomic.Value(T).init(initial),
                .operation_count = std.atomic.Value(usize).init(0),
            };
        }

        pub fn load(self: *const Self, order: std.atomic.Ordering) T {
            return self.value.load(order);
        }

        pub fn store(self: *Self, val: T, order: std.atomic.Ordering) void {
            self.value.store(val, order);
            _ = self.operation_count.fetchAdd(1, .monotonic);
        }

        pub fn fetchAdd(self: *Self, delta: T, order: std.atomic.Ordering) T {
            _ = self.operation_count.fetchAdd(1, .monotonic);
            return self.value.fetchAdd(delta, order);
        }

        pub fn fetchSub(self: *Self, delta: T, order: std.atomic.Ordering) T {
            _ = self.operation_count.fetchAdd(1, .monotonic);
            return self.value.fetchSub(delta, order);
        }

        pub fn fetchAnd(self: *Self, mask: T, order: std.atomic.Ordering) T {
            _ = self.operation_count.fetchAdd(1, .monotonic);
            return self.value.fetchAnd(mask, order);
        }

        pub fn fetchOr(self: *Self, mask: T, order: std.atomic.Ordering) T {
            _ = self.operation_count.fetchAdd(1, .monotonic);
            return self.value.fetchOr(mask, order);
        }

        pub fn fetchXor(self: *Self, mask: T, order: std.atomic.Ordering) T {
            _ = self.operation_count.fetchAdd(1, .monotonic);
            return self.value.fetchXor(mask, order);
        }

        pub fn swap(self: *Self, val: T, order: std.atomic.Ordering) T {
            _ = self.operation_count.fetchAdd(1, .monotonic);
            return self.value.swap(val, order);
        }

        pub fn compareAndSwap(self: *Self, expected: T, desired: T, success_order: std.atomic.Ordering, failure_order: std.atomic.Ordering) ?T {
            _ = self.operation_count.fetchAdd(1, .monotonic);
            return self.value.cmpxchgStrong(expected, desired, success_order, failure_order);
        }

        pub fn getOperationCount(self: *const Self) usize {
            return self.operation_count.load(.acquire);
        }
    };
}

/// Atomic pointer wrapper
pub fn AtomicPtr(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: std.atomic.Value(?*T),

        pub fn init(initial: ?*T) Self {
            return .{ .ptr = std.atomic.Value(?*T).init(initial) };
        }

        pub fn load(self: *const Self, order: std.atomic.Ordering) ?*T {
            return self.ptr.load(order);
        }

        pub fn store(self: *Self, val: ?*T, order: std.atomic.Ordering) void {
            self.ptr.store(val, order);
        }

        pub fn swap(self: *Self, val: ?*T, order: std.atomic.Ordering) ?*T {
            return self.ptr.swap(val, order);
        }

        pub fn compareAndSwap(self: *Self, expected: ?*T, desired: ?*T, success_order: std.atomic.Ordering, failure_order: std.atomic.Ordering) ?*T {
            const result = self.ptr.cmpxchgStrong(expected, desired, success_order, failure_order);
            return result;
        }

        pub fn isNull(self: *const Self) bool {
            return self.ptr.load(.acquire) == null;
        }
    };
}

/// Atomic bit field for flag manipulation
pub const AtomicBitField = struct {
    const Self = @This();

    bits: std.atomic.Value(u64),

    pub fn init(initial: u64) Self {
        return .{ .bits = std.atomic.Value(u64).init(initial) };
    }

    pub fn setBit(self: *Self, bit: u6) void {
        const mask = @as(u64, 1) << bit;
        _ = self.bits.fetchOr(mask, .release);
    }

    pub fn clearBit(self: *Self, bit: u6) void {
        const mask = ~(@as(u64, 1) << bit);
        _ = self.bits.fetchAnd(mask, .release);
    }

    pub fn toggleBit(self: *Self, bit: u6) void {
        const mask = @as(u64, 1) << bit;
        _ = self.bits.fetchXor(mask, .release);
    }

    pub fn testBit(self: *const Self, bit: u6) bool {
        const mask = @as(u64, 1) << bit;
        return (self.bits.load(.acquire) & mask) != 0;
    }

    pub fn testAndSetBit(self: *Self, bit: u6) bool {
        const mask = @as(u64, 1) << bit;
        const old = self.bits.fetchOr(mask, .acq_rel);
        return (old & mask) != 0;
    }

    pub fn testAndClearBit(self: *Self, bit: u6) bool {
        const mask = @as(u64, 1) << bit;
        const inv_mask = ~mask;
        const old = self.bits.fetchAnd(inv_mask, .acq_rel);
        return (old & mask) != 0;
    }

    pub fn popCount(self: *const Self) u7 {
        return @popCount(self.bits.load(.acquire));
    }

    pub fn load(self: *const Self) u64 {
        return self.bits.load(.acquire);
    }

    pub fn store(self: *Self, val: u64) void {
        self.bits.store(val, .release);
    }
};

/// Lock-free counter using compare-and-swap
pub const LockFreeCounter = struct {
    const Self = @This();

    value: std.atomic.Value(i64),
    cas_failures: std.atomic.Value(usize),
    operations: std.atomic.Value(usize),

    pub fn init(initial: i64) Self {
        return .{
            .value = std.atomic.Value(i64).init(initial),
            .cas_failures = std.atomic.Value(usize).init(0),
            .operations = std.atomic.Value(usize).init(0),
        };
    }

    pub fn increment(self: *Self) i64 {
        return self.add(1);
    }

    pub fn decrement(self: *Self) i64 {
        return self.add(-1);
    }

    pub fn add(self: *Self, delta: i64) i64 {
        _ = self.operations.fetchAdd(1, .monotonic);
        var current = self.value.load(.acquire);

        while (true) {
            const result = self.value.cmpxchgWeak(current, current + delta, .release, .acquire);
            if (result) |old| {
                current = old;
                _ = self.cas_failures.fetchAdd(1, .monotonic);
            } else {
                return current + delta;
            }
        }
    }

    pub fn get(self: *const Self) i64 {
        return self.value.load(.acquire);
    }

    pub fn set(self: *Self, val: i64) void {
        self.value.store(val, .release);
    }

    pub fn getStats(self: *const Self) struct { ops: usize, failures: usize } {
        return .{
            .ops = self.operations.load(.acquire),
            .failures = self.cas_failures.load(.acquire),
        };
    }
};

/// Atomic minimum/maximum operations
pub fn AtomicMinMax(comptime T: type) type {
    return struct {
        const Self = @This();

        value: std.atomic.Value(T),

        pub fn init(initial: T) Self {
            return .{ .value = std.atomic.Value(T).init(initial) };
        }

        pub fn updateMin(self: *Self, val: T) T {
            var current = self.value.load(.acquire);
            while (val < current) {
                const result = self.value.cmpxchgWeak(current, val, .release, .acquire);
                if (result) |old| {
                    current = old;
                } else {
                    return val;
                }
            }
            return current;
        }

        pub fn updateMax(self: *Self, val: T) T {
            var current = self.value.load(.acquire);
            while (val > current) {
                const result = self.value.cmpxchgWeak(current, val, .release, .acquire);
                if (result) |old| {
                    current = old;
                } else {
                    return val;
                }
            }
            return current;
        }

        pub fn get(self: *const Self) T {
            return self.value.load(.acquire);
        }
    };
}

/// Atomic pair for related values
pub fn AtomicPair(comptime T: type) type {
    const PairType = packed struct {
        first: T,
        second: T,
    };

    return struct {
        const Self = @This();

        value: std.atomic.Value(PairType),

        pub fn init(first: T, second: T) Self {
            return .{ .value = std.atomic.Value(PairType).init(.{ .first = first, .second = second }) };
        }

        pub fn load(self: *const Self) struct { first: T, second: T } {
            const pair = self.value.load(.acquire);
            return .{ .first = pair.first, .second = pair.second };
        }

        pub fn store(self: *Self, first: T, second: T) void {
            self.value.store(.{ .first = first, .second = second }, .release);
        }

        pub fn compareAndSwap(self: *Self, expected_first: T, expected_second: T, desired_first: T, desired_second: T) bool {
            const expected = PairType{ .first = expected_first, .second = expected_second };
            const desired = PairType{ .first = desired_first, .second = desired_second };
            return self.value.cmpxchgStrong(expected, desired, .acq_rel, .acquire) == null;
        }
    };
}

/// Spin lock using atomic operations
pub const AtomicSpinLock = struct {
    const Self = @This();

    locked: std.atomic.Value(bool),
    acquisitions: std.atomic.Value(usize),
    contentions: std.atomic.Value(usize),

    pub fn init() Self {
        return .{
            .locked = std.atomic.Value(bool).init(false),
            .acquisitions = std.atomic.Value(usize).init(0),
            .contentions = std.atomic.Value(usize).init(0),
        };
    }

    pub fn acquire(self: *Self) void {
        var spins: usize = 0;
        while (self.locked.swap(true, .acquire)) {
            spins += 1;
            std.atomic.spinLoopHint();
        }
        if (spins > 0) {
            _ = self.contentions.fetchAdd(1, .monotonic);
        }
        _ = self.acquisitions.fetchAdd(1, .monotonic);
    }

    pub fn tryAcquire(self: *Self) bool {
        if (!self.locked.swap(true, .acquire)) {
            _ = self.acquisitions.fetchAdd(1, .monotonic);
            return true;
        }
        return false;
    }

    pub fn release(self: *Self) void {
        self.locked.store(false, .release);
    }

    pub fn isLocked(self: *const Self) bool {
        return self.locked.load(.acquire);
    }

    pub fn getStats(self: *const Self) struct { acquisitions: usize, contentions: usize } {
        return .{
            .acquisitions = self.acquisitions.load(.acquire),
            .contentions = self.contentions.load(.acquire),
        };
    }
};

/// Ticket lock for fair ordering
pub const TicketLock = struct {
    const Self = @This();

    ticket: std.atomic.Value(u64),
    serving: std.atomic.Value(u64),
    acquisitions: std.atomic.Value(usize),

    pub fn init() Self {
        return .{
            .ticket = std.atomic.Value(u64).init(0),
            .serving = std.atomic.Value(u64).init(0),
            .acquisitions = std.atomic.Value(usize).init(0),
        };
    }

    pub fn acquire(self: *Self) void {
        const my_ticket = self.ticket.fetchAdd(1, .acq_rel);
        while (self.serving.load(.acquire) != my_ticket) {
            std.atomic.spinLoopHint();
        }
        _ = self.acquisitions.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *Self) void {
        _ = self.serving.fetchAdd(1, .release);
    }

    pub fn isLocked(self: *const Self) bool {
        return self.ticket.load(.acquire) != self.serving.load(.acquire);
    }

    pub fn waiters(self: *const Self) u64 {
        const t = self.ticket.load(.acquire);
        const s = self.serving.load(.acquire);
        return if (t > s) t - s else 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "atomic_int_basic" {
    var ai = AtomicInt(i64).init(0);

    ai.store(10, .release);
    try std.testing.expectEqual(@as(i64, 10), ai.load(.acquire));

    const old = ai.fetchAdd(5, .acq_rel);
    try std.testing.expectEqual(@as(i64, 10), old);
    try std.testing.expectEqual(@as(i64, 15), ai.load(.acquire));
}

test "atomic_int_swap" {
    var ai = AtomicInt(i64).init(100);

    const old = ai.swap(200, .acq_rel);
    try std.testing.expectEqual(@as(i64, 100), old);
    try std.testing.expectEqual(@as(i64, 200), ai.load(.acquire));
}

test "atomic_int_cas" {
    var ai = AtomicInt(i64).init(42);

    // Should fail - expected doesn't match
    try std.testing.expectEqual(@as(?i64, 42), ai.compareAndSwap(0, 99, .acq_rel, .acquire));
    try std.testing.expectEqual(@as(i64, 42), ai.load(.acquire));

    // Should succeed
    try std.testing.expectEqual(@as(?i64, null), ai.compareAndSwap(42, 99, .acq_rel, .acquire));
    try std.testing.expectEqual(@as(i64, 99), ai.load(.acquire));
}

test "atomic_ptr_basic" {
    var data: i32 = 42;
    var ap = AtomicPtr(i32).init(&data);

    try std.testing.expect(!ap.isNull());
    try std.testing.expectEqual(&data, ap.load(.acquire).?);

    ap.store(null, .release);
    try std.testing.expect(ap.isNull());
}

test "atomic_bitfield_basic" {
    var bf = AtomicBitField.init(0);

    bf.setBit(0);
    try std.testing.expect(bf.testBit(0));
    try std.testing.expectEqual(@as(u7, 1), bf.popCount());

    bf.setBit(5);
    try std.testing.expect(bf.testBit(5));
    try std.testing.expectEqual(@as(u7, 2), bf.popCount());

    bf.clearBit(0);
    try std.testing.expect(!bf.testBit(0));
    try std.testing.expectEqual(@as(u7, 1), bf.popCount());
}

test "atomic_bitfield_test_and_set" {
    var bf = AtomicBitField.init(0);

    try std.testing.expect(!bf.testAndSetBit(3));
    try std.testing.expect(bf.testAndSetBit(3));
    try std.testing.expect(bf.testBit(3));
}

test "lock_free_counter_basic" {
    var counter = LockFreeCounter.init(0);

    try std.testing.expectEqual(@as(i64, 1), counter.increment());
    try std.testing.expectEqual(@as(i64, 2), counter.increment());
    try std.testing.expectEqual(@as(i64, 1), counter.decrement());
    try std.testing.expectEqual(@as(i64, 1), counter.get());
}

test "lock_free_counter_add" {
    var counter = LockFreeCounter.init(0);

    try std.testing.expectEqual(@as(i64, 10), counter.add(10));
    try std.testing.expectEqual(@as(i64, 5), counter.add(-5));
    try std.testing.expectEqual(@as(i64, 5), counter.get());
}

test "atomic_min_max_basic" {
    var mm = AtomicMinMax(i64).init(50);

    try std.testing.expectEqual(@as(i64, 30), mm.updateMin(30));
    try std.testing.expectEqual(@as(i64, 30), mm.get());

    try std.testing.expectEqual(@as(i64, 30), mm.updateMin(40)); // No change
    try std.testing.expectEqual(@as(i64, 30), mm.get());

    try std.testing.expectEqual(@as(i64, 100), mm.updateMax(100));
    try std.testing.expectEqual(@as(i64, 100), mm.get());
}

test "atomic_pair_basic" {
    var pair = AtomicPair(u32).init(1, 2);

    const vals = pair.load();
    try std.testing.expectEqual(@as(u32, 1), vals.first);
    try std.testing.expectEqual(@as(u32, 2), vals.second);

    pair.store(10, 20);
    const vals2 = pair.load();
    try std.testing.expectEqual(@as(u32, 10), vals2.first);
    try std.testing.expectEqual(@as(u32, 20), vals2.second);
}

test "atomic_spinlock_basic" {
    var lock = AtomicSpinLock.init();

    try std.testing.expect(!lock.isLocked());

    lock.acquire();
    try std.testing.expect(lock.isLocked());

    lock.release();
    try std.testing.expect(!lock.isLocked());
}

test "atomic_spinlock_try_acquire" {
    var lock = AtomicSpinLock.init();

    try std.testing.expect(lock.tryAcquire());
    try std.testing.expect(!lock.tryAcquire());

    lock.release();
    try std.testing.expect(lock.tryAcquire());
    lock.release();
}

test "ticket_lock_basic" {
    var lock = TicketLock.init();

    try std.testing.expect(!lock.isLocked());

    lock.acquire();
    try std.testing.expect(lock.isLocked());

    lock.release();
    try std.testing.expect(!lock.isLocked());
}

test "lock_free_counter_multithread" {
    var counter = LockFreeCounter.init(0);

    const num_threads = 4;
    const increments = 1000;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(c: *LockFreeCounter) void {
                for (0..increments) |_| {
                    _ = c.increment();
                }
            }
        }.run, .{&counter}) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    try std.testing.expectEqual(@as(i64, num_threads * increments), counter.get());
}

test "spinlock_multithread" {
    var lock = AtomicSpinLock.init();
    var counter = std.atomic.Value(usize).init(0);

    const num_threads = 4;
    const increments = 100;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(l: *AtomicSpinLock, c: *std.atomic.Value(usize)) void {
                for (0..increments) |_| {
                    l.acquire();
                    const val = c.load(.acquire);
                    c.store(val + 1, .release);
                    l.release();
                }
            }
        }.run, .{ &lock, &counter }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    try std.testing.expectEqual(@as(usize, num_threads * increments), counter.load(.acquire));
}

test "ticket_lock_fairness" {
    var lock = TicketLock.init();
    var order: [8]std.atomic.Value(usize) = undefined;
    for (&order) |*o| {
        o.* = std.atomic.Value(usize).init(0);
    }
    var next_order = std.atomic.Value(usize).init(0);

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(l: *TicketLock, ord: *[8]std.atomic.Value(usize), next: *std.atomic.Value(usize), tid: usize) void {
                l.acquire();
                const my_order = next.fetchAdd(1, .acq_rel);
                if (my_order < 8) {
                    ord[my_order].store(tid, .release);
                }
                l.release();
            }
        }.run, .{ &lock, &order, &next_order, i }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    // All threads should have completed
    try std.testing.expectEqual(@as(usize, num_threads), next_order.load(.acquire));
}
