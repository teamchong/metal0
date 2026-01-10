//! concurrent.interpreters._queues - Inter-interpreter queue support
//! Reference: cpython/Lib/concurrent/interpreters/_queues.py
//!
//! Provides queue implementations for communication between interpreters.

const std = @import("std");
const interpreters = @import("../interpreters.zig");
const _crossinterp = @import("_crossinterp.zig");

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class QueueError(Exception)
pub const QueueError = error.QueueError;

/// CPython: class QueueEmpty(QueueError)
pub const QueueEmpty = interpreters.QueueEmpty;

/// CPython: class QueueFull(QueueError)
pub const QueueFull = interpreters.QueueFull;

// ============================================================================
// QueueInfo
// ============================================================================

/// Information about a queue
pub const QueueInfo = struct {
    /// Queue ID
    id: u64,
    /// Maximum size (0 = unbounded)
    maxsize: usize,
    /// Current size
    count: usize,
    /// Number of formatters
    fmt_count: usize = 0,
    /// Whether queue is full
    is_full: bool,
    /// Whether queue is closed
    is_closed: bool = false,
};

// ============================================================================
// InterpreterQueue
// ============================================================================

/// CPython: class Queue
/// A queue for inter-interpreter communication with serialization
pub fn InterpreterQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Queue ID
        id: u64,
        /// Underlying queue
        queue: std.ArrayList(SerializedItem),
        /// Maximum size (0 = unbounded)
        maxsize: usize,
        /// Mutex for thread safety
        mutex: std.Thread.Mutex = .{},
        /// Condition for blocking get
        not_empty: std.Thread.Condition = .{},
        /// Condition for blocking put
        not_full: std.Thread.Condition = .{},
        /// Whether queue is closed
        is_closed: bool = false,
        /// Allocator
        allocator: std.mem.Allocator,

        const SerializedItem = struct {
            data: []u8,
            source_interp: u64,
        };

        pub fn init(allocator: std.mem.Allocator, id: u64, maxsize: usize) Self {
            return .{
                .id = id,
                .queue = std.ArrayList(SerializedItem).init(allocator),
                .maxsize = maxsize,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.queue.items) |item| {
                self.allocator.free(item.data);
            }
            self.queue.deinit();
        }

        /// CPython: def put(self, obj, /, timeout=None, *, syncobj=False)
        /// Put an item on the queue with optional timeout
        pub fn put(self: *Self, item: T, source_interp: u64, timeout: ?u64) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.is_closed) {
                return error.QueueClosed;
            }

            while (self.maxsize > 0 and self.queue.items.len >= self.maxsize) {
                if (timeout) |t| {
                    const did_timeout = self.not_full.timedWait(&self.mutex, t) == .timed_out;
                    if (did_timeout) return QueueFull;
                } else {
                    self.not_full.wait(&self.mutex);
                }
            }

            // Serialize the item
            const data = try _crossinterp.CrossInterpreterData.serialize(T, item, self.allocator);
            try self.queue.append(.{
                .data = data,
                .source_interp = source_interp,
            });
            self.not_empty.signal();
        }

        /// CPython: def put_nowait(self, obj, /, *, syncobj=False)
        /// Put an item without waiting
        pub fn put_nowait(self: *Self, item: T, source_interp: u64) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.is_closed) {
                return error.QueueClosed;
            }

            if (self.maxsize > 0 and self.queue.items.len >= self.maxsize) {
                return QueueFull;
            }

            const data = try _crossinterp.CrossInterpreterData.serialize(T, item, self.allocator);
            try self.queue.append(.{
                .data = data,
                .source_interp = source_interp,
            });
            self.not_empty.signal();
        }

        /// CPython: def get(self, /, timeout=None)
        /// Get an item from the queue with optional timeout
        pub fn get(self: *Self, timeout: ?u64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.queue.items.len == 0) {
                if (self.is_closed) {
                    return QueueEmpty;
                }
                if (timeout) |t| {
                    const did_timeout = self.not_empty.timedWait(&self.mutex, t) == .timed_out;
                    if (did_timeout) return QueueEmpty;
                } else {
                    self.not_empty.wait(&self.mutex);
                }
            }

            const serialized = self.queue.orderedRemove(0);
            defer self.allocator.free(serialized.data);
            self.not_full.signal();

            return _crossinterp.CrossInterpreterData.deserialize(T, serialized.data);
        }

        /// CPython: def get_nowait(self)
        /// Get an item without waiting
        pub fn get_nowait(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.queue.items.len == 0) {
                return QueueEmpty;
            }

            const serialized = self.queue.orderedRemove(0);
            defer self.allocator.free(serialized.data);
            self.not_full.signal();

            return _crossinterp.CrossInterpreterData.deserialize(T, serialized.data);
        }

        /// CPython: def qsize(self)
        /// Return current queue size
        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.queue.items.len;
        }

        /// CPython: def empty(self)
        /// Check if queue is empty
        pub fn empty(self: *Self) bool {
            return self.qsize() == 0;
        }

        /// CPython: def full(self)
        /// Check if queue is full
        pub fn full(self: *Self) bool {
            if (self.maxsize == 0) return false;
            return self.qsize() >= self.maxsize;
        }

        /// CPython: def close(self)
        /// Close the queue
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.is_closed = true;
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }

        /// Get queue info
        pub fn info(self: *Self) QueueInfo {
            self.mutex.lock();
            defer self.mutex.unlock();
            return QueueInfo{
                .id = self.id,
                .maxsize = self.maxsize,
                .count = self.queue.items.len,
                .is_full = self.maxsize > 0 and self.queue.items.len >= self.maxsize,
                .is_closed = self.is_closed,
            };
        }
    };
}

