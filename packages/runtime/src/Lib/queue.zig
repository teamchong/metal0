//! Python 'queue' module - A synchronized queue class
//!
//! Multi-producer, multi-consumer queues for threading.
//!
//! Mirrors: CPython Lib/queue.py

const std = @import("std");

// ============================================================================
// Queue - FIFO queue
// ============================================================================

/// Thread-safe FIFO queue
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        items: std.ArrayList(T),
        maxsize: usize,
        mutex: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                .items = std.ArrayList(T).init(allocator),
                .maxsize = maxsize,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        /// Put an item into the queue
        pub fn put(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.maxsize > 0 and self.items.items.len >= self.maxsize) {
                return error.QueueFull;
            }

            try self.items.append(item);
        }

        /// Put an item without blocking (alias for put with immediate check)
        pub fn put_nowait(self: *Self, item: T) !void {
            return self.put(item);
        }

        /// Remove and return an item from the queue
        pub fn get(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len == 0) {
                return error.QueueEmpty;
            }

            return self.items.orderedRemove(0);
        }

        /// Remove and return an item without blocking
        pub fn get_nowait(self: *Self) !T {
            return self.get();
        }

        /// Return True if the queue is empty
        pub fn empty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len == 0;
        }

        /// Return True if the queue is full
        pub fn full(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.maxsize > 0 and self.items.items.len >= self.maxsize;
        }

        /// Return the number of items in the queue
        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        /// Indicate that a formerly enqueued task is complete (stub)
        pub fn task_done(_: *Self) void {
            // Would decrement join counter
        }

        /// Block until all items have been processed (stub)
        pub fn join(_: *Self) void {
            // Would wait for join counter to reach 0
        }

        /// Clear all items
        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.items.clearRetainingCapacity();
        }
    };
}

// ============================================================================
// LifoQueue - LIFO queue (stack)
// ============================================================================

/// Thread-safe LIFO queue (stack)
pub fn LifoQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        items: std.ArrayList(T),
        maxsize: usize,
        mutex: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                .items = std.ArrayList(T).init(allocator),
                .maxsize = maxsize,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        /// Put an item into the queue
        pub fn put(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.maxsize > 0 and self.items.items.len >= self.maxsize) {
                return error.QueueFull;
            }

            try self.items.append(item);
        }

        /// Put an item without blocking
        pub fn put_nowait(self: *Self, item: T) !void {
            return self.put(item);
        }

        /// Remove and return an item from the queue (LIFO)
        pub fn get(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.items.popOrNull() orelse error.QueueEmpty;
        }

        /// Remove and return an item without blocking
        pub fn get_nowait(self: *Self) !T {
            return self.get();
        }

        /// Return True if the queue is empty
        pub fn empty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len == 0;
        }

        /// Return True if the queue is full
        pub fn full(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.maxsize > 0 and self.items.items.len >= self.maxsize;
        }

        /// Return the number of items in the queue
        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        pub fn task_done(_: *Self) void {}
        pub fn join(_: *Self) void {}

        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.items.clearRetainingCapacity();
        }
    };
}

// ============================================================================
// PriorityQueue - Heap-based priority queue
// ============================================================================

/// Thread-safe priority queue using a min-heap
pub fn PriorityQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        heap: std.PriorityQueue(T, void, defaultLessThan),
        maxsize: usize,
        mutex: std.Thread.Mutex = .{},

        fn defaultLessThan(_: void, a: T, b: T) std.math.Order {
            return std.math.order(a, b);
        }

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                .heap = std.PriorityQueue(T, void, defaultLessThan).init(allocator, {}),
                .maxsize = maxsize,
            };
        }

        pub fn deinit(self: *Self) void {
            self.heap.deinit();
        }

        /// Put an item into the queue
        pub fn put(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.maxsize > 0 and self.heap.count() >= self.maxsize) {
                return error.QueueFull;
            }

            try self.heap.add(item);
        }

        /// Put an item without blocking
        pub fn put_nowait(self: *Self, item: T) !void {
            return self.put(item);
        }

        /// Remove and return the smallest item
        pub fn get(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.heap.removeOrNull() orelse error.QueueEmpty;
        }

        /// Remove and return an item without blocking
        pub fn get_nowait(self: *Self) !T {
            return self.get();
        }

        /// Return True if the queue is empty
        pub fn empty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.heap.count() == 0;
        }

        /// Return True if the queue is full
        pub fn full(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.maxsize > 0 and self.heap.count() >= self.maxsize;
        }

        /// Return the number of items in the queue
        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.heap.count();
        }

        /// Peek at the smallest item without removing it
        pub fn peek(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.heap.peek();
        }

        pub fn task_done(_: *Self) void {}
        pub fn join(_: *Self) void {}
    };
}

