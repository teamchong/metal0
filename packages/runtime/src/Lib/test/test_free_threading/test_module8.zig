//! test.test_free_threading.test_memory - Memory ordering
//!
//! This module tests memory ordering semantics for free-threaded Python.
//! It provides utilities for testing different memory order constraints
//! and ensuring proper synchronization between threads.
const std = @import("std");

/// Memory ordering levels
pub const MemoryOrder = enum {
    relaxed,
    acquire,
    release,
    acq_rel,
    seq_cst,

    pub fn toStd(self: MemoryOrder) std.atomic.Ordering {
        return switch (self) {
            .relaxed => .monotonic,
            .acquire => .acquire,
            .release => .release,
            .acq_rel => .acq_rel,
            .seq_cst => .seq_cst,
        };
    }
};

/// Atomic flag with configurable ordering
pub const AtomicFlag = struct {
    const Self = @This();

    value: std.atomic.Value(bool),
    set_count: std.atomic.Value(usize),
    clear_count: std.atomic.Value(usize),

    pub fn init(initial: bool) Self {
        return .{
            .value = std.atomic.Value(bool).init(initial),
            .set_count = std.atomic.Value(usize).init(0),
            .clear_count = std.atomic.Value(usize).init(0),
        };
    }

    pub fn set(self: *Self, order: MemoryOrder) void {
        self.value.store(true, order.toStd());
        _ = self.set_count.fetchAdd(1, .monotonic);
    }

    pub fn clear(self: *Self, order: MemoryOrder) void {
        self.value.store(false, order.toStd());
        _ = self.clear_count.fetchAdd(1, .monotonic);
    }

    pub fn load(self: *const Self, order: MemoryOrder) bool {
        return self.value.load(order.toStd());
    }

    pub fn testAndSet(self: *Self, order: MemoryOrder) bool {
        const old = self.value.swap(true, order.toStd());
        if (!old) {
            _ = self.set_count.fetchAdd(1, .monotonic);
        }
        return old;
    }

    pub fn getStats(self: *const Self) struct { sets: usize, clears: usize } {
        return .{
            .sets = self.set_count.load(.acquire),
            .clears = self.clear_count.load(.acquire),
        };
    }
};

/// Message passing primitive for testing acquire-release semantics
pub fn MessagePassing(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,
        ready: std.atomic.Value(bool),
        reads: std.atomic.Value(usize),
        writes: std.atomic.Value(usize),

        pub fn init(initial: T) Self {
            return .{
                .data = initial,
                .ready = std.atomic.Value(bool).init(false),
                .reads = std.atomic.Value(usize).init(0),
                .writes = std.atomic.Value(usize).init(0),
            };
        }

        /// Send a value with release semantics
        pub fn send(self: *Self, value: T) void {
            self.data = value;
            std.atomic.fence(.release);
            self.ready.store(true, .release);
            _ = self.writes.fetchAdd(1, .monotonic);
        }

        /// Receive a value with acquire semantics
        pub fn receive(self: *Self) ?T {
            if (!self.ready.load(.acquire)) {
                return null;
            }
            std.atomic.fence(.acquire);
            _ = self.reads.fetchAdd(1, .monotonic);
            return self.data;
        }

        /// Wait for a value with spin loop
        pub fn waitAndReceive(self: *Self, timeout_ns: u64) ?T {
            const start = std.time.nanoTimestamp();

            while (!self.ready.load(.acquire)) {
                const elapsed: u64 = @intCast(std.time.nanoTimestamp() - start);
                if (elapsed >= timeout_ns) {
                    return null;
                }
                std.atomic.spinLoopHint();
            }

            std.atomic.fence(.acquire);
            _ = self.reads.fetchAdd(1, .monotonic);
            return self.data;
        }

        /// Reset for reuse
        pub fn reset(self: *Self) void {
            self.ready.store(false, .release);
        }
    };
}

