//! test.test_concurrent_futures.test_process_pool - ProcessPoolExecutor tests
//!
//! Tests for ProcessPoolExecutor including process management, inter-process
//! communication, worker initialization, and max_tasks_per_child behavior.

const std = @import("std");
const testing = std.testing;

/// Error types for process pool operations
pub const ProcessPoolError = error{
    PoolNotRunning,
    PoolShutdown,
    MaxWorkersExceeded,
    ProcessCreationFailed,
    TaskRejected,
    ProcessCommunicationFailed,
    SerializationFailed,
    DeserializationFailed,
    InitializerFailed,
    ProcessDied,
};

/// Process pool state
pub const ProcessPoolState = enum {
    created,
    running,
    shutting_down,
    terminated,

    pub fn isActive(self: ProcessPoolState) bool {
        return self == .running;
    }

    pub fn canAcceptTasks(self: ProcessPoolState) bool {
        return self == .running;
    }

    pub fn isTerminated(self: ProcessPoolState) bool {
        return self == .terminated;
    }
};

/// Configuration for process pool
pub const ProcessPoolConfig = struct {
    max_workers: usize = 0, // 0 means auto-detect (os.cpu_count())
    mp_context: ?[]const u8 = null, // spawn, fork, forkserver
    initializer: ?*const fn () void = null,
    initargs: ?*const anyopaque = null,
    max_tasks_per_child: ?usize = null, // None means unlimited
    queue_size: usize = 0, // 0 means unlimited

    pub fn init() ProcessPoolConfig {
        return .{};
    }

    pub fn withMaxWorkers(max_workers: usize) ProcessPoolConfig {
        return .{ .max_workers = max_workers };
    }

    pub fn withMaxTasksPerChild(max_tasks: usize) ProcessPoolConfig {
        return .{ .max_tasks_per_child = max_tasks };
    }

    pub fn withInitializer(initializer: *const fn () void) ProcessPoolConfig {
        return .{ .initializer = initializer };
    }

    pub fn withContext(ctx: []const u8) ProcessPoolConfig {
        return .{ .mp_context = ctx };
    }

    pub fn validate(self: ProcessPoolConfig) ProcessPoolError!void {
        if (self.mp_context) |ctx| {
            if (!std.mem.eql(u8, ctx, "spawn") and
                !std.mem.eql(u8, ctx, "fork") and
                !std.mem.eql(u8, ctx, "forkserver"))
            {
                return ProcessPoolError.ProcessCreationFailed;
            }
        }
    }
};

/// Worker process information
pub const ProcessWorkerInfo = struct {
    const Self = @This();

    id: u64,
    pid: ?i32 = null, // Simulated PID
    state: State = .initializing,
    tasks_completed: usize = 0,
    creation_time: i64,
    last_active_time: i64,
    exit_code: ?i32 = null,

    pub const State = enum {
        initializing,
        ready,
        busy,
        terminating,
        terminated,
        crashed,

        pub fn isHealthy(self: State) bool {
            return self == .ready or self == .busy;
        }

        pub fn isAlive(self: State) bool {
            return self != .terminated and self != .crashed;
        }

        pub fn canAcceptWork(self: State) bool {
            return self == .ready;
        }
    };

    pub fn init(id: u64) Self {
        const now = std.time.milliTimestamp();
        return .{
            .id = id,
            .pid = @as(i32, @intCast(id + 1000)), // Simulated PID
            .creation_time = now,
            .last_active_time = now,
        };
    }

    pub fn markReady(self: *Self) void {
        self.state = .ready;
    }

    pub fn startTask(self: *Self) void {
        self.state = .busy;
    }

    pub fn completeTask(self: *Self) void {
        self.state = .ready;
        self.tasks_completed += 1;
        self.last_active_time = std.time.milliTimestamp();
    }

    pub fn terminate(self: *Self, exit_code: i32) void {
        self.state = .terminated;
        self.exit_code = exit_code;
    }

    pub fn crash(self: *Self, exit_code: i32) void {
        self.state = .crashed;
        self.exit_code = exit_code;
    }

    pub fn getUptime(self: Self) i64 {
        return std.time.milliTimestamp() - self.creation_time;
    }

    pub fn shouldRestart(self: Self, max_tasks: ?usize) bool {
        if (max_tasks) |max| {
            return self.tasks_completed >= max;
        }
        return false;
    }
};

