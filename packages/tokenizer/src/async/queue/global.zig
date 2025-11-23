const std = @import("std");
const Task = @import("../task.zig").Task;

/// Global overflow queue (unbounded, lock-protected)
/// Used when local queues are full or for work-stealing overflow
/// Based on Go's global runqueue design
pub const GlobalQueue = struct {
    /// Head of linked list
    head: std.atomic.Value(?*Task),

    /// Tail of linked list
    tail: std.atomic.Value(?*Task),

    /// Mutex for coordinated access (needed for linked list operations)
    mutex: std.Thread.Mutex,

    /// Queue size (approximate)
    size_atomic: std.atomic.Value(usize),

    /// Statistics
    total_pushed: usize,
    total_popped: usize,

    const Self = @This();

    /// Initialize empty global queue
    pub fn init() Self {
        return Self{
            .head = std.atomic.Value(?*Task).init(null),
            .tail = std.atomic.Value(?*Task).init(null),
            .mutex = std.Thread.Mutex{},
            .size_atomic = std.atomic.Value(usize).init(0),
            .total_pushed = 0,
            .total_popped = 0,
        };
    }

    /// Push task to global queue
    /// Thread-safe, uses mutex
    pub fn push(self: *Self, task: *Task) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        task.next = null;

        const old_tail = self.tail.load(.acquire);
        if (old_tail) |tail| {
            tail.next = task;
        } else {
            // Queue was empty, set head
            self.head.store(task, .release);
        }

        self.tail.store(task, .release);
        _ = self.size_atomic.fetchAdd(1, .release);
        self.total_pushed += 1;
    }

    /// Push multiple tasks as a batch (more efficient)
    pub fn pushBatch(self: *Self, tasks: []*Task) void {
        if (tasks.len == 0) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Link tasks together
        for (tasks[0 .. tasks.len - 1], 0..) |task, i| {
            task.next = tasks[i + 1];
        }
        tasks[tasks.len - 1].next = null;

        const old_tail = self.tail.load(.acquire);
        if (old_tail) |tail| {
            tail.next = tasks[0];
        } else {
            // Queue was empty, set head
            self.head.store(tasks[0], .release);
        }

        self.tail.store(tasks[tasks.len - 1], .release);
        _ = self.size_atomic.fetchAdd(tasks.len, .release);
        self.total_pushed += tasks.len;
    }

    /// Pop task from global queue
    /// Thread-safe, uses mutex
    /// Returns null if queue is empty
    pub fn pop(self: *Self) ?*Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        const old_head = self.head.load(.acquire);
        const task = old_head orelse return null;

        const next = task.next;
        self.head.store(next, .release);

        if (next == null) {
            // Queue is now empty, clear tail
            self.tail.store(null, .release);
        }

        task.next = null;
        _ = self.size_atomic.fetchSub(1, .release);
        self.total_popped += 1;

        return task;
    }

    /// Pop multiple tasks as a batch (for work distribution)
    /// Returns up to max_count tasks
    pub fn popBatch(self: *Self, max_count: usize) []?*Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        var tasks = std.ArrayList(?*Task).init(std.heap.page_allocator);
        var current = self.head.load(.acquire);
        var count: usize = 0;

        while (current != null and count < max_count) {
            const task = current.?;
            tasks.append(task) catch break;

            current = task.next;
            task.next = null;
            count += 1;
        }

        self.head.store(current, .release);

        if (current == null) {
            // Queue is now empty
            self.tail.store(null, .release);
        }

        _ = self.size_atomic.fetchSub(count, .release);
        self.total_popped += count;

        return tasks.items;
    }

    /// Get current queue size (approximate)
    pub fn size(self: *Self) usize {
        return self.size_atomic.load(.acquire);
    }

    /// Check if queue is empty (approximate)
    pub fn isEmpty(self: *Self) bool {
        return self.size() == 0;
    }

    /// Get statistics
    pub fn getStats(self: *Self) GlobalQueueStats {
        return GlobalQueueStats{
            .current_size = self.size(),
            .total_pushed = self.total_pushed,
            .total_popped = self.total_popped,
        };
    }

    /// Clear queue (not thread-safe - use only when queue is idle)
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.head.store(null, .release);
        self.tail.store(null, .release);
        self.size_atomic.store(0, .release);
        self.total_pushed = 0;
        self.total_popped = 0;
    }
};

