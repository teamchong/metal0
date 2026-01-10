//! test.test_concurrent_futures.test_thread_pool - ThreadPoolExecutor tests
//!
//! Tests for ThreadPoolExecutor including thread management, task queuing,
//! worker scaling, and thread-specific behavior.

const std = @import("std");
const testing = std.testing;

/// Error types for thread pool operations
pub const ThreadPoolError = error{
    PoolNotRunning,
    PoolShutdown,
    MaxWorkersExceeded,
    WorkerCreationFailed,
    TaskRejected,
    QueueFull,
    ThreadJoinFailed,
};

/// Thread pool state
pub const PoolState = enum {
    created,
    running,
    shutting_down,
    terminated,

    pub fn isActive(self: PoolState) bool {
        return self == .running;
    }

    pub fn canAcceptTasks(self: PoolState) bool {
        return self == .running;
    }

    pub fn isTerminated(self: PoolState) bool {
        return self == .terminated;
    }
};

/// Configuration for thread pool
pub const ThreadPoolConfig = struct {
    max_workers: usize = 0, // 0 means auto-detect
    min_workers: usize = 0,
    thread_name_prefix: []const u8 = "ThreadPoolWorker",
    keep_alive_time_ms: u64 = 60000,
    queue_capacity: usize = 1000,
    allow_core_thread_timeout: bool = false,

    pub fn init() ThreadPoolConfig {
        return .{};
    }

    pub fn withMaxWorkers(max_workers: usize) ThreadPoolConfig {
        return .{ .max_workers = max_workers };
    }

    pub fn withRange(min: usize, max: usize) ThreadPoolConfig {
        return .{
            .min_workers = min,
            .max_workers = max,
        };
    }

    pub fn withPrefix(prefix: []const u8) ThreadPoolConfig {
        return .{ .thread_name_prefix = prefix };
    }

    pub fn validate(self: ThreadPoolConfig) ThreadPoolError!void {
        if (self.max_workers > 0 and self.min_workers > self.max_workers) {
            return ThreadPoolError.MaxWorkersExceeded;
        }
        if (self.queue_capacity == 0) {
            return ThreadPoolError.TaskRejected;
        }
    }
};

/// Worker thread information
pub const WorkerInfo = struct {
    id: u64,
    state: State = .idle,
    tasks_completed: usize = 0,
    creation_time: i64,
    last_active_time: i64,
    current_task_start: ?i64 = null,

    pub const State = enum {
        idle,
        busy,
        terminating,
        terminated,

        pub fn isWorking(self: State) bool {
            return self == .busy;
        }

        pub fn isAlive(self: State) bool {
            return self == .idle or self == .busy;
        }
    };

    pub fn init(id: u64) WorkerInfo {
        const now = std.time.milliTimestamp();
        return .{
            .id = id,
            .creation_time = now,
            .last_active_time = now,
        };
    }

    pub fn startTask(self: *WorkerInfo) void {
        self.state = .busy;
        self.current_task_start = std.time.milliTimestamp();
    }

    pub fn completeTask(self: *WorkerInfo) void {
        self.state = .idle;
        self.tasks_completed += 1;
        self.last_active_time = std.time.milliTimestamp();
        self.current_task_start = null;
    }

    pub fn terminate(self: *WorkerInfo) void {
        self.state = .terminated;
    }

    pub fn getIdleTime(self: WorkerInfo) i64 {
        if (self.state == .busy) return 0;
        return std.time.milliTimestamp() - self.last_active_time;
    }

    pub fn getCurrentTaskDuration(self: WorkerInfo) ?i64 {
        if (self.current_task_start) |start| {
            return std.time.milliTimestamp() - start;
        }
        return null;
    }

    pub fn getUptime(self: WorkerInfo) i64 {
        return std.time.milliTimestamp() - self.creation_time;
    }
};