/// Process pool worker manager
pub const ProcessWorkerManager = struct {
    const Self = @This();

    workers: std.ArrayList(ProcessWorkerInfo),
    allocator: std.mem.Allocator,
    next_worker_id: u64 = 0,
    config: ProcessPoolConfig,
    crashed_count: usize = 0,
    restarted_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: ProcessPoolConfig) Self {
        return .{
            .workers = std.ArrayList(ProcessWorkerInfo).init(allocator),
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.workers.deinit();
    }

    pub fn createWorker(self: *Self) ProcessPoolError!*ProcessWorkerInfo {
        if (self.config.max_workers > 0 and self.getAliveCount() >= self.config.max_workers) {
            return ProcessPoolError.MaxWorkersExceeded;
        }

        var worker = ProcessWorkerInfo.init(self.next_worker_id);
        self.next_worker_id += 1;

        // Simulate initialization
        if (self.config.initializer) |initializer| {
            initializer();
        }
        worker.markReady();

        self.workers.append(worker) catch {
            return ProcessPoolError.ProcessCreationFailed;
        };
        return &self.workers.items[self.workers.items.len - 1];
    }

    pub fn getWorkerCount(self: Self) usize {
        return self.workers.items.len;
    }

    pub fn getAliveCount(self: Self) usize {
        var count: usize = 0;
        for (self.workers.items) |w| {
            if (w.state.isAlive()) count += 1;
        }
        return count;
    }

    pub fn getHealthyCount(self: Self) usize {
        var count: usize = 0;
        for (self.workers.items) |w| {
            if (w.state.isHealthy()) count += 1;
        }
        return count;
    }

    pub fn getBusyCount(self: Self) usize {
        var count: usize = 0;
        for (self.workers.items) |w| {
            if (w.state == .busy) count += 1;
        }
        return count;
    }

    pub fn getAvailableWorker(self: *Self) ?*ProcessWorkerInfo {
        for (self.workers.items) |*w| {
            if (w.state.canAcceptWork()) return w;
        }
        return null;
    }

    pub fn terminateAll(self: *Self) void {
        for (self.workers.items) |*w| {
            if (w.state.isAlive()) {
                w.terminate(0);
            }
        }
    }

    pub fn restartCrashedWorkers(self: *Self) !usize {
        var restarted: usize = 0;
        for (self.workers.items) |*w| {
            if (w.state == .crashed) {
                w.* = ProcessWorkerInfo.init(self.next_worker_id);
                self.next_worker_id += 1;
                w.markReady();
                restarted += 1;
                self.restarted_count += 1;
            }
        }
        return restarted;
    }

    pub fn restartExpiredWorkers(self: *Self) !usize {
        if (self.config.max_tasks_per_child == null) return 0;

        var restarted: usize = 0;
        for (self.workers.items) |*w| {
            if (w.shouldRestart(self.config.max_tasks_per_child)) {
                w.terminate(0);
                w.* = ProcessWorkerInfo.init(self.next_worker_id);
                self.next_worker_id += 1;
                w.markReady();
                restarted += 1;
                self.restarted_count += 1;
            }
        }
        return restarted;
    }

    pub fn getTotalTasksCompleted(self: Self) usize {
        var total: usize = 0;
        for (self.workers.items) |w| {
            total += w.tasks_completed;
        }
        return total;
    }
};