/// Statistics for global queue
pub const GlobalQueueStats = struct {
    current_size: usize,
    total_pushed: usize,
    total_popped: usize,
};

// Tests
test "GlobalQueue basic operations" {
    const testing = std.testing;

    var queue = GlobalQueue.init();

    // Create tasks
    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);
    var task3 = Task.init(3, undefined, undefined);

    // Test empty
    try testing.expect(queue.isEmpty());
    try testing.expect(queue.pop() == null);

    // Test push
    queue.push(&task1);
    queue.push(&task2);
    queue.push(&task3);
    try testing.expect(queue.size() == 3);

    // Check stats
    const stats = queue.getStats();
    try testing.expect(stats.total_pushed == 3);
    try testing.expect(stats.current_size == 3);

    // Test pop
    const t1 = queue.pop();
    try testing.expect(t1 != null);
    try testing.expect(t1.?.id == 1);

    const t2 = queue.pop();
    try testing.expect(t2 != null);
    try testing.expect(t2.?.id == 2);

    try testing.expect(queue.size() == 1);

    const t3 = queue.pop();
    try testing.expect(t3 != null);
    try testing.expect(t3.?.id == 3);

    try testing.expect(queue.isEmpty());
}

test "GlobalQueue batch operations" {
    const testing = std.testing;

    var queue = GlobalQueue.init();

    // Create tasks
    var tasks: [5]Task = undefined;
    var task_ptrs: [5]*Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = Task.init(i, undefined, undefined);
        task_ptrs[i] = task;
    }

    // Test batch push
    queue.pushBatch(&task_ptrs);
    try testing.expect(queue.size() == 5);

    // Test batch pop
    const popped = queue.popBatch(3);
    try testing.expect(popped.len == 3);
    try testing.expect(popped[0].?.id == 0);
    try testing.expect(popped[1].?.id == 1);
    try testing.expect(popped[2].?.id == 2);

    try testing.expect(queue.size() == 2);

    // Pop remaining
    const t4 = queue.pop();
    try testing.expect(t4 != null);
    try testing.expect(t4.?.id == 3);

    const t5 = queue.pop();
    try testing.expect(t5 != null);
    try testing.expect(t5.?.id == 4);

    try testing.expect(queue.isEmpty());
}

test "GlobalQueue linked list integrity" {
    const testing = std.testing;

    var queue = GlobalQueue.init();

    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);
    var task3 = Task.init(3, undefined, undefined);

    // Push tasks
    queue.push(&task1);
    queue.push(&task2);
    queue.push(&task3);

    // Pop all and verify order
    const t1 = queue.pop();
    try testing.expect(t1 != null);
    try testing.expect(t1.?.id == 1);
    try testing.expect(t1.?.next == null); // Should be cleared

    const t2 = queue.pop();
    try testing.expect(t2 != null);
    try testing.expect(t2.?.id == 2);
    try testing.expect(t2.?.next == null);

    const t3 = queue.pop();
    try testing.expect(t3 != null);
    try testing.expect(t3.?.id == 3);
    try testing.expect(t3.?.next == null);

    try testing.expect(queue.isEmpty());
}

test "GlobalQueue clear" {
    const testing = std.testing;

    var queue = GlobalQueue.init();

    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);

    queue.push(&task1);
    queue.push(&task2);

    queue.clear();

    try testing.expect(queue.isEmpty());
    const stats = queue.getStats();
    try testing.expect(stats.total_pushed == 0);
    try testing.expect(stats.total_popped == 0);
}
