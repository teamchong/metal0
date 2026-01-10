//! test.test_free_threading.test_containers - Thread-safe containers
//!
//! This module provides thread-safe container implementations for free-threaded
//! Python execution. It includes concurrent queues, stacks, and other data
//! structures that can be safely accessed from multiple threads.
const std = @import("std");

/// A lock-free bounded queue using atomic operations
pub fn ConcurrentQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]?T,
        head: std.atomic.Value(usize),
        tail: std.atomic.Value(usize),
        size: std.atomic.Value(usize),

        pub fn init() Self {
            return .{
                .buffer = [_]?T{null} ** capacity,
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
                .size = std.atomic.Value(usize).init(0),
            };
        }

        pub fn push(self: *Self, item: T) bool {
            while (true) {
                const current_size = self.size.load(.acquire);
                if (current_size >= capacity) {
                    return false; // Queue is full
                }

                const current_tail = self.tail.load(.acquire);
                const next_tail = (current_tail + 1) % capacity;

                if (self.tail.cmpxchgWeak(current_tail, next_tail, .release, .acquire)) |_| {
                    continue; // Retry
                }

                self.buffer[current_tail] = item;
                _ = self.size.fetchAdd(1, .release);
                return true;
            }
        }

        pub fn pop(self: *Self) ?T {
            while (true) {
                const current_size = self.size.load(.acquire);
                if (current_size == 0) {
                    return null; // Queue is empty
                }

                const current_head = self.head.load(.acquire);
                const next_head = (current_head + 1) % capacity;

                if (self.head.cmpxchgWeak(current_head, next_head, .release, .acquire)) |_| {
                    continue; // Retry
                }

                const item = self.buffer[current_head];
                self.buffer[current_head] = null;
                _ = self.size.fetchSub(1, .release);
                return item;
            }
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.size.load(.acquire) == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.size.load(.acquire) >= capacity;
        }

        pub fn len(self: *const Self) usize {
            return self.size.load(.acquire);
        }
    };
}

/// Thread-safe stack using a mutex
pub fn ConcurrentStack(comptime T: type) type {
    return struct {
        const Self = @This();

        items: std.ArrayList(T),
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.items.deinit();
        }

        pub fn push(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(item);
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.popOrNull();
        }

        pub fn peek(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.items.items.len == 0) return null;
            return self.items.items[self.items.items.len - 1];
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.len() == 0;
        }
    };
}

/// Thread-safe set using read-write lock for better concurrent read performance
pub fn ConcurrentSet(comptime T: type) type {
    return struct {
        const Self = @This();
        const SetMap = std.AutoHashMap(T, void);

        map: SetMap,
        rwlock: std.Thread.RwLock,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .map = SetMap.init(allocator),
                .rwlock = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.map.deinit();
        }

        pub fn add(self: *Self, item: T) !void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            try self.map.put(item, {});
        }

        pub fn remove(self: *Self, item: T) bool {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            return self.map.remove(item);
        }

        pub fn contains(self: *Self, item: T) bool {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.map.contains(item);
        }

        pub fn len(self: *Self) usize {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.map.count();
        }
    };
}

/// A simple ring buffer for bounded producer-consumer scenarios
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        data: [capacity]T,
        read_pos: std.atomic.Value(usize),
        write_pos: std.atomic.Value(usize),

        pub fn init() Self {
            return .{
                .data = undefined,
                .read_pos = std.atomic.Value(usize).init(0),
                .write_pos = std.atomic.Value(usize).init(0),
            };
        }

        pub fn write(self: *Self, item: T) bool {
            const write_pos = self.write_pos.load(.acquire);
            const read_pos = self.read_pos.load(.acquire);
            const next_write = (write_pos + 1) % capacity;

            if (next_write == read_pos) {
                return false; // Buffer full
            }

            self.data[write_pos] = item;
            self.write_pos.store(next_write, .release);
            return true;
        }

        pub fn read(self: *Self) ?T {
            const read_pos = self.read_pos.load(.acquire);
            const write_pos = self.write_pos.load(.acquire);

            if (read_pos == write_pos) {
                return null; // Buffer empty
            }

            const item = self.data[read_pos];
            const next_read = (read_pos + 1) % capacity;
            self.read_pos.store(next_read, .release);
            return item;
        }

        pub fn available(self: *const Self) usize {
            const write_pos = self.write_pos.load(.acquire);
            const read_pos = self.read_pos.load(.acquire);
            if (write_pos >= read_pos) {
                return write_pos - read_pos;
            }
            return capacity - read_pos + write_pos;
        }
    };
}