// ============================================================================
// Queue Registry
// ============================================================================

/// Global queue counter
var _queue_counter: u64 = 0;

/// CPython: def create(maxsize=0)
/// Create a new inter-interpreter queue
pub fn create(comptime T: type, allocator: std.mem.Allocator, maxsize: usize) InterpreterQueue(T) {
    const id = @atomicRmw(u64, &_queue_counter, .Add, 1, .monotonic);
    return InterpreterQueue(T).init(allocator, id, maxsize);
}

/// CPython: def list_all()
/// List all queues (not fully implemented - would need global registry)
pub fn list_all(allocator: std.mem.Allocator) !std.ArrayList(QueueInfo) {
    return std.ArrayList(QueueInfo).init(allocator);
}

// ============================================================================
// FIFOLock (internal)
// ============================================================================

/// A FIFO mutex that grants access in request order
pub const FIFOLock = struct {
    const Self = @This();

    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    waiters: usize = 0,
    owner: ?std.Thread.Id = null,

    pub fn init() Self {
        return .{};
    }

    pub fn acquire(self: *Self) void {
        self.mutex.lock();
        self.waiters += 1;

        while (self.owner != null) {
            self.condition.wait(&self.mutex);
        }

        self.owner = std.Thread.getCurrentId();
        self.waiters -= 1;
        self.mutex.unlock();
    }

    pub fn release(self: *Self) void {
        self.mutex.lock();
        self.owner = null;
        self.condition.signal();
        self.mutex.unlock();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "QueueInfo" {
    const info = QueueInfo{
        .id = 1,
        .maxsize = 10,
        .count = 5,
        .is_full = false,
    };
    try std.testing.expectEqual(@as(u64, 1), info.id);
    try std.testing.expectEqual(@as(usize, 10), info.maxsize);
}

test "InterpreterQueue basic" {
    const allocator = std.testing.allocator;
    var queue = InterpreterQueue(i32).init(allocator, 1, 10);
    defer queue.deinit();

    try std.testing.expect(queue.empty());
    try std.testing.expect(!queue.full());
}

test "create queue" {
    const allocator = std.testing.allocator;
    var queue = create(i32, allocator, 5);
    defer queue.deinit();

    try std.testing.expect(queue.id >= 0);
    try std.testing.expectEqual(@as(usize, 5), queue.maxsize);
}

test "FIFOLock basic" {
    var lock = FIFOLock.init();

    lock.acquire();
    try std.testing.expect(lock.owner != null);
    lock.release();
    try std.testing.expect(lock.owner == null);
}
