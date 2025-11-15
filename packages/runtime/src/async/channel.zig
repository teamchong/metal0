const std = @import("std");
const Task = @import("task.zig").Task;
const TaskState = @import("task.zig").TaskState;

/// Go-style channel for task communication
pub fn Channel(comptime T: type) type {
    return struct {
        buffer: ?[]T,
        capacity: usize,
        head: usize, // Read position
        tail: usize, // Write position
        size: usize, // Current number of items
        send_queue: TaskQueue,
        recv_queue: TaskQueue,
        mutex: std.Thread.Mutex,
        closed: std.atomic.Value(bool),
        allocator: std.mem.Allocator,

        const Self = @This();

        /// Task queue for blocked tasks
        const TaskQueue = struct {
            head: ?*QueueNode,
            tail: ?*QueueNode,
            len: usize,

            const QueueNode = struct {
                task: *Task,
                value_ptr: ?*T, // For send operations
                next: ?*QueueNode,
            };

            pub const DequeueResult = struct {
                task: *Task,
                value_ptr: ?*T,
            };

            fn init() TaskQueue {
                return TaskQueue{
                    .head = null,
                    .tail = null,
                    .len = 0,
                };
            }

            pub fn enqueue(self: *TaskQueue, allocator: std.mem.Allocator, task: *Task, value_ptr: ?*T) !void {
                const node = try allocator.create(QueueNode);
                node.* = QueueNode{
                    .task = task,
                    .value_ptr = value_ptr,
                    .next = null,
                };

                if (self.tail) |tail| {
                    tail.next = node;
                    self.tail = node;
                } else {
                    self.head = node;
                    self.tail = node;
                }
                self.len += 1;
            }

            pub fn dequeue(self: *TaskQueue, allocator: std.mem.Allocator) ?DequeueResult {
                const node = self.head orelse return null;
                self.head = node.next;
                if (self.head == null) {
                    self.tail = null;
                }
                self.len -= 1;

                const result = DequeueResult{ .task = node.task, .value_ptr = node.value_ptr };
                allocator.destroy(node);
                return result;
            }

            fn clear(self: *TaskQueue, allocator: std.mem.Allocator) void {
                while (self.dequeue(allocator)) |_| {}
            }
        };

        /// Create unbuffered channel
        pub fn init(allocator: std.mem.Allocator) !*Self {
            return initBuffered(allocator, 0);
        }

        /// Create buffered channel
        pub fn initBuffered(allocator: std.mem.Allocator, capacity: usize) !*Self {
            const chan = try allocator.create(Self);
            errdefer allocator.destroy(chan);

            chan.* = Self{
                .buffer = if (capacity > 0) try allocator.alloc(T, capacity) else null,
                .capacity = capacity,
                .head = 0,
                .tail = 0,
                .size = 0,
                .send_queue = TaskQueue.init(),
                .recv_queue = TaskQueue.init(),
                .mutex = std.Thread.Mutex{},
                .closed = std.atomic.Value(bool).init(false),
                .allocator = allocator,
            };

            return chan;
        }

        pub fn deinit(self: *Self) void {
            self.send_queue.clear(self.allocator);
            self.recv_queue.clear(self.allocator);

            if (self.buffer) |buf| {
                self.allocator.free(buf);
            }

            self.allocator.destroy(self);
        }

        /// Send value to channel
        pub fn send(self: *Self, value: T, current_task: *Task) !void {
            if (self.capacity == 0) {
                const unbuf = @import("channel/unbuffered.zig");
                return unbuf.send(self, value, current_task);
            } else {
                const buf = @import("channel/buffered.zig");
                return buf.send(self, value, current_task);
            }
        }

        /// Receive value from channel
        pub fn recv(self: *Self, current_task: *Task) !T {
            if (self.capacity == 0) {
                const unbuf = @import("channel/unbuffered.zig");
                return unbuf.recv(self, current_task);
            } else {
                const buf = @import("channel/buffered.zig");
                return buf.recv(self, current_task);
            }
        }

        /// Try send without blocking
        pub fn trySend(self: *Self, value: T) !bool {
            if (self.closed.load(.acquire)) {
                return error.ChannelClosed;
            }

            self.mutex.lock();
            defer self.mutex.unlock();

            // Check if receiver waiting
            if (self.recv_queue.dequeue(self.allocator)) |receiver| {
                // Direct handoff
                if (receiver.value_ptr) |ptr| {
                    ptr.* = value;
                }
                receiver.task.state = .runnable;
                return true;
            }

            // Try buffer
            if (self.buffer != null and self.size < self.capacity) {
                self.buffer.?[self.tail] = value;
                self.tail = (self.tail + 1) % self.capacity;
                self.size += 1;
                return true;
            }

            return false;
        }

        /// Try receive without blocking
        pub fn tryRecv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Check buffer first
            if (self.buffer != null and self.size > 0) {
                const value = self.buffer.?[self.head];
                self.head = (self.head + 1) % self.capacity;
                self.size -= 1;

                // Wake waiting sender
                if (self.send_queue.dequeue(self.allocator)) |sender| {
                    sender.task.state = .runnable;
                }

                return value;
            }

            // Check if sender waiting
            if (self.send_queue.dequeue(self.allocator)) |sender| {
                const value = sender.value_ptr.?.*;
                sender.task.state = .runnable;
                return value;
            }

            return null;
        }

        /// Close channel
        pub fn close(self: *Self) void {
            self.closed.store(true, .release);

            self.mutex.lock();
            defer self.mutex.unlock();

            // Wake all blocked tasks
            while (self.send_queue.dequeue(self.allocator)) |sender| {
                sender.task.state = .runnable;
            }
            while (self.recv_queue.dequeue(self.allocator)) |receiver| {
                receiver.task.state = .runnable;
            }
        }

        /// Check if channel is closed
        pub fn isClosed(self: *Self) bool {
            return self.closed.load(.acquire);
        }

        /// Get number of items in buffer
        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.size;
        }

        /// Check if buffer is empty
        pub fn isEmpty(self: *Self) bool {
            return self.len() == 0;
        }

        /// Check if buffer is full
        pub fn isFull(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.size >= self.capacity;
        }

        /// Get capacity
        pub fn cap(self: *Self) usize {
            return self.capacity;
        }

        /// Get number of waiting senders
        pub fn sendQueueLen(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.send_queue.len;
        }

        /// Get number of waiting receivers
        pub fn recvQueueLen(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.recv_queue.len;
        }
    };
}

/// Select operation on multiple channels
pub const Select = @import("channel/select.zig").Select;

/// Create unbuffered channel
pub fn make(comptime T: type, allocator: std.mem.Allocator) !*Channel(T) {
    return Channel(T).init(allocator);
}

/// Create buffered channel
pub fn makeBuffered(comptime T: type, allocator: std.mem.Allocator, capacity: usize) !*Channel(T) {
    return Channel(T).initBuffered(allocator, capacity);
}