/// Sequence lock for read-optimized scenarios
pub const SeqLock = struct {
    const Self = @This();

    sequence: std.atomic.Value(usize),

    pub fn init() Self {
        return .{ .sequence = std.atomic.Value(usize).init(0) };
    }

    pub fn writeBegin(self: *Self) void {
        _ = self.sequence.fetchAdd(1, .acquire);
    }

    pub fn writeEnd(self: *Self) void {
        _ = self.sequence.fetchAdd(1, .release);
    }

    pub fn readBegin(self: *const Self) usize {
        while (true) {
            const seq = self.sequence.load(.acquire);
            if (seq % 2 == 0) {
                return seq;
            }
            std.atomic.spinLoopHint();
        }
    }

    pub fn readRetry(self: *const Self, start_seq: usize) bool {
        std.atomic.fence(.acquire);
        return self.sequence.load(.acquire) != start_seq;
    }
};

/// Memory barrier wrapper
pub const MemoryBarrier = struct {
    pub fn fence(order: MemoryOrder) void {
        std.atomic.fence(order.toStd());
    }

    pub fn compilerFence() void {
        std.atomic.compilerFence(.seq_cst);
    }

    pub fn acquireFence() void {
        std.atomic.fence(.acquire);
    }

    pub fn releaseFence() void {
        std.atomic.fence(.release);
    }

    pub fn seqCstFence() void {
        std.atomic.fence(.seq_cst);
    }
};

/// Double-checked locking pattern implementation
pub fn DoubleCheckedInit(comptime T: type) type {
    return struct {
        const Self = @This();

        value: ?T,
        initialized: std.atomic.Value(bool),
        mutex: std.Thread.Mutex,
        init_attempts: std.atomic.Value(usize),

        pub fn init() Self {
            return .{
                .value = null,
                .initialized = std.atomic.Value(bool).init(false),
                .mutex = .{},
                .init_attempts = std.atomic.Value(usize).init(0),
            };
        }

        pub fn get(self: *Self, initializer: *const fn () T) T {
            // Fast path - already initialized
            if (self.initialized.load(.acquire)) {
                return self.value.?;
            }

            self.mutex.lock();
            defer self.mutex.unlock();

            // Double check after acquiring lock
            if (!self.initialized.load(.acquire)) {
                _ = self.init_attempts.fetchAdd(1, .monotonic);
                self.value = initializer();
                std.atomic.fence(.release);
                self.initialized.store(true, .release);
            }

            return self.value.?;
        }

        pub fn getInitAttempts(self: *const Self) usize {
            return self.init_attempts.load(.acquire);
        }

        pub fn isInitialized(self: *const Self) bool {
            return self.initialized.load(.acquire);
        }
    };
}

/// Store buffer for testing store-load ordering
pub fn StoreBuffer(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]std.atomic.Value(i64),
        write_index: std.atomic.Value(usize),
        read_index: std.atomic.Value(usize),

        pub fn init() Self {
            var buffer: [capacity]std.atomic.Value(i64) = undefined;
            for (&buffer) |*slot| {
                slot.* = std.atomic.Value(i64).init(0);
            }
            return .{
                .buffer = buffer,
                .write_index = std.atomic.Value(usize).init(0),
                .read_index = std.atomic.Value(usize).init(0),
            };
        }

        pub fn store(self: *Self, value: i64, order: MemoryOrder) bool {
            const wi = self.write_index.load(.acquire);
            const ri = self.read_index.load(.acquire);

            if ((wi + 1) % capacity == ri) {
                return false; // Buffer full
            }

            self.buffer[wi].store(value, order.toStd());
            self.write_index.store((wi + 1) % capacity, .release);
            return true;
        }

        pub fn load(self: *Self, order: MemoryOrder) ?i64 {
            const ri = self.read_index.load(.acquire);
            const wi = self.write_index.load(.acquire);

            if (ri == wi) {
                return null; // Buffer empty
            }

            const value = self.buffer[ri].load(order.toStd());
            self.read_index.store((ri + 1) % capacity, .release);
            return value;
        }

        pub fn available(self: *const Self) usize {
            const wi = self.write_index.load(.acquire);
            const ri = self.read_index.load(.acquire);
            if (wi >= ri) {
                return wi - ri;
            }
            return capacity - ri + wi;
        }
    };
}

