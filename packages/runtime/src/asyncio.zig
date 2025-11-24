/// Python asyncio module implementation
/// Simplified for AOT - Queue only, no full async/await
const std = @import("std");

/// Placeholder stubs for async functions (not fully implemented)
pub fn run(allocator: std.mem.Allocator, coro: anytype) !void {
    _ = allocator;
    _ = coro;
}

pub fn sleep(seconds: f64) !void {
    _ = seconds;
}

pub fn createTask(allocator: std.mem.Allocator, coro: anytype) !void {
    _ = allocator;
    _ = coro;
}

pub fn gather(tasks: anytype) !void {
    _ = tasks;
}

/// asyncio.Queue - Simplified synchronous queue for AOT compilation
pub fn Queue(comptime T: type) type {
    return struct {
        buffer: []T,
        capacity: usize,
        head: usize,
        tail: usize,
        size: usize,
        allocator: std.mem.Allocator,

        const Self = @This();

        /// Create queue with maxsize
        pub fn init(allocator: std.mem.Allocator, maxsize: usize) !*Self {
            const self = try allocator.create(Self);
            const buf = try allocator.alloc(T, maxsize);
            self.* = Self{
                .buffer = buf,
                .capacity = maxsize,
                .head = 0,
                .tail = 0,
                .size = 0,
                .allocator = allocator,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
            self.allocator.destroy(self);
        }

        /// Non-blocking put
        pub fn put_nowait(self: *Self, item: T) !void {
            if (self.size >= self.capacity) return error.QueueFull;
            self.buffer[self.tail] = item;
            self.tail = (self.tail + 1) % self.capacity;
            self.size += 1;
        }

        /// Non-blocking get
        pub fn get_nowait(self: *Self) !T {
            if (self.size == 0) return error.QueueEmpty;
            const item = self.buffer[self.head];
            self.head = (self.head + 1) % self.capacity;
            self.size -= 1;
            return item;
        }

        /// Check if queue is empty
        pub fn empty(self: *Self) bool {
            return self.size == 0;
        }

        /// Check if queue is full
        pub fn full(self: *Self) bool {
            return self.size >= self.capacity;
        }

        /// Get current queue size
        pub fn qsize(self: *Self) usize {
            return self.size;
        }
    };
}

// Tests
test "asyncio.Queue basic" {
    const testing = std.testing;
    const IntQueue = Queue(i64);

    var queue = try IntQueue.init(testing.allocator, 10);
    defer queue.deinit();

    try testing.expect(queue.empty());
    try testing.expect(!queue.full());
    try testing.expectEqual(@as(usize, 0), queue.qsize());

    // Put/get
    try queue.put_nowait(42);
    try testing.expectEqual(@as(usize, 1), queue.qsize());

    const val = try queue.get_nowait();
    try testing.expectEqual(@as(i64, 42), val);
    try testing.expect(queue.empty());
}
