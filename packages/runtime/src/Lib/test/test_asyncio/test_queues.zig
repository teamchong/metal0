//! test.test_asyncio.test_queues - Tests for asyncio Queue classes
//! Reference: cpython/Lib/test/test_asyncio/test_queues.py
//!
//! Tests for Queue, PriorityQueue, LifoQueue

const std = @import("std");
const utils = @import("utils.zig");

// ============================================================================
// Queue Implementation for Testing
// ============================================================================

/// Queue errors
pub const QueueEmpty = error.QueueEmpty;
pub const QueueFull = error.QueueFull;
pub const QueueShutDown = error.QueueShutDown;

/// A FIFO queue for asyncio
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        _maxsize: usize,
        _queue: std.ArrayList(T),
        _getters: std.ArrayList(*Waiter),
        _putters: std.ArrayList(*Waiter),
        _unfinished_tasks: usize = 0,
        _finished: bool = true,
        _is_shutdown: bool = false,

        pub const Waiter = struct {
            resolved: bool = false,
            item: ?T = null,
        };

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                ._maxsize = maxsize,
                ._queue = std.ArrayList(T).init(allocator),
                ._getters = std.ArrayList(*Waiter).init(allocator),
                ._putters = std.ArrayList(*Waiter).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self._queue.deinit();
            self._getters.deinit();
            self._putters.deinit();
        }

        pub fn maxsize(self: *const Self) usize {
            return self._maxsize;
        }

        pub fn qsize(self: *const Self) usize {
            return self._queue.items.len;
        }

        pub fn empty(self: *const Self) bool {
            return self._queue.items.len == 0;
        }

        pub fn full(self: *const Self) bool {
            if (self._maxsize == 0) return false;
            return self._queue.items.len >= self._maxsize;
        }

        /// Put an item into the queue (blocking)
        pub fn put(self: *Self, item: T) !void {
            if (self._is_shutdown) {
                return QueueShutDown;
            }

            while (self.full()) {
                var waiter = Waiter{};
                try self._putters.append(&waiter);
                while (!waiter.resolved and !self._is_shutdown) {
                    std.atomic.spinLoopHint();
                }
                if (self._is_shutdown) {
                    return QueueShutDown;
                }
            }

            try self.put_nowait(item);
        }

        /// Put an item without blocking
        pub fn put_nowait(self: *Self, item: T) !void {
            if (self._is_shutdown) {
                return QueueShutDown;
            }
            if (self.full()) {
                return QueueFull;
            }

            try self._queue.append(item);
            self._unfinished_tasks += 1;
            self._finished = false;

            // Wake a getter if waiting
            if (self._getters.items.len > 0) {
                const waiter = self._getters.orderedRemove(0);
                waiter.resolved = true;
            }
        }

        /// Get an item from the queue (blocking)
        pub fn get(self: *Self) !T {
            while (self.empty()) {
                if (self._is_shutdown) {
                    return QueueShutDown;
                }
                var waiter = Waiter{};
                try self._getters.append(&waiter);
                while (!waiter.resolved and !self._is_shutdown) {
                    std.atomic.spinLoopHint();
                }
                if (self._is_shutdown and self.empty()) {
                    return QueueShutDown;
                }
            }

            return self.get_nowait();
        }

        /// Get an item without blocking
        pub fn get_nowait(self: *Self) !T {
            if (self.empty()) {
                if (self._is_shutdown) {
                    return QueueShutDown;
                }
                return QueueEmpty;
            }

            const item = self._queue.orderedRemove(0);

            // Wake a putter if waiting
            if (self._putters.items.len > 0) {
                const waiter = self._putters.orderedRemove(0);
                waiter.resolved = true;
            }

            return item;
        }

        /// Mark a task as done
        pub fn task_done(self: *Self) void {
            if (self._unfinished_tasks == 0) {
                @panic("task_done() called too many times");
            }
            self._unfinished_tasks -= 1;
            if (self._unfinished_tasks == 0) {
                self._finished = true;
            }
        }

        /// Wait for all tasks to complete
        pub fn join(self: *Self) !void {
            while (!self._finished) {
                std.atomic.spinLoopHint();
            }
        }

        /// Shut down the queue
        pub fn shutdown(self: *Self, immediate: bool) void {
            self._is_shutdown = true;

            if (immediate) {
                self._queue.clearRetainingCapacity();
                self._unfinished_tasks = 0;
                self._finished = true;
            }

            // Wake all waiters
            for (self._getters.items) |waiter| {
                waiter.resolved = true;
            }
            self._getters.clearRetainingCapacity();

            for (self._putters.items) |waiter| {
                waiter.resolved = true;
            }
            self._putters.clearRetainingCapacity();
        }
    };
}

