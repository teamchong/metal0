//! test.test_free_threading.test_critical - Critical sections
//!
//! This module provides critical section implementations and tests for
//! protecting critical regions in free-threaded Python execution.
const std = @import("std");

/// A simple critical section with statistics tracking
pub const CriticalSection = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    held_by: std.atomic.Value(usize),
    entry_count: std.atomic.Value(usize),
    contention_count: std.atomic.Value(usize),
    max_wait_ns: std.atomic.Value(i64),
    total_wait_ns: std.atomic.Value(i64),
    hold_count: std.atomic.Value(usize),

    pub fn init() Self {
        return .{
            .mutex = .{},
            .held_by = std.atomic.Value(usize).init(0),
            .entry_count = std.atomic.Value(usize).init(0),
            .contention_count = std.atomic.Value(usize).init(0),
            .max_wait_ns = std.atomic.Value(i64).init(0),
            .total_wait_ns = std.atomic.Value(i64).init(0),
            .hold_count = std.atomic.Value(usize).init(0),
        };
    }

    pub fn enter(self: *Self) void {
        const start = std.time.nanoTimestamp();
        const tid = std.Thread.getCurrentId();

        // Track contention if already held
        if (self.held_by.load(.acquire) != 0) {
            _ = self.contention_count.fetchAdd(1, .monotonic);
        }

        self.mutex.lock();

        const elapsed = std.time.nanoTimestamp() - start;
        _ = self.total_wait_ns.fetchAdd(elapsed, .monotonic);
        self.updateMaxWait(elapsed);

        self.held_by.store(tid, .release);
        _ = self.entry_count.fetchAdd(1, .monotonic);
        _ = self.hold_count.fetchAdd(1, .monotonic);
    }

    pub fn leave(self: *Self) void {
        self.held_by.store(0, .release);
        _ = self.hold_count.fetchSub(1, .monotonic);
        self.mutex.unlock();
    }

    pub fn tryEnter(self: *Self) bool {
        if (self.mutex.tryLock()) {
            self.held_by.store(std.Thread.getCurrentId(), .release);
            _ = self.entry_count.fetchAdd(1, .monotonic);
            _ = self.hold_count.fetchAdd(1, .monotonic);
            return true;
        }
        return false;
    }

    fn updateMaxWait(self: *Self, wait_ns: i64) void {
        var max = self.max_wait_ns.load(.acquire);
        while (wait_ns > max) {
            const result = self.max_wait_ns.cmpxchgWeak(max, wait_ns, .release, .acquire);
            if (result) |new_max| {
                max = new_max;
            } else {
                break;
            }
        }
    }

    pub fn isHeld(self: *const Self) bool {
        return self.held_by.load(.acquire) != 0;
    }

    pub fn isHeldByCurrentThread(self: *const Self) bool {
        return self.held_by.load(.acquire) == std.Thread.getCurrentId();
    }

    pub fn getStats(self: *const Self) struct {
        entry_count: usize,
        contention_count: usize,
        max_wait_ns: i64,
        avg_wait_ns: i64,
    } {
        const entries = self.entry_count.load(.acquire);
        const total = self.total_wait_ns.load(.acquire);
        return .{
            .entry_count = entries,
            .contention_count = self.contention_count.load(.acquire),
            .max_wait_ns = self.max_wait_ns.load(.acquire),
            .avg_wait_ns = if (entries > 0) @divTrunc(total, @as(i64, @intCast(entries))) else 0,
        };
    }
};

