const std = @import("std");
const Task = @import("../task.zig").Task;

/// Lock-free circular buffer queue (from Tokio)
/// Uses atomic operations for thread-safe push/pop/steal without locks
/// Capacity must be power of 2 for fast modulo via bitwise AND
pub fn Queue(comptime capacity: usize) type {
    // Verify power of 2 at compile time
    comptime {
        if (capacity == 0 or (capacity & (capacity - 1)) != 0) {
            @compileError("Queue capacity must be power of 2");
        }
    }

    return struct {
        /// Fixed-size buffer for tasks
        buffer: [capacity]?*Task,

        /// Head index (consumer reads from here)
        head: std.atomic.Value(usize),

        /// Tail index (producer writes here)
        tail: std.atomic.Value(usize),

        const Self = @This();
        const mask = capacity - 1; // Comptime: e.g., 256 -> 255 (0xFF)

        /// Initialize empty queue
        pub fn init() Self {
            var queue = Self{
                .buffer = undefined,
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
            };

            // Initialize buffer to null
            for (&queue.buffer) |*slot| {
                slot.* = null;
            }

            return queue;
        }

        /// Push task onto queue (single producer)
        /// Returns true on success, false if queue is full
        pub fn push(self: *Self, task: *Task) bool {
            const tail = self.tail.load(.acquire);
            const next_tail = (tail + 1) & mask; // Fast modulo

            // Check if queue is full
            const head = self.head.load(.acquire);
            if (next_tail == head) {
                return false; // Full
            }

            // Write task to buffer
            self.buffer[tail] = task;

            // Update tail with release semantics (makes write visible)
            self.tail.store(next_tail, .release);

            return true;
        }

        /// Pop task from queue (single consumer - same thread that pushed)
        /// Returns null if queue is empty
        pub fn pop(self: *Self) ?*Task {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);

            // Check if queue is empty
            if (head == tail) {
                return null;
            }

            // Read task from buffer
            const task = self.buffer[head];

            // Clear slot
            self.buffer[head] = null;

            // Update head with release semantics
            self.head.store((head + 1) & mask, .release);

            return task;
        }

        /// Steal task from queue (work-stealing by other threads)
        /// Uses fetch-add for atomic increment
        /// Returns null if queue is empty or race lost
        pub fn steal(self: *Self) ?*Task {
            // Atomically increment head and get old value
            const old_head = self.head.fetchAdd(1, .acquire);
            const tail = self.tail.load(.acquire);

            // Check if we won the race
            if (old_head >= tail) {
                // Lost race or queue empty, revert head
                _ = self.head.fetchSub(1, .release);
                return null;
            }

            // Won the race, get task
            const task = self.buffer[old_head & mask];

            // Clear slot
            self.buffer[old_head & mask] = null;

            return task;
        }

        /// Get current queue size (approximate - may be stale)
        pub fn size(self: *Self) usize {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);

            if (tail >= head) {
                return tail - head;
            } else {
                // Wrapped around
                return capacity - (head - tail);
            }
        }

        /// Check if queue is empty (approximate)
        pub fn isEmpty(self: *Self) bool {
            return self.size() == 0;
        }

        /// Check if queue is full (approximate)
        pub fn isFull(self: *Self) bool {
            const tail = self.tail.load(.acquire);
            const next_tail = (tail + 1) & mask;
            const head = self.head.load(.acquire);
            return next_tail == head;
        }

        /// Clear all tasks from queue (not thread-safe - use only when queue is idle)
        pub fn clear(self: *Self) void {
            while (self.pop()) |_| {}
        }

        /// Capacity of this queue (compile-time constant)
        pub fn getCapacity() usize {
            return capacity;
        }
    };
}

// Tests
test "Queue basic operations" {
    const testing = std.testing;

    // Create a small queue
    var queue = Queue(4).init();

    // Create dummy tasks
    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);
    var task3 = Task.init(3, undefined, undefined);

    // Test empty
    try testing.expect(queue.isEmpty());
    try testing.expect(queue.pop() == null);

    // Test push
    try testing.expect(queue.push(&task1));
    try testing.expect(queue.push(&task2));
    try testing.expect(queue.push(&task3));
    try testing.expect(queue.size() == 3);

    // Test pop
    const t1 = queue.pop();
    try testing.expect(t1 != null);
    try testing.expect(t1.?.id == 1);

    const t2 = queue.pop();
    try testing.expect(t2 != null);
    try testing.expect(t2.?.id == 2);

    try testing.expect(queue.size() == 1);

    // Test push again
    var task4 = Task.init(4, undefined, undefined);
    try testing.expect(queue.push(&task4));

    // Test pop remaining
    const t3 = queue.pop();
    try testing.expect(t3 != null);
    try testing.expect(t3.?.id == 3);

    const t4 = queue.pop();
    try testing.expect(t4 != null);
    try testing.expect(t4.?.id == 4);

    try testing.expect(queue.isEmpty());
}

test "Queue full condition" {
    const testing = std.testing;

    // Create queue with capacity 4 (can hold 3 items)
    var queue = Queue(4).init();

    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);
    var task3 = Task.init(3, undefined, undefined);
    var task4 = Task.init(4, undefined, undefined);

    // Fill queue
    try testing.expect(queue.push(&task1));
    try testing.expect(queue.push(&task2));
    try testing.expect(queue.push(&task3));

    // Queue should be full now
    try testing.expect(queue.isFull());
    try testing.expect(!queue.push(&task4));
}

test "Queue steal operation" {
    const testing = std.testing;

    var queue = Queue(8).init();

    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);
    var task3 = Task.init(3, undefined, undefined);

    // Push tasks
    try testing.expect(queue.push(&task1));
    try testing.expect(queue.push(&task2));
    try testing.expect(queue.push(&task3));

    // Steal from queue (simulating another thread)
    const stolen1 = queue.steal();
    try testing.expect(stolen1 != null);
    try testing.expect(stolen1.?.id == 1);

    const stolen2 = queue.steal();
    try testing.expect(stolen2 != null);
    try testing.expect(stolen2.?.id == 2);

    // Pop should still work for remaining task
    const popped = queue.pop();
    try testing.expect(popped != null);
    try testing.expect(popped.?.id == 3);

    try testing.expect(queue.isEmpty());
}

test "Queue wrap-around" {
    const testing = std.testing;

    var queue = Queue(4).init();

    // Create tasks
    var tasks: [10]Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = Task.init(i, undefined, undefined);
    }

    // Push and pop repeatedly to test wrap-around
    try testing.expect(queue.push(&tasks[0]));
    try testing.expect(queue.push(&tasks[1]));
    _ = queue.pop();
    _ = queue.pop();

    try testing.expect(queue.push(&tasks[2]));
    try testing.expect(queue.push(&tasks[3]));
    try testing.expect(queue.push(&tasks[4]));
    _ = queue.pop();

    try testing.expect(queue.push(&tasks[5]));
    const t = queue.pop();
    try testing.expect(t != null);
    try testing.expect(t.?.id == 3);
}

test "Queue comptime power-of-2 check" {
    // These should compile
    _ = Queue(2).init();
    _ = Queue(4).init();
    _ = Queue(8).init();
    _ = Queue(16).init();
    _ = Queue(256).init();

    // These would fail at compile time:
    // _ = Queue(0).init();   // Error: not power of 2
    // _ = Queue(3).init();   // Error: not power of 2
    // _ = Queue(100).init(); // Error: not power of 2
}