/// Thread pool worker manager
pub const WorkerManager = struct {
    const Self = @This();

    workers: std.ArrayList(WorkerInfo),
    allocator: std.mem.Allocator,
    next_worker_id: u64 = 0,
    config: ThreadPoolConfig,

    pub fn init(allocator: std.mem.Allocator, config: ThreadPoolConfig) Self {
        return .{
            .workers = std.ArrayList(WorkerInfo).init(allocator),
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.workers.deinit();
    }

    pub fn createWorker(self: *Self) ThreadPoolError!*WorkerInfo {
        if (self.config.max_workers > 0 and self.workers.items.len >= self.config.max_workers) {
            return ThreadPoolError.MaxWorkersExceeded;
        }

        const worker = WorkerInfo.init(self.next_worker_id);
        self.next_worker_id += 1;
        self.workers.append(worker) catch {
            return ThreadPoolError.WorkerCreationFailed;
        };
        return &self.workers.items[self.workers.items.len - 1];
    }

    pub fn getWorkerCount(self: Self) usize {
        return self.workers.items.len;
    }

    pub fn getActiveCount(self: Self) usize {
        var count: usize = 0;
        for (self.workers.items) |w| {
            if (w.state.isAlive()) count += 1;
        }
        return count;
    }

    pub fn getBusyCount(self: Self) usize {
        var count: usize = 0;
        for (self.workers.items) |w| {
            if (w.state.isWorking()) count += 1;
        }
        return count;
    }

    pub fn getIdleCount(self: Self) usize {
        var count: usize = 0;
        for (self.workers.items) |w| {
            if (w.state == .idle) count += 1;
        }
        return count;
    }

    pub fn getIdleWorker(self: *Self) ?*WorkerInfo {
        for (self.workers.items) |*w| {
            if (w.state == .idle) return w;
        }
        return null;
    }

    pub fn terminateIdleWorkers(self: *Self, max_idle_time_ms: i64) usize {
        var terminated: usize = 0;
        for (self.workers.items) |*w| {
            if (w.state == .idle and w.getIdleTime() > max_idle_time_ms) {
                w.terminate();
                terminated += 1;
            }
        }
        return terminated;
    }

    pub fn terminateAll(self: *Self) void {
        for (self.workers.items) |*w| {
            w.terminate();
        }
    }

    pub fn getTotalTasksCompleted(self: Self) usize {
        var total: usize = 0;
        for (self.workers.items) |w| {
            total += w.tasks_completed;
        }
        return total;
    }
};

/// Thread pool task queue
pub fn TaskQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const QueuedTask = struct {
            id: u64,
            data: T,
            priority: Priority = .normal,
            queued_at: i64,

            pub const Priority = enum(u8) {
                low = 0,
                normal = 1,
                high = 2,
            };
        };

        items: std.ArrayList(QueuedTask),
        allocator: std.mem.Allocator,
        capacity: usize,
        next_id: u64 = 0,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) Self {
            return .{
                .items = std.ArrayList(QueuedTask).init(allocator),
                .allocator = allocator,
                .capacity = capacity,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn enqueue(self: *Self, data: T) ThreadPoolError!u64 {
            return self.enqueueWithPriority(data, .normal);
        }

        pub fn enqueueWithPriority(self: *Self, data: T, priority: QueuedTask.Priority) ThreadPoolError!u64 {
            if (self.items.items.len >= self.capacity) {
                return ThreadPoolError.QueueFull;
            }

            const id = self.next_id;
            self.next_id += 1;
            self.items.append(.{
                .id = id,
                .data = data,
                .priority = priority,
                .queued_at = std.time.milliTimestamp(),
            }) catch {
                return ThreadPoolError.TaskRejected;
            };
            return id;
        }

        pub fn dequeue(self: *Self) ?QueuedTask {
            if (self.items.items.len == 0) return null;

            // Find highest priority task
            var best_idx: usize = 0;
            var best_priority: u8 = 0;

            for (self.items.items, 0..) |task, i| {
                const pri = @intFromEnum(task.priority);
                if (pri > best_priority) {
                    best_priority = pri;
                    best_idx = i;
                }
            }

            return self.items.orderedRemove(best_idx);
        }

        pub fn size(self: Self) usize {
            return self.items.items.len;
        }

        pub fn isEmpty(self: Self) bool {
            return self.items.items.len == 0;
        }

        pub fn isFull(self: Self) bool {
            return self.items.items.len >= self.capacity;
        }

        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        pub fn remainingCapacity(self: Self) usize {
            return self.capacity - self.items.items.len;
        }
    };
}