/// Recursive critical section (reentrant lock)
pub const RecursiveCriticalSection = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    owner: std.atomic.Value(usize),
    recursion_count: usize,
    condition: std.Thread.Condition,

    pub fn init() Self {
        return .{
            .mutex = .{},
            .owner = std.atomic.Value(usize).init(0),
            .recursion_count = 0,
            .condition = .{},
        };
    }

    pub fn enter(self: *Self) void {
        const tid = std.Thread.getCurrentId();

        if (self.owner.load(.acquire) == tid) {
            self.recursion_count += 1;
            return;
        }

        self.mutex.lock();

        while (self.owner.load(.acquire) != 0) {
            self.condition.wait(&self.mutex);
        }

        self.owner.store(tid, .release);
        self.recursion_count = 1;
        self.mutex.unlock();
    }

    pub fn leave(self: *Self) void {
        const tid = std.Thread.getCurrentId();

        if (self.owner.load(.acquire) != tid) {
            return; // Not owner
        }

        self.recursion_count -= 1;
        if (self.recursion_count == 0) {
            self.mutex.lock();
            self.owner.store(0, .release);
            self.condition.signal();
            self.mutex.unlock();
        }
    }

    pub fn getRecursionDepth(self: *const Self) usize {
        return self.recursion_count;
    }

    pub fn isHeldByCurrentThread(self: *const Self) bool {
        return self.owner.load(.acquire) == std.Thread.getCurrentId();
    }
};

/// Read-write critical section
pub const RWCriticalSection = struct {
    const Self = @This();

    rwlock: std.Thread.RwLock,
    readers: std.atomic.Value(usize),
    writers: std.atomic.Value(usize),
    write_waiters: std.atomic.Value(usize),
    read_entries: std.atomic.Value(usize),
    write_entries: std.atomic.Value(usize),

    pub fn init() Self {
        return .{
            .rwlock = .{},
            .readers = std.atomic.Value(usize).init(0),
            .writers = std.atomic.Value(usize).init(0),
            .write_waiters = std.atomic.Value(usize).init(0),
            .read_entries = std.atomic.Value(usize).init(0),
            .write_entries = std.atomic.Value(usize).init(0),
        };
    }

    pub fn enterRead(self: *Self) void {
        self.rwlock.lockShared();
        _ = self.readers.fetchAdd(1, .monotonic);
        _ = self.read_entries.fetchAdd(1, .monotonic);
    }

    pub fn leaveRead(self: *Self) void {
        _ = self.readers.fetchSub(1, .monotonic);
        self.rwlock.unlockShared();
    }

    pub fn enterWrite(self: *Self) void {
        _ = self.write_waiters.fetchAdd(1, .monotonic);
        self.rwlock.lock();
        _ = self.write_waiters.fetchSub(1, .monotonic);
        _ = self.writers.fetchAdd(1, .monotonic);
        _ = self.write_entries.fetchAdd(1, .monotonic);
    }

    pub fn leaveWrite(self: *Self) void {
        _ = self.writers.fetchSub(1, .monotonic);
        self.rwlock.unlock();
    }

    pub fn tryEnterRead(self: *Self) bool {
        if (self.rwlock.tryLockShared()) {
            _ = self.readers.fetchAdd(1, .monotonic);
            _ = self.read_entries.fetchAdd(1, .monotonic);
            return true;
        }
        return false;
    }

    pub fn tryEnterWrite(self: *Self) bool {
        if (self.rwlock.tryLock()) {
            _ = self.writers.fetchAdd(1, .monotonic);
            _ = self.write_entries.fetchAdd(1, .monotonic);
            return true;
        }
        return false;
    }

    pub fn getStats(self: *const Self) struct {
        current_readers: usize,
        current_writers: usize,
        write_waiters: usize,
        read_entries: usize,
        write_entries: usize,
    } {
        return .{
            .current_readers = self.readers.load(.acquire),
            .current_writers = self.writers.load(.acquire),
            .write_waiters = self.write_waiters.load(.acquire),
            .read_entries = self.read_entries.load(.acquire),
            .write_entries = self.write_entries.load(.acquire),
        };
    }
};

/// Scoped critical section helper
pub fn ScopedCritical(comptime CS: type) type {
    return struct {
        const Self = @This();
        cs: *CS,

        pub fn init(cs: *CS) Self {
            cs.enter();
            return .{ .cs = cs };
        }

        pub fn deinit(self: Self) void {
            self.cs.leave();
        }
    };
}