/// Thread-safe object pool for reusing allocations
pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();

        free_list: std.ArrayList(*T),
        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex,
        total_allocated: std.atomic.Value(usize),
        total_reused: std.atomic.Value(usize),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .free_list = std.ArrayList(*T).init(allocator),
                .allocator = allocator,
                .mutex = .{},
                .total_allocated = std.atomic.Value(usize).init(0),
                .total_reused = std.atomic.Value(usize).init(0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            for (self.free_list.items) |ptr| {
                self.allocator.destroy(ptr);
            }
            self.free_list.deinit();
        }

        pub fn acquire(self: *Self) !*T {
            self.mutex.lock();
            if (self.free_list.popOrNull()) |ptr| {
                self.mutex.unlock();
                _ = self.total_reused.fetchAdd(1, .monotonic);
                return ptr;
            }
            self.mutex.unlock();

            const ptr = try self.allocator.create(T);
            _ = self.total_allocated.fetchAdd(1, .monotonic);
            return ptr;
        }

        pub fn release(self: *Self, ptr: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.free_list.append(ptr) catch {
                self.allocator.destroy(ptr);
            };
        }

        pub fn stats(self: *const Self) struct { allocated: usize, reused: usize } {
            return .{
                .allocated = self.total_allocated.load(.acquire),
                .reused = self.total_reused.load(.acquire),
            };
        }
    };
}

/// Work-stealing deque for parallel work distribution
pub fn WorkStealingDeque(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]?T,
        top: std.atomic.Value(isize),
        bottom: std.atomic.Value(isize),

        pub fn init() Self {
            return .{
                .buffer = [_]?T{null} ** capacity,
                .top = std.atomic.Value(isize).init(0),
                .bottom = std.atomic.Value(isize).init(0),
            };
        }

        /// Push an item to the bottom (owner thread only)
        pub fn pushBottom(self: *Self, item: T) bool {
            const b = self.bottom.load(.acquire);
            const t = self.top.load(.acquire);

            if (b - t >= @as(isize, capacity)) {
                return false; // Deque is full
            }

            const index: usize = @intCast(@mod(b, capacity));
            self.buffer[index] = item;
            std.atomic.fence(.release);
            self.bottom.store(b + 1, .release);
            return true;
        }

        /// Pop an item from the bottom (owner thread only)
        pub fn popBottom(self: *Self) ?T {
            var b = self.bottom.load(.acquire);
            b -= 1;
            self.bottom.store(b, .release);
            std.atomic.fence(.seq_cst);

            const t = self.top.load(.acquire);

            if (t <= b) {
                const index: usize = @intCast(@mod(b, capacity));
                const item = self.buffer[index];
                if (t == b) {
                    if (self.top.cmpxchgStrong(t, t + 1, .seq_cst, .acquire)) |_| {
                        self.bottom.store(t + 1, .release);
                        return null;
                    }
                    self.bottom.store(t + 1, .release);
                }
                return item;
            }

            self.bottom.store(t, .release);
            return null;
        }

        /// Steal an item from the top (other threads)
        pub fn steal(self: *Self) ?T {
            const t = self.top.load(.acquire);
            std.atomic.fence(.seq_cst);
            const b = self.bottom.load(.acquire);

            if (t < b) {
                const index: usize = @intCast(@mod(t, capacity));
                const item = self.buffer[index];

                if (self.top.cmpxchgStrong(t, t + 1, .seq_cst, .acquire)) |_| {
                    return null; // Lost the race
                }

                return item;
            }

            return null;
        }

        pub fn isEmpty(self: *const Self) bool {
            const t = self.top.load(.acquire);
            const b = self.bottom.load(.acquire);
            return t >= b;
        }
    };
}