/// Memory visibility tester
pub const VisibilityTester = struct {
    const Self = @This();

    shared_var: std.atomic.Value(i64),
    observer_count: std.atomic.Value(usize),
    observed_values: [16]std.atomic.Value(i64),

    pub fn init() Self {
        var observed: [16]std.atomic.Value(i64) = undefined;
        for (&observed) |*slot| {
            slot.* = std.atomic.Value(i64).init(0);
        }
        return .{
            .shared_var = std.atomic.Value(i64).init(0),
            .observer_count = std.atomic.Value(usize).init(0),
            .observed_values = observed,
        };
    }

    pub fn write(self: *Self, value: i64, order: MemoryOrder) void {
        self.shared_var.store(value, order.toStd());
    }

    pub fn read(self: *Self, order: MemoryOrder) i64 {
        return self.shared_var.load(order.toStd());
    }

    pub fn observe(self: *Self, order: MemoryOrder) void {
        const idx = self.observer_count.fetchAdd(1, .monotonic);
        if (idx < 16) {
            const value = self.shared_var.load(order.toStd());
            self.observed_values[idx].store(value, .release);
        }
    }

    pub fn getObservedValues(self: *const Self) []const i64 {
        const count = @min(self.observer_count.load(.acquire), 16);
        var result: [16]i64 = undefined;
        for (0..count) |i| {
            result[i] = self.observed_values[i].load(.acquire);
        }
        return result[0..count];
    }
};