/// A priority queue (min-heap)
pub fn PriorityQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        const Compare = fn (T, T) std.math.Order;

        allocator: std.mem.Allocator,
        _maxsize: usize,
        _heap: std.PriorityQueue(T, void, defaultCompare),
        _getters: std.ArrayList(*Queue(T).Waiter),
        _putters: std.ArrayList(*Queue(T).Waiter),
        _unfinished_tasks: usize = 0,
        _finished: bool = true,
        _is_shutdown: bool = false,

        fn defaultCompare(_: void, a: T, b: T) std.math.Order {
            return std.math.order(a, b);
        }

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                ._maxsize = maxsize,
                ._heap = std.PriorityQueue(T, void, defaultCompare).init(allocator, {}),
                ._getters = std.ArrayList(*Queue(T).Waiter).init(allocator),
                ._putters = std.ArrayList(*Queue(T).Waiter).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self._heap.deinit();
            self._getters.deinit();
            self._putters.deinit();
        }

        pub fn qsize(self: *const Self) usize {
            return self._heap.count();
        }

        pub fn empty(self: *const Self) bool {
            return self._heap.count() == 0;
        }

        pub fn full(self: *const Self) bool {
            if (self._maxsize == 0) return false;
            return self._heap.count() >= self._maxsize;
        }

        pub fn put_nowait(self: *Self, item: T) !void {
            if (self._is_shutdown) return QueueShutDown;
            if (self.full()) return QueueFull;
            try self._heap.add(item);
            self._unfinished_tasks += 1;
            self._finished = false;

            if (self._getters.items.len > 0) {
                const waiter = self._getters.orderedRemove(0);
                waiter.resolved = true;
            }
        }

        pub fn get_nowait(self: *Self) !T {
            if (self.empty()) {
                if (self._is_shutdown) return QueueShutDown;
                return QueueEmpty;
            }
            const item = self._heap.remove();

            if (self._putters.items.len > 0) {
                const waiter = self._putters.orderedRemove(0);
                waiter.resolved = true;
            }

            return item;
        }

        pub fn task_done(self: *Self) void {
            if (self._unfinished_tasks == 0) {
                @panic("task_done() called too many times");
            }
            self._unfinished_tasks -= 1;
            if (self._unfinished_tasks == 0) {
                self._finished = true;
            }
        }
    };
}

/// A LIFO queue (stack)
pub fn LifoQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        _maxsize: usize,
        _queue: std.ArrayList(T),
        _getters: std.ArrayList(*Queue(T).Waiter),
        _putters: std.ArrayList(*Queue(T).Waiter),
        _unfinished_tasks: usize = 0,
        _finished: bool = true,
        _is_shutdown: bool = false,

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                ._maxsize = maxsize,
                ._queue = std.ArrayList(T).init(allocator),
                ._getters = std.ArrayList(*Queue(T).Waiter).init(allocator),
                ._putters = std.ArrayList(*Queue(T).Waiter).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self._queue.deinit();
            self._getters.deinit();
            self._putters.deinit();
        }

        pub fn qsize(self: *const Self) usize {
            return self._queue.items.len;
        }

        pub fn empty(self: *const Self) bool {
            return self._queue.items.len == 0;
        }

        pub fn full(self: *const Self) bool {
            if (self._maxsize == 0) return false;
            return self._queue.items.len >= self._maxsize;
        }

        pub fn put_nowait(self: *Self, item: T) !void {
            if (self._is_shutdown) return QueueShutDown;
            if (self.full()) return QueueFull;
            try self._queue.append(item);
            self._unfinished_tasks += 1;
            self._finished = false;

            if (self._getters.items.len > 0) {
                const waiter = self._getters.orderedRemove(0);
                waiter.resolved = true;
            }
        }

        pub fn get_nowait(self: *Self) !T {
            if (self.empty()) {
                if (self._is_shutdown) return QueueShutDown;
                return QueueEmpty;
            }
            // Pop from end (LIFO)
            const item = self._queue.pop();

            if (self._putters.items.len > 0) {
                const waiter = self._putters.orderedRemove(0);
                waiter.resolved = true;
            }

            return item;
        }

        pub fn task_done(self: *Self) void {
            if (self._unfinished_tasks == 0) {
                @panic("task_done() called too many times");
            }
            self._unfinished_tasks -= 1;
            if (self._unfinished_tasks == 0) {
                self._finished = true;
            }
        }
    };
}

