//! Queue - Inter-process communication queue
const std = @import("std");

/// A process-safe queue with blocking support via condition variables
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        items: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,
        maxsize: usize,
        closed: bool,

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                .items = std.ArrayList(T){},
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .maxsize = maxsize,
                .closed = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        /// Put an item into the queue with optional blocking
        pub fn put(self: *Self, item: T, block: bool, timeout: ?f64) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed) return error.QueueClosed;

            // Wait for space if queue is full and blocking requested
            while (self.maxsize > 0 and self.items.items.len >= self.maxsize) {
                if (!block) return error.QueueFull;

                // Block with optional timeout
                if (timeout) |t| {
                    const timeout_ns: u64 = @intFromFloat(t * std.time.ns_per_s);
                    const result = self.not_full.timedWait(&self.mutex, timeout_ns);
                    if (result == .timed_out) return error.QueueFull;
                } else {
                    self.not_full.wait(&self.mutex);
                }

                if (self.closed) return error.QueueClosed;
            }

            try self.items.append(self.allocator, item);
            // Signal that queue is not empty
            self.not_empty.signal();
        }

        /// Put without blocking
        pub fn putNowait(self: *Self, item: T) !void {
            return self.put(item, false, null);
        }

        /// Get an item from the queue with optional blocking
        pub fn get(self: *Self, block: bool, timeout: ?f64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait for item if queue is empty and blocking requested
            while (self.items.items.len == 0) {
                if (!block) return error.QueueEmpty;

                // Block with optional timeout
                if (timeout) |t| {
                    const timeout_ns: u64 = @intFromFloat(t * std.time.ns_per_s);
                    const result = self.not_empty.timedWait(&self.mutex, timeout_ns);
                    if (result == .timed_out) return error.QueueEmpty;
                } else {
                    self.not_empty.wait(&self.mutex);
                }

                if (self.closed) return error.QueueClosed;
            }

            const item = self.items.orderedRemove(0);
            // Signal that queue is not full
            self.not_full.signal();
            return item;
        }

        /// Get without blocking
        pub fn getNowait(self: *Self) !T {
            return self.get(false, null);
        }

        /// Check if queue is empty
        pub fn empty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len == 0;
        }

        /// Check if queue is full
        pub fn full(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.maxsize > 0 and self.items.items.len >= self.maxsize;
        }

        /// Get approximate queue size
        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        /// Close the queue
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.closed = true;
        }

        /// Join queue (wait for all tasks to complete)
        pub fn joinQueue(self: *Self) void {
            while (!self.empty()) {
                std.Thread.sleep(1_000_000); // 1ms
            }
        }
    };
}

/// Simple queue (non-generic, for compatibility)
pub const SimpleQueue = Queue([]const u8);

/// Joinable queue
pub fn JoinableQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        queue: Queue(T),
        unfinished_tasks: usize,
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .queue = Queue(T).init(allocator, maxsize),
                .unfinished_tasks = 0,
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        pub fn put(self: *Self, item: T, block: bool, timeout: ?f64) !void {
            try self.queue.put(item, block, timeout);
            self.mutex.lock();
            defer self.mutex.unlock();
            self.unfinished_tasks += 1;
        }

        pub fn get(self: *Self, block: bool, timeout: ?f64) !T {
            return self.queue.get(block, timeout);
        }

        pub fn taskDone(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.unfinished_tasks > 0) {
                self.unfinished_tasks -= 1;
            }
        }

        pub fn join(self: *Self) void {
            while (true) {
                self.mutex.lock();
                const tasks = self.unfinished_tasks;
                self.mutex.unlock();
                if (tasks == 0) break;
                std.Thread.sleep(1_000_000); // 1ms
            }
        }
    };
}