/// Happens-before relationship tracker
pub const HappensBefore = struct {
    const Self = @This();
    const MAX_EVENTS = 64;

    events: [MAX_EVENTS]std.atomic.Value(i64),
    event_count: std.atomic.Value(usize),
    clock: std.atomic.Value(i64),

    pub fn init() Self {
        var events: [MAX_EVENTS]std.atomic.Value(i64) = undefined;
        for (&events) |*e| {
            e.* = std.atomic.Value(i64).init(0);
        }
        return .{
            .events = events,
            .event_count = std.atomic.Value(usize).init(0),
            .clock = std.atomic.Value(i64).init(0),
        };
    }

    pub fn recordEvent(self: *Self) usize {
        const timestamp = self.clock.fetchAdd(1, .seq_cst);
        const idx = self.event_count.fetchAdd(1, .seq_cst);
        if (idx < MAX_EVENTS) {
            self.events[idx].store(timestamp, .release);
        }
        return idx;
    }

    pub fn happensBefore(self: *const Self, event_a: usize, event_b: usize) bool {
        if (event_a >= MAX_EVENTS or event_b >= MAX_EVENTS) {
            return false;
        }
        const time_a = self.events[event_a].load(.acquire);
        const time_b = self.events[event_b].load(.acquire);
        return time_a < time_b;
    }

    pub fn synchronizeWith(self: *Self, other: *Self) void {
        const my_clock = self.clock.load(.acquire);
        var other_clock = other.clock.load(.acquire);

        while (other_clock < my_clock) {
            const result = other.clock.cmpxchgWeak(other_clock, my_clock, .release, .acquire);
            if (result) |new_clock| {
                other_clock = new_clock;
            } else {
                break;
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "atomic_flag_basic" {
    var flag = AtomicFlag.init(false);

    try std.testing.expect(!flag.load(.relaxed));

    flag.set(.release);
    try std.testing.expect(flag.load(.acquire));

    flag.clear(.release);
    try std.testing.expect(!flag.load(.acquire));
}

test "atomic_flag_test_and_set" {
    var flag = AtomicFlag.init(false);

    try std.testing.expect(!flag.testAndSet(.seq_cst));
    try std.testing.expect(flag.testAndSet(.seq_cst));

    const stats = flag.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.sets);
}

test "message_passing_basic" {
    var mp = MessagePassing(i32).init(0);

    try std.testing.expect(mp.receive() == null);

    mp.send(42);
    try std.testing.expectEqual(@as(?i32, 42), mp.receive());
}

test "message_passing_wait" {
    var mp = MessagePassing(i32).init(0);

    // Should timeout since nothing sent
    try std.testing.expect(mp.waitAndReceive(1_000) == null);

    mp.send(123);
    try std.testing.expectEqual(@as(?i32, 123), mp.waitAndReceive(1_000_000));
}

test "seqlock_basic" {
    var lock = SeqLock.init();

    const seq1 = lock.readBegin();
    try std.testing.expect(!lock.readRetry(seq1));

    lock.writeBegin();
    lock.writeEnd();

    // After write, sequence should have changed
    const seq2 = lock.readBegin();
    try std.testing.expect(seq2 != seq1);
}

test "double_checked_init_basic" {
    var dci = DoubleCheckedInit(i32).init();

    try std.testing.expect(!dci.isInitialized());

    const val = dci.get(struct {
        fn init() i32 {
            return 42;
        }
    }.init);

    try std.testing.expectEqual(@as(i32, 42), val);
    try std.testing.expect(dci.isInitialized());
    try std.testing.expectEqual(@as(usize, 1), dci.getInitAttempts());
}

test "double_checked_init_idempotent" {
    var dci = DoubleCheckedInit(i32).init();

    const val1 = dci.get(struct {
        fn init() i32 {
            return 100;
        }
    }.init);

    const val2 = dci.get(struct {
        fn init() i32 {
            return 200;
        }
    }.init);

    try std.testing.expectEqual(@as(i32, 100), val1);
    try std.testing.expectEqual(@as(i32, 100), val2);
    try std.testing.expectEqual(@as(usize, 1), dci.getInitAttempts());
}

test "store_buffer_basic" {
    var buf = StoreBuffer(8).init();

    try std.testing.expect(buf.store(1, .release));
    try std.testing.expect(buf.store(2, .release));
    try std.testing.expect(buf.store(3, .release));

    try std.testing.expectEqual(@as(usize, 3), buf.available());

    try std.testing.expectEqual(@as(?i64, 1), buf.load(.acquire));
    try std.testing.expectEqual(@as(?i64, 2), buf.load(.acquire));
    try std.testing.expectEqual(@as(?i64, 3), buf.load(.acquire));
    try std.testing.expectEqual(@as(?i64, null), buf.load(.acquire));
}

test "visibility_tester_basic" {
    var vt = VisibilityTester.init();

    vt.write(42, .release);
    try std.testing.expectEqual(@as(i64, 42), vt.read(.acquire));

    vt.observe(.acquire);
    vt.observe(.acquire);

    try std.testing.expectEqual(@as(usize, 2), vt.observer_count.load(.acquire));
}

test "happens_before_basic" {
    var hb = HappensBefore.init();

    const e1 = hb.recordEvent();
    const e2 = hb.recordEvent();
    const e3 = hb.recordEvent();

    try std.testing.expect(hb.happensBefore(e1, e2));
    try std.testing.expect(hb.happensBefore(e2, e3));
    try std.testing.expect(hb.happensBefore(e1, e3));
    try std.testing.expect(!hb.happensBefore(e3, e1));
}

test "memory_barrier_fence" {
    MemoryBarrier.acquireFence();
    MemoryBarrier.releaseFence();
    MemoryBarrier.seqCstFence();
    MemoryBarrier.compilerFence();
}

test "message_passing_multithread" {
    var mp = MessagePassing(i64).init(0);

    var sender = std.Thread.spawn(.{}, struct {
        fn run(m: *MessagePassing(i64)) void {
            std.time.sleep(100_000); // 100us
            m.send(999);
        }
    }.run, .{&mp}) catch unreachable;

    const result = mp.waitAndReceive(10_000_000_000);
    sender.join();

    try std.testing.expectEqual(@as(?i64, 999), result);
}

test "seqlock_multithread" {
    const Data = struct {
        a: i64,
        b: i64,
    };

    var lock = SeqLock.init();
    var data = Data{ .a = 0, .b = 0 };
    var reads_valid = std.atomic.Value(usize).init(0);

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(l: *SeqLock, d: *Data, valid: *std.atomic.Value(usize)) void {
                for (0..100) |_| {
                    var a: i64 = undefined;
                    var b: i64 = undefined;

                    while (true) {
                        const seq = l.readBegin();
                        a = d.a;
                        b = d.b;
                        if (!l.readRetry(seq)) break;
                    }

                    // Values should always match
                    if (a == b) {
                        _ = valid.fetchAdd(1, .monotonic);
                    }
                }
            }
        }.run, .{ &lock, &data, &reads_valid }) catch unreachable;
    }

    // Writer thread
    for (0..50) |i| {
        lock.writeBegin();
        data.a = @intCast(i);
        data.b = @intCast(i);
        lock.writeEnd();
        std.atomic.spinLoopHint();
    }

    for (&threads) |*t| {
        t.join();
    }

    // All reads should have been valid
    try std.testing.expectEqual(@as(usize, num_threads * 100), reads_valid.load(.acquire));
}