// ============================================================================
// Test Cases
// ============================================================================

fn testQueueBasic() !void {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, 0);
    defer q.deinit();

    try std.testing.expect(q.empty());
    try std.testing.expectEqual(@as(usize, 0), q.qsize());

    try q.put_nowait(1);
    try q.put_nowait(2);
    try q.put_nowait(3);

    try std.testing.expect(!q.empty());
    try std.testing.expectEqual(@as(usize, 3), q.qsize());

    try std.testing.expectEqual(@as(i32, 1), try q.get_nowait());
    try std.testing.expectEqual(@as(i32, 2), try q.get_nowait());
    try std.testing.expectEqual(@as(i32, 3), try q.get_nowait());

    try std.testing.expect(q.empty());
}

fn testQueueMaxsize() !void {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, 2);
    defer q.deinit();

    try std.testing.expect(!q.full());
    try q.put_nowait(1);
    try std.testing.expect(!q.full());
    try q.put_nowait(2);
    try std.testing.expect(q.full());

    const err = q.put_nowait(3);
    try std.testing.expectError(QueueFull, err);
}

fn testQueueGetEmpty() !void {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, 0);
    defer q.deinit();

    const err = q.get_nowait();
    try std.testing.expectError(QueueEmpty, err);
}

fn testQueueTaskDone() !void {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, 0);
    defer q.deinit();

    try q.put_nowait(1);
    try q.put_nowait(2);

    _ = try q.get_nowait();
    q.task_done();
    _ = try q.get_nowait();
    q.task_done();

    try std.testing.expect(q._finished);
}

fn testQueueShutdown() !void {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, 0);
    defer q.deinit();

    try q.put_nowait(1);
    q.shutdown(false);

    // Can still get existing items
    try std.testing.expectEqual(@as(i32, 1), try q.get_nowait());

    // But can't put new items
    const put_err = q.put_nowait(2);
    try std.testing.expectError(QueueShutDown, put_err);
}

fn testQueueShutdownImmediate() !void {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, 0);
    defer q.deinit();

    try q.put_nowait(1);
    try q.put_nowait(2);

    q.shutdown(true);

    try std.testing.expect(q.empty());
    try std.testing.expect(q._finished);
}

fn testPriorityQueueBasic() !void {
    const allocator = std.testing.allocator;
    var q = PriorityQueue(i32).init(allocator, 0);
    defer q.deinit();

    try q.put_nowait(3);
    try q.put_nowait(1);
    try q.put_nowait(2);

    // Should come out in priority order (min first)
    try std.testing.expectEqual(@as(i32, 1), try q.get_nowait());
    try std.testing.expectEqual(@as(i32, 2), try q.get_nowait());
    try std.testing.expectEqual(@as(i32, 3), try q.get_nowait());
}

fn testLifoQueueBasic() !void {
    const allocator = std.testing.allocator;
    var q = LifoQueue(i32).init(allocator, 0);
    defer q.deinit();

    try q.put_nowait(1);
    try q.put_nowait(2);
    try q.put_nowait(3);

    // Should come out in LIFO order
    try std.testing.expectEqual(@as(i32, 3), try q.get_nowait());
    try std.testing.expectEqual(@as(i32, 2), try q.get_nowait());
    try std.testing.expectEqual(@as(i32, 1), try q.get_nowait());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "Queue basic operations" {
    try testQueueBasic();
}

test "Queue maxsize" {
    try testQueueMaxsize();
}

test "Queue get_nowait when empty" {
    try testQueueGetEmpty();
}

test "Queue task_done" {
    try testQueueTaskDone();
}

test "Queue shutdown" {
    try testQueueShutdown();
}

test "Queue shutdown immediate" {
    try testQueueShutdownImmediate();
}

test "PriorityQueue basic" {
    try testPriorityQueueBasic();
}

test "LifoQueue basic" {
    try testLifoQueueBasic();
}
