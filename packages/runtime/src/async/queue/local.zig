const std = @import("std");
const Task = @import("../task.zig").Task;
const lockfree = @import("lockfree.zig");

/// Local run queue for a processor (P in Go's GMP model)
/// Each processor has its own queue to minimize contention
/// Capacity is 256 (power of 2) for fast operations
pub const LocalQueue = struct {
    /// Lock-free circular buffer (256 slots)
    queue: lockfree.Queue(256),

    /// Processor ID that owns this queue
    processor_id: usize,

    /// Statistics
    total_pushed: usize,
    total_popped: usize,
    total_stolen: usize,

    const Self = @This();

    /// Initialize local queue for a processor
    pub fn init(processor_id: usize) Self {
        return Self{
            .queue = lockfree.Queue(256).init(),
            .processor_id = processor_id,
            .total_pushed = 0,
            .total_popped = 0,
            .total_stolen = 0,
        };
    }

    /// Push task to local queue (called by owning processor)
    /// Returns false if queue is full (task should go to global queue)
    pub fn push(self: *Self, task: *Task) bool {
        const result = self.queue.push(task);
        if (result) {
            self.total_pushed += 1;
        }
        return result;
    }

    /// Pop task from local queue (called by owning processor)
    /// Returns null if queue is empty
    pub fn pop(self: *Self) ?*Task {
        const task = self.queue.pop();
        if (task != null) {
            self.total_popped += 1;
        }
        return task;
    }

    /// Steal task from this queue (called by other processors)
    /// Returns null if queue is empty or race lost
    pub fn steal(self: *Self) ?*Task {
        const task = self.queue.steal();
        if (task != null) {
            self.total_stolen += 1;
        }
        return task;
    }

    /// Get current queue size
    pub fn size(self: *Self) usize {
        return self.queue.size();
    }

    /// Check if queue is empty
    pub fn isEmpty(self: *Self) bool {
        return self.queue.isEmpty();
    }

    /// Check if queue is full
    pub fn isFull(self: *Self) bool {
        return self.queue.isFull();
    }

    /// Get statistics
    pub fn getStats(self: *Self) LocalQueueStats {
        return LocalQueueStats{
            .processor_id = self.processor_id,
            .current_size = self.size(),
            .total_pushed = self.total_pushed,
            .total_popped = self.total_popped,
            .total_stolen = self.total_stolen,
        };
    }

    /// Clear queue (not thread-safe - use only when queue is idle)
    pub fn clear(self: *Self) void {
        self.queue.clear();
        self.total_pushed = 0;
        self.total_popped = 0;
        self.total_stolen = 0;
    }
};

/// Statistics for a local queue
pub const LocalQueueStats = struct {
    processor_id: usize,
    current_size: usize,
    total_pushed: usize,
    total_popped: usize,
    total_stolen: usize,
};

// Tests
test "LocalQueue basic operations" {
    const testing = std.testing;

    var queue = LocalQueue.init(0);

    // Create tasks
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

    // Check stats
    var stats = queue.getStats();
    try testing.expect(stats.total_pushed == 3);
    try testing.expect(stats.current_size == 3);

    // Test pop
    const t1 = queue.pop();
    try testing.expect(t1 != null);
    try testing.expect(t1.?.id == 1);

    stats = queue.getStats();
    try testing.expect(stats.total_popped == 1);

    // Test steal
    const t2 = queue.steal();
    try testing.expect(t2 != null);
    try testing.expect(t2.?.id == 2);

    stats = queue.getStats();
    try testing.expect(stats.total_stolen == 1);
}

test "LocalQueue full condition" {
    const testing = std.testing;

    var queue = LocalQueue.init(0);

    // Try to fill the queue
    var tasks: [300]Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = Task.init(i, undefined, undefined);
    }

    // Push until full
    var pushed: usize = 0;
    for (&tasks) |*task| {
        if (!queue.push(task)) {
            break;
        }
        pushed += 1;
    }

    // Should have pushed 255 tasks (capacity - 1)
    try testing.expect(pushed == 255);
    try testing.expect(queue.isFull());

    // Check stats
    const stats = queue.getStats();
    try testing.expect(stats.total_pushed == 255);
}

test "LocalQueue steal vs pop" {
    const testing = std.testing;

    var queue = LocalQueue.init(0);

    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);
    var task3 = Task.init(3, undefined, undefined);
    var task4 = Task.init(4, undefined, undefined);

    // Push tasks
    try testing.expect(queue.push(&task1));
    try testing.expect(queue.push(&task2));
    try testing.expect(queue.push(&task3));
    try testing.expect(queue.push(&task4));

    // Mix pop and steal
    const t1 = queue.pop(); // Owner pops
    try testing.expect(t1 != null);
    try testing.expect(t1.?.id == 1);

    const t2 = queue.steal(); // Thief steals
    try testing.expect(t2 != null);
    try testing.expect(t2.?.id == 2);

    const t3 = queue.pop(); // Owner pops
    try testing.expect(t3 != null);
    try testing.expect(t3.?.id == 3);

    const t4 = queue.steal(); // Thief steals
    try testing.expect(t4 != null);
    try testing.expect(t4.?.id == 4);

    // Check stats
    const stats = queue.getStats();
    try testing.expect(stats.total_popped == 2);
    try testing.expect(stats.total_stolen == 2);
}

test "LocalQueue clear" {
    const testing = std.testing;

    var queue = LocalQueue.init(0);

    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);

    try testing.expect(queue.push(&task1));
    try testing.expect(queue.push(&task2));

    queue.clear();

    try testing.expect(queue.isEmpty());
    const stats = queue.getStats();
    try testing.expect(stats.total_pushed == 0);
    try testing.expect(stats.total_popped == 0);
}
