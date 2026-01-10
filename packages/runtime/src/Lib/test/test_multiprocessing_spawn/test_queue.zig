//! test.test_multiprocessing_spawn.test_queue - Multiprocessing queue tests
const std = @import("std");

/// Queue errors
pub const QueueError = error{
    Empty,
    Full,
    Closed,
    Timeout,
};

/// Thread-safe queue for multiprocessing
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        items: std.ArrayList(T),
        maxsize: ?usize,
        closed: bool = false,
        mutex: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator, maxsize: ?usize) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .maxsize = maxsize,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn put(self: *Self, item: T, block: bool, timeout: ?f64) !void {
            _ = timeout;
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed) return QueueError.Closed;

            if (self.maxsize) |max| {
                if (self.items.items.len >= max) {
                    if (!block) return QueueError.Full;
                    return QueueError.Full;
                }
            }

            try self.items.append(item);
        }

        pub fn put_nowait(self: *Self, item: T) !void {
            return self.put(item, false, null);
        }

        pub fn get(self: *Self, block: bool, timeout: ?f64) !T {
            _ = timeout;
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed and self.items.items.len == 0) {
                return QueueError.Closed;
            }

            if (self.items.items.len == 0) {
                if (!block) return QueueError.Empty;
                return QueueError.Empty;
            }

            return self.items.orderedRemove(0);
        }

        pub fn get_nowait(self: *Self) !T {
            return self.get(false, null);
        }

        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        pub fn empty(self: *Self) bool {
            return self.qsize() == 0;
        }

        pub fn full(self: *Self) bool {
            if (self.maxsize) |max| {
                return self.qsize() >= max;
            }
            return false;
        }

        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.closed = true;
        }

        pub fn join_thread(self: *Self) void {
            while (!self.empty()) {
                std.time.sleep(1_000_000);
            }
        }
    };
}

/// Simple queue (unbounded)
pub fn SimpleQueue(comptime T: type) type {
    return Queue(T);
}

/// Joinable queue with task tracking
pub fn JoinableQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        queue: Queue(T),
        unfinished_tasks: usize = 0,

        pub fn init(allocator: std.mem.Allocator, maxsize: ?usize) Self {
            return .{
                .queue = Queue(T).init(allocator, maxsize),
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        pub fn put(self: *Self, item: T, block: bool, timeout: ?f64) !void {
            try self.queue.put(item, block, timeout);
            self.unfinished_tasks += 1;
        }

        pub fn get(self: *Self, block: bool, timeout: ?f64) !T {
            return self.queue.get(block, timeout);
        }

        pub fn task_done(self: *Self) void {
            if (self.unfinished_tasks > 0) {
                self.unfinished_tasks -= 1;
            }
        }

        pub fn join(self: *Self) void {
            while (self.unfinished_tasks > 0) {
                std.time.sleep(1_000_000);
            }
        }
    };
}

test "queue basic operations" {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, 10);
    defer q.deinit();

    try std.testing.expect(q.empty());
    try std.testing.expect(!q.full());

    try q.put(1, true, null);
    try q.put(2, true, null);
    try q.put(3, true, null);

    try std.testing.expectEqual(@as(usize, 3), q.qsize());
    try std.testing.expect(!q.empty());

    const v1 = try q.get(true, null);
    try std.testing.expectEqual(@as(i32, 1), v1);

    const v2 = try q.get_nowait();
    try std.testing.expectEqual(@as(i32, 2), v2);
}

test "queue full behavior" {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, 2);
    defer q.deinit();

    try q.put(1, true, null);
    try q.put(2, true, null);
    try std.testing.expect(q.full());

    try std.testing.expectError(QueueError.Full, q.put_nowait(3));
}

test "queue close" {
    const allocator = std.testing.allocator;
    var q = Queue(i32).init(allocator, null);
    defer q.deinit();

    try q.put(1, true, null);
    q.close();

    const v = try q.get_nowait();
    try std.testing.expectEqual(@as(i32, 1), v);

    try std.testing.expectError(QueueError.Closed, q.put_nowait(2));
}

test "joinable queue" {
    const allocator = std.testing.allocator;
    var q = JoinableQueue(i32).init(allocator, null);
    defer q.deinit();

    try q.put(1, true, null);
    try q.put(2, true, null);
    try std.testing.expectEqual(@as(usize, 2), q.unfinished_tasks);

    _ = try q.get(true, null);
    q.task_done();
    try std.testing.expectEqual(@as(usize, 1), q.unfinished_tasks);
}