/// Inter-process message types
pub const IPCMessage = struct {
    const Self = @This();

    pub const Type = enum {
        task_submit,
        task_result,
        task_error,
        worker_ready,
        worker_exit,
        shutdown,
    };

    msg_type: Type,
    task_id: ?u64 = null,
    worker_id: ?u64 = null,
    timestamp: i64,
    payload_size: usize = 0,

    pub fn taskSubmit(task_id: u64) Self {
        return .{
            .msg_type = .task_submit,
            .task_id = task_id,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn taskResult(task_id: u64, worker_id: u64) Self {
        return .{
            .msg_type = .task_result,
            .task_id = task_id,
            .worker_id = worker_id,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn taskError(task_id: u64, worker_id: u64) Self {
        return .{
            .msg_type = .task_error,
            .task_id = task_id,
            .worker_id = worker_id,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn shutdown() Self {
        return .{
            .msg_type = .shutdown,
            .timestamp = std.time.milliTimestamp(),
        };
    }
};

/// Process pool executor
pub fn ProcessPoolExecutor(comptime T: type) type {
    return struct {
        const Self = @This();

        state: ProcessPoolState = .created,
        config: ProcessPoolConfig,
        workers: ProcessWorkerManager,
        pending_tasks: std.ArrayList(PendingTask),
        stats: PoolStats = .{},
        allocator: std.mem.Allocator,
        creation_time: i64,

        pub const PendingTask = struct {
            id: u64,
            data: T,
            submitted_at: i64,
        };

        pub const PoolStats = struct {
            tasks_submitted: usize = 0,
            tasks_completed: usize = 0,
            tasks_failed: usize = 0,
            workers_created: usize = 0,
            workers_crashed: usize = 0,
            workers_restarted: usize = 0,

            pub fn successRate(self: PoolStats) f64 {
                const total = self.tasks_completed + self.tasks_failed;
                if (total == 0) return 0;
                return @as(f64, @floatFromInt(self.tasks_completed)) / @as(f64, @floatFromInt(total));
            }

            pub fn crashRate(self: PoolStats) f64 {
                if (self.workers_created == 0) return 0;
                return @as(f64, @floatFromInt(self.workers_crashed)) / @as(f64, @floatFromInt(self.workers_created));
            }
        };

        pub fn init(allocator: std.mem.Allocator, config: ProcessPoolConfig) ProcessPoolError!Self {
            try config.validate();
            return .{
                .config = config,
                .workers = ProcessWorkerManager.init(allocator, config),
                .pending_tasks = std.ArrayList(PendingTask).init(allocator),
                .allocator = allocator,
                .creation_time = std.time.milliTimestamp(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.workers.deinit();
            self.pending_tasks.deinit();
        }

        pub fn start(self: *Self) ProcessPoolError!void {
            if (self.state != .created) {
                return ProcessPoolError.PoolNotRunning;
            }

            // Determine number of workers
            const num_workers = if (self.config.max_workers == 0) 4 else self.config.max_workers;

            // Create workers
            var i: usize = 0;
            while (i < num_workers) : (i += 1) {
                _ = try self.workers.createWorker();
                self.stats.workers_created += 1;
            }

            self.state = .running;
        }

        pub fn submit(self: *Self, task: T) ProcessPoolError!u64 {
            if (!self.state.canAcceptTasks()) {
                return ProcessPoolError.PoolShutdown;
            }

            const task_id = self.stats.tasks_submitted;
            self.stats.tasks_submitted += 1;

            self.pending_tasks.append(.{
                .id = task_id,
                .data = task,
                .submitted_at = std.time.milliTimestamp(),
            }) catch {
                return ProcessPoolError.TaskRejected;
            };

            return task_id;
        }

        pub fn processNextTask(self: *Self) bool {
            if (self.pending_tasks.items.len == 0) return false;

            if (self.workers.getAvailableWorker()) |worker| {
                const task = self.pending_tasks.orderedRemove(0);
                _ = task;
                worker.startTask();
                worker.completeTask();
                self.stats.tasks_completed += 1;
                return true;
            }

            return false;
        }

        pub fn shutdown(self: *Self, wait: bool) void {
            self.state = .shutting_down;

            if (wait) {
                while (self.pending_tasks.items.len > 0) {
                    _ = self.processNextTask();
                }
            } else {
                self.pending_tasks.clearRetainingCapacity();
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

        pub fn getPendingCount(self: Self) usize {
            return self.pending_tasks.items.len;
        }

        pub fn setMaxTasksPerChild(self: *Self, max_tasks: usize) void {
            self.config.max_tasks_per_child = max_tasks;
        }

        pub fn getMaxTasksPerChild(self: Self) ?usize {
            return self.config.max_tasks_per_child;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "process_pool_state_properties" {
    try testing.expect(!ProcessPoolState.created.isActive());
    try testing.expect(ProcessPoolState.running.isActive());
    try testing.expect(!ProcessPoolState.shutting_down.isActive());

    try testing.expect(ProcessPoolState.running.canAcceptTasks());
    try testing.expect(!ProcessPoolState.terminated.canAcceptTasks());
}

test "process_pool_config_default" {
    const config = ProcessPoolConfig.init();
    try testing.expectEqual(@as(usize, 0), config.max_workers);
    try testing.expect(config.max_tasks_per_child == null);
    try testing.expect(config.initializer == null);
    try config.validate();
}

test "process_pool_config_with_max_tasks" {
    const config = ProcessPoolConfig.withMaxTasksPerChild(100);
    try testing.expectEqual(@as(usize, 100), config.max_tasks_per_child.?);
}

test "process_pool_config_context_validation" {
    const valid_spawn = ProcessPoolConfig.withContext("spawn");
    try valid_spawn.validate();

    const valid_fork = ProcessPoolConfig.withContext("fork");
    try valid_fork.validate();

    const invalid = ProcessPoolConfig.withContext("invalid");
    try testing.expectError(ProcessPoolError.ProcessCreationFailed, invalid.validate());
}

test "process_worker_info_basic" {
    const worker = ProcessWorkerInfo.init(1);

    try testing.expectEqual(@as(u64, 1), worker.id);
    try testing.expect(worker.pid != null);
    try testing.expectEqual(ProcessWorkerInfo.State.initializing, worker.state);
}

test "process_worker_info_lifecycle" {
    var worker = ProcessWorkerInfo.init(1);

    worker.markReady();
    try testing.expect(worker.state.canAcceptWork());

    worker.startTask();
    try testing.expect(!worker.state.canAcceptWork());

    worker.completeTask();
    try testing.expect(worker.state.canAcceptWork());
    try testing.expectEqual(@as(usize, 1), worker.tasks_completed);
}

test "process_worker_info_crash" {
    var worker = ProcessWorkerInfo.init(1);
    worker.markReady();

    try testing.expect(worker.state.isHealthy());

    worker.crash(-1);
    try testing.expect(!worker.state.isHealthy());
    try testing.expect(!worker.state.isAlive());
    try testing.expectEqual(@as(i32, -1), worker.exit_code.?);
}

test "process_worker_info_should_restart" {
    var worker = ProcessWorkerInfo.init(1);
    worker.markReady();

    // No limit - should not restart
    try testing.expect(!worker.shouldRestart(null));

    // Under limit
    try testing.expect(!worker.shouldRestart(10));

    // Simulate reaching limit
    worker.tasks_completed = 10;
    try testing.expect(worker.shouldRestart(10));
}

test "process_worker_manager_create" {
    var manager = ProcessWorkerManager.init(testing.allocator, ProcessPoolConfig.withMaxWorkers(4));
    defer manager.deinit();

    _ = try manager.createWorker();
    _ = try manager.createWorker();

    try testing.expectEqual(@as(usize, 2), manager.getWorkerCount());
    try testing.expectEqual(@as(usize, 2), manager.getHealthyCount());
}

test "process_worker_manager_max_workers" {
    var manager = ProcessWorkerManager.init(testing.allocator, ProcessPoolConfig.withMaxWorkers(2));
    defer manager.deinit();

    _ = try manager.createWorker();
    _ = try manager.createWorker();

    try testing.expectError(ProcessPoolError.MaxWorkersExceeded, manager.createWorker());
}

test "process_worker_manager_restart_expired" {
    const config = ProcessPoolConfig.withMaxTasksPerChild(5);
    var manager = ProcessWorkerManager.init(testing.allocator, config);
    defer manager.deinit();

    var worker = try manager.createWorker();

    // Simulate completing enough tasks
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        worker.startTask();
        worker.completeTask();
    }

    const restarted = try manager.restartExpiredWorkers();
    try testing.expectEqual(@as(usize, 1), restarted);
    try testing.expectEqual(@as(usize, 1), manager.restarted_count);
}

test "ipc_message_types" {
    const submit = IPCMessage.taskSubmit(1);
    try testing.expectEqual(IPCMessage.Type.task_submit, submit.msg_type);
    try testing.expectEqual(@as(u64, 1), submit.task_id.?);

    const result = IPCMessage.taskResult(1, 2);
    try testing.expectEqual(IPCMessage.Type.task_result, result.msg_type);
    try testing.expectEqual(@as(u64, 2), result.worker_id.?);

    const shutdown = IPCMessage.shutdown();
    try testing.expectEqual(IPCMessage.Type.shutdown, shutdown.msg_type);
}

test "process_pool_executor_basic" {
    var pool = try ProcessPoolExecutor(i32).init(testing.allocator, ProcessPoolConfig.withMaxWorkers(2));
    defer pool.deinit();

    try testing.expectEqual(ProcessPoolState.created, pool.state);

    try pool.start();
    try testing.expectEqual(ProcessPoolState.running, pool.state);
    try testing.expectEqual(@as(usize, 2), pool.getWorkerCount());

    _ = try pool.submit(42);
    try testing.expectEqual(@as(usize, 1), pool.stats.tasks_submitted);

    pool.shutdown(true);
    try testing.expect(pool.isShutdown());
}

test "process_pool_executor_process_tasks" {
    var pool = try ProcessPoolExecutor(i32).init(testing.allocator, ProcessPoolConfig.withMaxWorkers(2));
    defer pool.deinit();

    try pool.start();
    _ = try pool.submit(1);
    _ = try pool.submit(2);
    _ = try pool.submit(3);

    try testing.expectEqual(@as(usize, 3), pool.getPendingCount());

    while (pool.processNextTask()) {}

    try testing.expectEqual(@as(usize, 0), pool.getPendingCount());
    try testing.expectEqual(@as(usize, 3), pool.stats.tasks_completed);
}

test "process_pool_executor_max_tasks_per_child" {
    var pool = try ProcessPoolExecutor(i32).init(testing.allocator, ProcessPoolConfig.withMaxWorkers(2));
    defer pool.deinit();

    try testing.expect(pool.getMaxTasksPerChild() == null);

    pool.setMaxTasksPerChild(50);
    try testing.expectEqual(@as(usize, 50), pool.getMaxTasksPerChild().?);
}

test "process_pool_executor_reject_after_shutdown" {
    var pool = try ProcessPoolExecutor(i32).init(testing.allocator, ProcessPoolConfig.withMaxWorkers(2));
    defer pool.deinit();

    try pool.start();
    pool.shutdown(false);

    try testing.expectError(ProcessPoolError.PoolShutdown, pool.submit(42));
}

test "process_pool_stats" {
    var pool = try ProcessPoolExecutor(i32).init(testing.allocator, ProcessPoolConfig.withMaxWorkers(2));
    defer pool.deinit();

    try pool.start();
    _ = try pool.submit(1);
    _ = try pool.submit(2);

    while (pool.processNextTask()) {}

    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 2), stats.tasks_submitted);
    try testing.expectEqual(@as(usize, 2), stats.tasks_completed);
    try testing.expectEqual(@as(usize, 2), stats.workers_created);
    try testing.expectApproxEqAbs(@as(f64, 1.0), stats.successRate(), 0.01);
}