/// Barrier for synchronizing multiple threads
pub const Barrier = struct {
    const Self = @This();

    count: usize,
    waiting: std.atomic.Value(usize),
    generation: std.atomic.Value(usize),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,

    pub fn init(count: usize) Self {
        return .{
            .count = count,
            .waiting = std.atomic.Value(usize).init(0),
            .generation = std.atomic.Value(usize).init(0),
            .mutex = .{},
            .condition = .{},
        };
    }

    pub fn wait(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const gen = self.generation.load(.acquire);
        const waiting = self.waiting.fetchAdd(1, .monotonic) + 1;

        if (waiting == self.count) {
            self.waiting.store(0, .release);
            _ = self.generation.fetchAdd(1, .release);
            self.condition.broadcast();
        } else {
            while (self.generation.load(.acquire) == gen) {
                self.condition.wait(&self.mutex);
            }
        }
    }

    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.waiting.store(0, .release);
    }
};

/// Semaphore for limiting concurrent access
pub const Semaphore = struct {
    const Self = @This();

    permits: std.atomic.Value(isize),
    max_permits: isize,
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    acquired_count: std.atomic.Value(usize),

    pub fn init(permits: usize) Self {
        return .{
            .permits = std.atomic.Value(isize).init(@intCast(permits)),
            .max_permits = @intCast(permits),
            .mutex = .{},
            .condition = .{},
            .acquired_count = std.atomic.Value(usize).init(0),
        };
    }

    pub fn acquire(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.permits.load(.acquire) <= 0) {
            self.condition.wait(&self.mutex);
        }

        _ = self.permits.fetchSub(1, .release);
        _ = self.acquired_count.fetchAdd(1, .monotonic);
    }

    pub fn tryAcquire(self: *Self) bool {
        while (true) {
            const current = self.permits.load(.acquire);
            if (current <= 0) return false;

            if (self.permits.cmpxchgWeak(current, current - 1, .release, .acquire)) |_| {
                continue;
            }

            _ = self.acquired_count.fetchAdd(1, .monotonic);
            return true;
        }
    }

    pub fn release(self: *Self) void {
        const prev = self.permits.fetchAdd(1, .release);
        if (prev < 0) {
            self.mutex.lock();
            self.condition.signal();
            self.mutex.unlock();
        }
    }

    pub fn availablePermits(self: *const Self) isize {
        return self.permits.load(.acquire);
    }
};

/// Once-only initialization
pub const Once = struct {
    const Self = @This();

    done: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,

    pub fn init() Self {
        return .{
            .done = std.atomic.Value(bool).init(false),
            .mutex = .{},
        };
    }

    pub fn callOnce(self: *Self, func: *const fn () void) void {
        if (self.done.load(.acquire)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.done.load(.acquire)) {
            func();
            self.done.store(true, .release);
        }
    }

    pub fn callOnceWithArg(self: *Self, comptime T: type, func: *const fn (T) void, arg: T) void {
        if (self.done.load(.acquire)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.done.load(.acquire)) {
            func(arg);
            self.done.store(true, .release);
        }
    }

    pub fn isDone(self: *const Self) bool {
        return self.done.load(.acquire);
    }

    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.done.store(false, .release);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "critical_section_basic" {
    var cs = CriticalSection.init();

    try std.testing.expect(!cs.isHeld());

    cs.enter();
    try std.testing.expect(cs.isHeld());
    try std.testing.expect(cs.isHeldByCurrentThread());

    cs.leave();
    try std.testing.expect(!cs.isHeld());
}

test "critical_section_try_enter" {
    var cs = CriticalSection.init();

    try std.testing.expect(cs.tryEnter());
    try std.testing.expect(cs.isHeld());

    cs.leave();
}

test "critical_section_stats" {
    var cs = CriticalSection.init();

    cs.enter();
    cs.leave();
    cs.enter();
    cs.leave();

    const stats = cs.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.entry_count);
}