/// Concurrent counter with per-thread buckets for reduced contention
pub const ShardedCounter = struct {
    const SHARD_COUNT = 16;

    shards: [SHARD_COUNT]std.atomic.Value(i64),

    pub fn init() ShardedCounter {
        var shards: [SHARD_COUNT]std.atomic.Value(i64) = undefined;
        for (&shards) |*shard| {
            shard.* = std.atomic.Value(i64).init(0);
        }
        return .{ .shards = shards };
    }

    fn getShardIndex() usize {
        // Use thread ID to pick a shard
        const tid = std.Thread.getCurrentId();
        return @intCast(tid % SHARD_COUNT);
    }

    pub fn add(self: *ShardedCounter, delta: i64) void {
        const idx = getShardIndex();
        _ = self.shards[idx].fetchAdd(delta, .monotonic);
    }

    pub fn increment(self: *ShardedCounter) void {
        self.add(1);
    }

    pub fn decrement(self: *ShardedCounter) void {
        self.add(-1);
    }

    pub fn get(self: *const ShardedCounter) i64 {
        var total: i64 = 0;
        for (&self.shards) |*shard| {
            total += shard.load(.acquire);
        }
        return total;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "concurrent_queue_basic" {
    var queue = ConcurrentQueue(i32, 8).init();

    try std.testing.expect(queue.push(1));
    try std.testing.expect(queue.push(2));
    try std.testing.expect(queue.push(3));

    try std.testing.expectEqual(@as(usize, 3), queue.len());

    try std.testing.expectEqual(@as(?i32, 1), queue.pop());
    try std.testing.expectEqual(@as(?i32, 2), queue.pop());
    try std.testing.expectEqual(@as(?i32, 3), queue.pop());
    try std.testing.expectEqual(@as(?i32, null), queue.pop());
}

test "concurrent_queue_full" {
    var queue = ConcurrentQueue(i32, 4).init();

    try std.testing.expect(queue.push(1));
    try std.testing.expect(queue.push(2));
    try std.testing.expect(queue.push(3));
    try std.testing.expect(queue.push(4));
    try std.testing.expect(!queue.push(5)); // Should fail - queue full
    try std.testing.expect(queue.isFull());
}

test "concurrent_stack_operations" {
    const allocator = std.testing.allocator;
    var stack = ConcurrentStack(i32).init(allocator);
    defer stack.deinit();

    try stack.push(10);
    try stack.push(20);
    try stack.push(30);

    try std.testing.expectEqual(@as(usize, 3), stack.len());
    try std.testing.expectEqual(@as(?i32, 30), stack.peek());
    try std.testing.expectEqual(@as(?i32, 30), stack.pop());
    try std.testing.expectEqual(@as(?i32, 20), stack.pop());
    try std.testing.expectEqual(@as(?i32, 10), stack.pop());
    try std.testing.expect(stack.isEmpty());
}

test "concurrent_set_operations" {
    const allocator = std.testing.allocator;
    var set = ConcurrentSet(i32).init(allocator);
    defer set.deinit();

    try set.add(1);
    try set.add(2);
    try set.add(3);

    try std.testing.expect(set.contains(1));
    try std.testing.expect(set.contains(2));
    try std.testing.expect(!set.contains(4));

    try std.testing.expect(set.remove(2));
    try std.testing.expect(!set.contains(2));
}

test "ring_buffer_basic" {
    var rb = RingBuffer(i32, 4).init();

    try std.testing.expect(rb.write(1));
    try std.testing.expect(rb.write(2));
    try std.testing.expect(rb.write(3));
    try std.testing.expect(!rb.write(4)); // Buffer full (capacity - 1)

    try std.testing.expectEqual(@as(?i32, 1), rb.read());
    try std.testing.expectEqual(@as(?i32, 2), rb.read());
    try std.testing.expectEqual(@as(?i32, 3), rb.read());
    try std.testing.expectEqual(@as(?i32, null), rb.read());
}

test "object_pool_basic" {
    const allocator = std.testing.allocator;
    var pool = ObjectPool(u64).init(allocator);
    defer pool.deinit();

    const obj1 = try pool.acquire();
    obj1.* = 42;

    const obj2 = try pool.acquire();
    obj2.* = 99;

    pool.release(obj1);
    pool.release(obj2);

    // Reuse from pool
    const obj3 = try pool.acquire();
    const obj4 = try pool.acquire();

    pool.release(obj3);
    pool.release(obj4);

    const s = pool.stats();
    try std.testing.expectEqual(@as(usize, 2), s.allocated);
    try std.testing.expectEqual(@as(usize, 2), s.reused);
}

test "work_stealing_deque_basic" {
    var deque = WorkStealingDeque(i32, 8).init();

    try std.testing.expect(deque.pushBottom(1));
    try std.testing.expect(deque.pushBottom(2));
    try std.testing.expect(deque.pushBottom(3));

    // Pop from bottom (LIFO for owner)
    try std.testing.expectEqual(@as(?i32, 3), deque.popBottom());

    // Steal from top (FIFO for thieves)
    try std.testing.expectEqual(@as(?i32, 1), deque.steal());

    // Remaining item
    try std.testing.expectEqual(@as(?i32, 2), deque.popBottom());
    try std.testing.expect(deque.isEmpty());
}

test "sharded_counter_basic" {
    var counter = ShardedCounter.init();

    counter.increment();
    counter.increment();
    counter.increment();
    counter.decrement();

    try std.testing.expectEqual(@as(i64, 2), counter.get());

    counter.add(10);
    try std.testing.expectEqual(@as(i64, 12), counter.get());
}

test "concurrent_queue_multithread" {
    var queue = ConcurrentQueue(usize, 1024).init();
    const num_threads = 4;
    const items_per_thread = 100;
    var threads: [num_threads]std.Thread = undefined;
    var produced = std.atomic.Value(usize).init(0);

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(q: *ConcurrentQueue(usize, 1024), p: *std.atomic.Value(usize), start: usize) void {
                for (0..items_per_thread) |j| {
                    while (!q.push(start * items_per_thread + j)) {
                        std.atomic.spinLoopHint();
                    }
                    _ = p.fetchAdd(1, .monotonic);
                }
            }
        }.run, .{ &queue, &produced, i }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    try std.testing.expectEqual(@as(usize, num_threads * items_per_thread), produced.load(.acquire));
    try std.testing.expectEqual(@as(usize, num_threads * items_per_thread), queue.len());
}
