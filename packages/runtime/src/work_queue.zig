const std = @import("std");
const GreenThread = @import("green_thread").GreenThread;

/// Chase-Lev work-stealing deque
/// Owner thread pushes/pops from bottom (LIFO)
/// Other threads steal from top (FIFO)
pub const WorkQueue = struct {
    tasks: std.ArrayList(*GreenThread),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WorkQueue {
        return .{
            .tasks = std.ArrayList(*GreenThread){},
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WorkQueue) void {
        self.tasks.deinit(self.allocator);
    }

    /// Push task to bottom (owner thread only)
    pub fn push(self: *WorkQueue, task: *GreenThread) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.tasks.append(self.allocator, task);
    }

    /// Pop task from bottom (owner thread only) - LIFO for cache locality
    pub fn pop(self: *WorkQueue) ?*GreenThread {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tasks.items.len == 0) return null;
        return self.tasks.pop();
    }

    /// Steal task from top (other threads) - FIFO for fairness
    pub fn steal(self: *WorkQueue) ?*GreenThread {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tasks.items.len == 0) return null;
        return self.tasks.orderedRemove(0);
    }

    pub fn len(self: *WorkQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.tasks.items.len;
    }

    /// Lock-free size check (may be stale, used for work-stealing heuristics)
    pub fn size(self: *const WorkQueue) usize {
        // Direct read without lock - acceptable race for heuristic checks
        return self.tasks.items.len;
    }

    pub fn isEmpty(self: *WorkQueue) bool {
        return self.len() == 0;
    }
};

test "WorkQueue basic operations" {
    const allocator = std.testing.allocator;

    var queue = WorkQueue.init(allocator);
    defer queue.deinit();

    try std.testing.expectEqual(@as(usize, 0), queue.len());
    try std.testing.expectEqual(true, queue.isEmpty());

    // Create dummy threads
    const TestFunc = struct {
        fn func(thread: *GreenThread) void {
            _ = thread;
        }
    };

    const t1 = try GreenThread.init(allocator, 1, TestFunc.func);
    defer t1.deinit(allocator);

    const t2 = try GreenThread.init(allocator, 2, TestFunc.func);
    defer t2.deinit(allocator);

    // Push tasks
    try queue.push(t1);
    try queue.push(t2);

    try std.testing.expectEqual(@as(usize, 2), queue.len());

    // Pop (LIFO) - should get t2
    const popped = queue.pop().?;
    try std.testing.expectEqual(@as(u64, 2), popped.id);

    try std.testing.expectEqual(@as(usize, 1), queue.len());
}

test "WorkQueue work stealing" {
    const allocator = std.testing.allocator;

    var queue = WorkQueue.init(allocator);
    defer queue.deinit();

    const TestFunc = struct {
        fn func(thread: *GreenThread) void {
            _ = thread;
        }
    };

    const t1 = try GreenThread.init(allocator, 1, TestFunc.func);
    defer t1.deinit(allocator);

    const t2 = try GreenThread.init(allocator, 2, TestFunc.func);
    defer t2.deinit(allocator);

    const t3 = try GreenThread.init(allocator, 3, TestFunc.func);
    defer t3.deinit(allocator);

    // Push tasks
    try queue.push(t1);
    try queue.push(t2);
    try queue.push(t3);

    // Steal (FIFO) - should get t1 (oldest)
    const stolen = queue.steal().?;
    try std.testing.expectEqual(@as(u64, 1), stolen.id);

    // Pop (LIFO) - should get t3 (newest)
    const popped = queue.pop().?;
    try std.testing.expectEqual(@as(u64, 3), popped.id);

    // Should have t2 left
    try std.testing.expectEqual(@as(usize, 1), queue.len());
}