/// Thread pool executor
pub fn ThreadPoolExecutor(comptime T: type) type {
    return struct {
        const Self = @This();

        state: PoolState = .created,
        config: ThreadPoolConfig,
        workers: WorkerManager,
        queue: TaskQueue(T),
        stats: PoolStats = .{},
        creation_time: i64,

        pub const PoolStats = struct {
            tasks_submitted: usize = 0,
            tasks_completed: usize = 0,
            tasks_rejected: usize = 0,
            peak_workers: usize = 0,
            peak_queue_size: usize = 0,

            pub fn completionRate(self: PoolStats) f64 {
                if (self.tasks_submitted == 0) return 0;
                return @as(f64, @floatFromInt(self.tasks_completed)) / @as(f64, @floatFromInt(self.tasks_submitted));
            }

            pub fn rejectionRate(self: PoolStats) f64 {
                const total = self.tasks_submitted + self.tasks_rejected;
                if (total == 0) return 0;
                return @as(f64, @floatFromInt(self.tasks_rejected)) / @as(f64, @floatFromInt(total));
            }
        };

        pub fn init(allocator: std.mem.Allocator, config: ThreadPoolConfig) ThreadPoolError!Self {
            try config.validate();
            return .{
                .config = config,
                .workers = WorkerManager.init(allocator, config),
                .queue = TaskQueue(T).init(allocator, config.queue_capacity),
                .creation_time = std.time.milliTimestamp(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.workers.deinit();
            self.queue.deinit();
        }

        pub fn start(self: *Self) ThreadPoolError!void {
            if (self.state != .created) {
                return ThreadPoolError.PoolNotRunning;
            }
            self.state = .running;

            // Create minimum workers
            var i: usize = 0;
            while (i < self.config.min_workers) : (i += 1) {
                _ = try self.workers.createWorker();
            }
        }

        pub fn submit(self: *Self, task: T) ThreadPoolError!u64 {
            if (!self.state.canAcceptTasks()) {
                self.stats.tasks_rejected += 1;
                return ThreadPoolError.PoolShutdown;
            }

            const id = try self.queue.enqueue(task);
            self.stats.tasks_submitted += 1;

            // Update peak queue size
            if (self.queue.size() > self.stats.peak_queue_size) {
                self.stats.peak_queue_size = self.queue.size();
            }

            return id;
        }

        pub fn shutdown(self: *Self, wait: bool) void {
            self.state = .shutting_down;

            if (wait) {
                // Process remaining tasks
                while (!self.queue.isEmpty()) {
                    _ = self.queue.dequeue();
                    self.stats.tasks_completed += 1;
                }
            } else {
                self.queue.clear();
            }

            self.workers.terminateAll();
            self.state = .terminated;
        }

        pub fn isShutdown(self: Self) bool {
            return self.state.isTerminated();
        }

        pub fn getStats(self: Self) PoolStats {
            return self.stats;
        }

        pub fn getWorkerCount(self: Self) usize {
            return self.workers.getWorkerCount();
        }

        pub fn getQueueSize(self: Self) usize {
            return self.queue.size();
        }

        pub fn getActiveCount(self: Self) usize {
            return self.workers.getBusyCount();
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "pool_state_properties" {
    try testing.expect(!PoolState.created.isActive());
    try testing.expect(PoolState.running.isActive());
    try testing.expect(!PoolState.shutting_down.isActive());

    try testing.expect(PoolState.running.canAcceptTasks());
    try testing.expect(!PoolState.terminated.canAcceptTasks());
}

test "thread_pool_config_default" {
    const config = ThreadPoolConfig.init();
    try testing.expectEqual(@as(usize, 0), config.max_workers);
    try testing.expectEqual(@as(usize, 1000), config.queue_capacity);
    try config.validate();
}

test "thread_pool_config_with_workers" {
    const config = ThreadPoolConfig.withMaxWorkers(8);
    try testing.expectEqual(@as(usize, 8), config.max_workers);
    try config.validate();
}

test "thread_pool_config_with_range" {
    const config = ThreadPoolConfig.withRange(2, 8);
    try testing.expectEqual(@as(usize, 2), config.min_workers);
    try testing.expectEqual(@as(usize, 8), config.max_workers);
    try config.validate();
}

test "thread_pool_config_invalid" {
    const config = ThreadPoolConfig{ .min_workers = 10, .max_workers = 5 };
    try testing.expectError(ThreadPoolError.MaxWorkersExceeded, config.validate());
}

test "worker_info_basic" {
    var worker = WorkerInfo.init(1);

    try testing.expectEqual(@as(u64, 1), worker.id);
    try testing.expectEqual(WorkerInfo.State.idle, worker.state);
    try testing.expectEqual(@as(usize, 0), worker.tasks_completed);
}

test "worker_info_task_lifecycle" {
    var worker = WorkerInfo.init(1);

    worker.startTask();
    try testing.expect(worker.state.isWorking());
    try testing.expect(worker.getCurrentTaskDuration() != null);

    worker.completeTask();
    try testing.expectEqual(WorkerInfo.State.idle, worker.state);
    try testing.expectEqual(@as(usize, 1), worker.tasks_completed);
}

test "worker_info_terminate" {
    var worker = WorkerInfo.init(1);

    try testing.expect(worker.state.isAlive());

    worker.terminate();
    try testing.expect(!worker.state.isAlive());
    try testing.expectEqual(WorkerInfo.State.terminated, worker.state);
}

test "worker_manager_create" {
    var manager = WorkerManager.init(testing.allocator, ThreadPoolConfig.withMaxWorkers(4));
    defer manager.deinit();

    _ = try manager.createWorker();
    _ = try manager.createWorker();

    try testing.expectEqual(@as(usize, 2), manager.getWorkerCount());
    try testing.expectEqual(@as(usize, 2), manager.getIdleCount());
    try testing.expectEqual(@as(usize, 0), manager.getBusyCount());
}

test "worker_manager_max_workers" {
    var manager = WorkerManager.init(testing.allocator, ThreadPoolConfig.withMaxWorkers(2));
    defer manager.deinit();

    _ = try manager.createWorker();
    _ = try manager.createWorker();

    try testing.expectError(ThreadPoolError.MaxWorkersExceeded, manager.createWorker());
}

test "worker_manager_get_idle" {
    var manager = WorkerManager.init(testing.allocator, ThreadPoolConfig.withMaxWorkers(4));
    defer manager.deinit();

    _ = try manager.createWorker();
    var worker = manager.getIdleWorker().?;
    worker.startTask();

    try testing.expect(manager.getIdleWorker() == null); // No idle workers now

    _ = try manager.createWorker();
    try testing.expect(manager.getIdleWorker() != null);
}

test "task_queue_basic" {
    var queue = TaskQueue(i32).init(testing.allocator, 10);
    defer queue.deinit();

    try testing.expect(queue.isEmpty());
    try testing.expectEqual(@as(usize, 10), queue.remainingCapacity());

    _ = try queue.enqueue(42);
    try testing.expect(!queue.isEmpty());
    try testing.expectEqual(@as(usize, 1), queue.size());

    const task = queue.dequeue().?;
    try testing.expectEqual(@as(i32, 42), task.data);
    try testing.expect(queue.isEmpty());
}

test "task_queue_priority" {
    var queue = TaskQueue(i32).init(testing.allocator, 10);
    defer queue.deinit();

    _ = try queue.enqueueWithPriority(1, .low);
    _ = try queue.enqueueWithPriority(2, .high);
    _ = try queue.enqueueWithPriority(3, .normal);

    // Should dequeue in priority order: high, normal, low
    try testing.expectEqual(@as(i32, 2), queue.dequeue().?.data);
    try testing.expectEqual(@as(i32, 3), queue.dequeue().?.data);
    try testing.expectEqual(@as(i32, 1), queue.dequeue().?.data);
}

test "task_queue_full" {
    var queue = TaskQueue(i32).init(testing.allocator, 2);
    defer queue.deinit();

    _ = try queue.enqueue(1);
    _ = try queue.enqueue(2);

    try testing.expect(queue.isFull());
    try testing.expectError(ThreadPoolError.QueueFull, queue.enqueue(3));
}

test "thread_pool_executor_basic" {
    var pool = try ThreadPoolExecutor(i32).init(testing.allocator, ThreadPoolConfig.withMaxWorkers(4));
    defer pool.deinit();

    try testing.expectEqual(PoolState.created, pool.state);

    try pool.start();
    try testing.expectEqual(PoolState.running, pool.state);

    _ = try pool.submit(42);
    try testing.expectEqual(@as(usize, 1), pool.stats.tasks_submitted);
    try testing.expectEqual(@as(usize, 1), pool.getQueueSize());

    pool.shutdown(true);
    try testing.expect(pool.isShutdown());
}

test "thread_pool_executor_shutdown_without_wait" {
    var pool = try ThreadPoolExecutor(i32).init(testing.allocator, ThreadPoolConfig.withMaxWorkers(4));
    defer pool.deinit();

    try pool.start();
    _ = try pool.submit(1);
    _ = try pool.submit(2);
    _ = try pool.submit(3);

    pool.shutdown(false); // Don't wait - clear queue
    try testing.expectEqual(@as(usize, 0), pool.getQueueSize());
}

test "thread_pool_executor_reject_after_shutdown" {
    var pool = try ThreadPoolExecutor(i32).init(testing.allocator, ThreadPoolConfig.withMaxWorkers(4));
    defer pool.deinit();

    try pool.start();
    pool.shutdown(false);

    try testing.expectError(ThreadPoolError.PoolShutdown, pool.submit(42));
    try testing.expectEqual(@as(usize, 1), pool.stats.tasks_rejected);
}

test "thread_pool_stats" {
    var pool = try ThreadPoolExecutor(i32).init(testing.allocator, ThreadPoolConfig.withMaxWorkers(4));
    defer pool.deinit();

    try pool.start();
    _ = try pool.submit(1);
    _ = try pool.submit(2);

    pool.shutdown(true); // Wait processes tasks

    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 2), stats.tasks_submitted);
    try testing.expectEqual(@as(usize, 2), stats.tasks_completed);
    try testing.expectApproxEqAbs(@as(f64, 1.0), stats.completionRate(), 0.01);
}