// ============================================================================
// SimpleQueue - Unbounded FIFO queue
// ============================================================================

/// Unbounded FIFO queue (no maxsize)
pub fn SimpleQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        items: std.ArrayList(T),
        mutex: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .items = std.ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        /// Put an item into the queue
        pub fn put(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(item);
        }

        /// Put an item without blocking
        pub fn put_nowait(self: *Self, item: T) !void {
            return self.put(item);
        }

        /// Remove and return an item from the queue
        pub fn get(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len == 0) {
                return error.QueueEmpty;
            }

            return self.items.orderedRemove(0);
        }

        /// Remove and return an item without blocking
        pub fn get_nowait(self: *Self) !T {
            return self.get();
        }

        /// Return True if the queue is empty
        pub fn empty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len == 0;
        }

        /// Return the number of items in the queue
        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }
    };
}

// ============================================================================
// Exceptions
// ============================================================================

pub const Empty = error.QueueEmpty;
pub const Full = error.QueueFull;

// ============================================================================
// Tests
// ============================================================================

test "Queue FIFO" {
    const allocator = std.testing.allocator;

    var q = Queue(i32).init(allocator, 0);
    defer q.deinit();

    try q.put(1);
    try q.put(2);
    try q.put(3);

    try std.testing.expectEqual(@as(usize, 3), q.qsize());
    try std.testing.expectEqual(@as(i32, 1), try q.get());
    try std.testing.expectEqual(@as(i32, 2), try q.get());
    try std.testing.expectEqual(@as(i32, 3), try q.get());
    try std.testing.expect(q.empty());
}

test "Queue maxsize" {
    const allocator = std.testing.allocator;

    var q = Queue(i32).init(allocator, 2);
    defer q.deinit();

    try q.put(1);
    try q.put(2);
    try std.testing.expectError(error.QueueFull, q.put(3));
    try std.testing.expect(q.full());
}

test "LifoQueue LIFO" {
    const allocator = std.testing.allocator;

    var q = LifoQueue(i32).init(allocator, 0);
    defer q.deinit();

    try q.put(1);
    try q.put(2);
    try q.put(3);

    try std.testing.expectEqual(@as(i32, 3), try q.get());
    try std.testing.expectEqual(@as(i32, 2), try q.get());
    try std.testing.expectEqual(@as(i32, 1), try q.get());
}

test "PriorityQueue" {
    const allocator = std.testing.allocator;

    var q = PriorityQueue(i32).init(allocator, 0);
    defer q.deinit();

    try q.put(3);
    try q.put(1);
    try q.put(2);

    try std.testing.expectEqual(@as(i32, 1), try q.get());
    try std.testing.expectEqual(@as(i32, 2), try q.get());
    try std.testing.expectEqual(@as(i32, 3), try q.get());
}

test "SimpleQueue" {
    const allocator = std.testing.allocator;

    var q = SimpleQueue(i32).init(allocator);
    defer q.deinit();

    try q.put(1);
    try q.put(2);

    try std.testing.expectEqual(@as(i32, 1), try q.get());
    try std.testing.expectEqual(@as(i32, 2), try q.get());
    try std.testing.expectError(error.QueueEmpty, q.get());
}