test "recursive_critical_section_basic" {
    var rcs = RecursiveCriticalSection.init();

    rcs.enter();
    try std.testing.expectEqual(@as(usize, 1), rcs.getRecursionDepth());

    rcs.enter();
    try std.testing.expectEqual(@as(usize, 2), rcs.getRecursionDepth());

    rcs.leave();
    try std.testing.expectEqual(@as(usize, 1), rcs.getRecursionDepth());

    rcs.leave();
    try std.testing.expect(!rcs.isHeldByCurrentThread());
}

test "rw_critical_section_read" {
    var rwcs = RWCriticalSection.init();

    rwcs.enterRead();
    try std.testing.expectEqual(@as(usize, 1), rwcs.readers.load(.acquire));

    rwcs.leaveRead();
    try std.testing.expectEqual(@as(usize, 0), rwcs.readers.load(.acquire));
}

test "rw_critical_section_write" {
    var rwcs = RWCriticalSection.init();

    rwcs.enterWrite();
    try std.testing.expectEqual(@as(usize, 1), rwcs.writers.load(.acquire));

    rwcs.leaveWrite();
    try std.testing.expectEqual(@as(usize, 0), rwcs.writers.load(.acquire));
}

test "rw_critical_section_stats" {
    var rwcs = RWCriticalSection.init();

    rwcs.enterRead();
    rwcs.leaveRead();
    rwcs.enterRead();
    rwcs.leaveRead();
    rwcs.enterWrite();
    rwcs.leaveWrite();

    const stats = rwcs.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.read_entries);
    try std.testing.expectEqual(@as(usize, 1), stats.write_entries);
}

test "barrier_basic" {
    var barrier = Barrier.init(1);
    barrier.wait();
    // Should complete immediately with count of 1
}

test "semaphore_basic" {
    var sem = Semaphore.init(2);

    try std.testing.expectEqual(@as(isize, 2), sem.availablePermits());

    sem.acquire();
    try std.testing.expectEqual(@as(isize, 1), sem.availablePermits());

    sem.acquire();
    try std.testing.expectEqual(@as(isize, 0), sem.availablePermits());

    try std.testing.expect(!sem.tryAcquire());

    sem.release();
    try std.testing.expectEqual(@as(isize, 1), sem.availablePermits());
}

test "once_basic" {
    var once = Once.init();
    var counter: usize = 0;

    try std.testing.expect(!once.isDone());

    once.callOnce(struct {
        fn inc() void {
            // Can't capture counter, so use a different approach
        }
    }.inc);

    try std.testing.expect(once.isDone());

    // Second call should not execute
    once.callOnce(struct {
        fn inc() void {}
    }.inc);
}

test "critical_section_multithread" {
    var cs = CriticalSection.init();
    var counter = std.atomic.Value(usize).init(0);

    const num_threads = 4;
    const increments = 100;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(section: *CriticalSection, cnt: *std.atomic.Value(usize)) void {
                for (0..increments) |_| {
                    section.enter();
                    const val = cnt.load(.acquire);
                    cnt.store(val + 1, .release);
                    section.leave();
                }
            }
        }.run, .{ &cs, &counter }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    try std.testing.expectEqual(@as(usize, num_threads * increments), counter.load(.acquire));
}

test "barrier_multithread" {
    const num_threads = 4;
    var barrier = Barrier.init(num_threads);
    var counter = std.atomic.Value(usize).init(0);
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(b: *Barrier, c: *std.atomic.Value(usize)) void {
                _ = c.fetchAdd(1, .monotonic);
                b.wait();
                // All threads should see counter == num_threads after barrier
            }
        }.run, .{ &barrier, &counter }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    try std.testing.expectEqual(@as(usize, num_threads), counter.load(.acquire));
}
