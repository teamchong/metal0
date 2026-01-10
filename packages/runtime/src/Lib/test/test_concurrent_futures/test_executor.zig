//! test.test_concurrent_futures.test_executor - Executor base class and pool executor tests
//!
//! Tests for concurrent.futures Executor implementations including the abstract
//! Executor base class and concrete ThreadPoolExecutor/ProcessPoolExecutor.

const std = @import("std");
const testing = std.testing;

/// Error types for executor operations
pub const ExecutorError = error{
    ShutdownError,
    BrokenExecutorError,
    InvalidWorkerCount,
    TaskRejected,
    ExecutorNotRunning,
    MaxWorkersExceeded,
    InitializationFailed,
};

/// State of an executor
pub const ExecutorState = enum {
    created,
    running,
    shutting_down,
    shutdown,
    broken,

    pub fn isActive(self: ExecutorState) bool {
        return self == .created or self == .running;
    }

    pub fn canAcceptWork(self: ExecutorState) bool {
        return self == .running;
    }

    pub fn isTerminal(self: ExecutorState) bool {
        return self == .shutdown or self == .broken;
    }
};

/// Configuration for executor initialization
pub const ExecutorConfig = struct {
    max_workers: usize = 0, // 0 means auto-detect
    thread_name_prefix: []const u8 = "Executor",
    initializer: ?*const fn () void = null,
    initargs: ?*const anyopaque = null,
    max_pending_tasks: usize = 1000,
    idle_timeout_ns: u64 = 60 * std.time.ns_per_s,

    pub fn withMaxWorkers(max_workers: usize) ExecutorConfig {
        return .{ .max_workers = max_workers };
    }

    pub fn withPrefix(prefix: []const u8) ExecutorConfig {
        return .{ .thread_name_prefix = prefix };
    }

    pub fn default() ExecutorConfig {
        return .{};
    }

    pub fn validate(self: ExecutorConfig) ExecutorError!void {
        if (self.max_workers > 1024) {
            return ExecutorError.MaxWorkersExceeded;
        }
        if (self.max_pending_tasks == 0) {
            return ExecutorError.InvalidWorkerCount;
        }
    }
};

/// Statistics for executor monitoring
pub const ExecutorStats = struct {
    tasks_submitted: usize = 0,
    tasks_completed: usize = 0,
    tasks_failed: usize = 0,
    tasks_cancelled: usize = 0,
    active_workers: usize = 0,
    idle_workers: usize = 0,
    peak_workers: usize = 0,
    queue_size: usize = 0,
    total_execution_time_ns: u64 = 0,

    pub fn reset(self: *ExecutorStats) void {
        self.* = .{};
    }

    pub fn recordTaskSubmitted(self: *ExecutorStats) void {
        self.tasks_submitted += 1;
        self.queue_size += 1;
    }

    pub fn recordTaskCompleted(self: *ExecutorStats, execution_time_ns: u64) void {
        self.tasks_completed += 1;
        self.total_execution_time_ns += execution_time_ns;
        if (self.queue_size > 0) self.queue_size -= 1;
    }

    pub fn recordTaskFailed(self: *ExecutorStats) void {
        self.tasks_failed += 1;
        if (self.queue_size > 0) self.queue_size -= 1;
    }

    pub fn recordTaskCancelled(self: *ExecutorStats) void {
        self.tasks_cancelled += 1;
        if (self.queue_size > 0) self.queue_size -= 1;
    }

    pub fn updateWorkerCount(self: *ExecutorStats, active: usize, idle: usize) void {
        self.active_workers = active;
        self.idle_workers = idle;
        const total = active + idle;
        if (total > self.peak_workers) {
            self.peak_workers = total;
        }
    }

    pub fn averageExecutionTimeNs(self: ExecutorStats) u64 {
        if (self.tasks_completed == 0) return 0;
        return self.total_execution_time_ns / self.tasks_completed;
    }

    pub fn successRate(self: ExecutorStats) f64 {
        const total = self.tasks_completed + self.tasks_failed;
        if (total == 0) return 1.0;
        return @as(f64, @floatFromInt(self.tasks_completed)) / @as(f64, @floatFromInt(total));
    }
};

/// Abstract Executor base - defines the interface for all executors
pub const Executor = struct {
    const Self = @This();

    state: ExecutorState = .created,
    config: ExecutorConfig = .{},
    stats: ExecutorStats = .{},
    allocator: std.mem.Allocator,
    creation_time: i64,
    shutdown_time: ?i64 = null,

    pub fn init(allocator: std.mem.Allocator, config: ExecutorConfig) ExecutorError!Self {
        try config.validate();
        return .{
            .allocator = allocator,
            .config = config,
            .creation_time = std.time.milliTimestamp(),
        };
    }

    pub fn start(self: *Self) ExecutorError!void {
        if (self.state != .created) {
            return ExecutorError.ExecutorNotRunning;
        }
        self.state = .running;
    }

    pub fn shutdown(self: *Self, wait: bool) void {
        if (self.state.isTerminal()) return;

        self.state = .shutting_down;
        self.shutdown_time = std.time.milliTimestamp();

        if (wait) {
            // In a real implementation, wait for pending tasks
            self.waitForPendingTasks();
        }

        self.state = .shutdown;
    }

    pub fn shutdownNow(self: *Self) void {
        self.state = .shutdown;
        self.shutdown_time = std.time.milliTimestamp();
    }

    fn waitForPendingTasks(self: *Self) void {
        // Simulate waiting - in real impl would block until queue empty
        _ = self;
    }

    pub fn isShutdown(self: Self) bool {
        return self.state == .shutdown;
    }

    pub fn isRunning(self: Self) bool {
        return self.state == .running;
    }

    pub fn getState(self: Self) ExecutorState {
        return self.state;
    }

    pub fn getStats(self: Self) ExecutorStats {
        return self.stats;
    }

    pub fn getUptime(self: Self) i64 {
        const end_time = self.shutdown_time orelse std.time.milliTimestamp();
        return end_time - self.creation_time;
    }

    pub fn markBroken(self: *Self) void {
        self.state = .broken;
    }
};

/// ThreadPoolExecutor - executes callables in a pool of threads
pub fn ThreadPoolExecutor(comptime max_workers_limit: usize) type {
    return struct {
        const Self = @This();

        base: Executor,
        max_workers: usize,
        active_count: usize = 0,
        pending_count: usize = 0,
        thread_name_prefix: []const u8,

        pub fn init(allocator: std.mem.Allocator) ExecutorError!Self {
            return initWithConfig(allocator, ExecutorConfig.default());
        }

        pub fn initWithConfig(allocator: std.mem.Allocator, config: ExecutorConfig) ExecutorError!Self {
            const base = try Executor.init(allocator, config);
            const workers = if (config.max_workers == 0)
                @min(max_workers_limit, 4) // Default to 4 or limit
            else
                @min(config.max_workers, max_workers_limit);

            return .{
                .base = base,
                .max_workers = workers,
                .thread_name_prefix = config.thread_name_prefix,
            };
        }

        pub fn start(self: *Self) ExecutorError!void {
            try self.base.start();
        }

        pub fn submit(self: *Self, comptime F: type, func: F) ExecutorError!void {
            if (!self.base.state.canAcceptWork()) {
                return ExecutorError.ShutdownError;
            }
            _ = func;
            self.pending_count += 1;
            self.base.stats.recordTaskSubmitted();
        }

        pub fn shutdown(self: *Self, wait: bool) void {
            self.base.shutdown(wait);
        }

        pub fn shutdownNow(self: *Self) usize {
            const pending = self.pending_count;
            self.base.shutdownNow();
            self.pending_count = 0;
            return pending;
        }

        pub fn isShutdown(self: Self) bool {
            return self.base.isShutdown();
        }

        pub fn getMaxWorkers(self: Self) usize {
            return self.max_workers;
        }

        pub fn getActiveCount(self: Self) usize {
            return self.active_count;
        }

        pub fn getPendingCount(self: Self) usize {
            return self.pending_count;
        }

        pub fn getStats(self: Self) ExecutorStats {
            return self.base.stats;
        }
    };
}

/// ProcessPoolExecutor - executes callables in a pool of processes
pub fn ProcessPoolExecutor(comptime max_workers_limit: usize) type {
    return struct {
        const Self = @This();

        base: Executor,
        max_workers: usize,
        mp_context: ?*const anyopaque = null,
        max_tasks_per_child: ?usize = null,

        pub fn init(allocator: std.mem.Allocator) ExecutorError!Self {
            return initWithConfig(allocator, ExecutorConfig.default());
        }

        pub fn initWithConfig(allocator: std.mem.Allocator, config: ExecutorConfig) ExecutorError!Self {
            const base = try Executor.init(allocator, config);
            const workers = if (config.max_workers == 0)
                @min(max_workers_limit, 4)
            else
                @min(config.max_workers, max_workers_limit);

            return .{
                .base = base,
                .max_workers = workers,
            };
        }

        pub fn start(self: *Self) ExecutorError!void {
            try self.base.start();
        }

        pub fn shutdown(self: *Self, wait: bool) void {
            self.base.shutdown(wait);
        }

        pub fn isShutdown(self: Self) bool {
            return self.base.isShutdown();
        }

        pub fn getMaxWorkers(self: Self) usize {
            return self.max_workers;
        }

        pub fn setMaxTasksPerChild(self: *Self, max_tasks: usize) void {
            self.max_tasks_per_child = max_tasks;
        }

        pub fn getMaxTasksPerChild(self: Self) ?usize {
            return self.max_tasks_per_child;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "executor_state_transitions" {
    const config = ExecutorConfig.default();
    var executor = try Executor.init(testing.allocator, config);

    try testing.expectEqual(ExecutorState.created, executor.state);
    try testing.expect(executor.state.isActive());
    try testing.expect(!executor.state.canAcceptWork());

    try executor.start();
    try testing.expectEqual(ExecutorState.running, executor.state);
    try testing.expect(executor.state.canAcceptWork());

    executor.shutdown(false);
    try testing.expectEqual(ExecutorState.shutdown, executor.state);
    try testing.expect(executor.state.isTerminal());
}

test "executor_config_validation" {
    // Valid config
    const valid = ExecutorConfig.withMaxWorkers(4);
    try valid.validate();

    // Invalid config - too many workers
    const invalid = ExecutorConfig{ .max_workers = 2000 };
    try testing.expectError(ExecutorError.MaxWorkersExceeded, invalid.validate());

    // Invalid config - zero pending tasks
    const zero_pending = ExecutorConfig{ .max_pending_tasks = 0 };
    try testing.expectError(ExecutorError.InvalidWorkerCount, zero_pending.validate());
}

test "executor_stats_tracking" {
    var stats = ExecutorStats{};

    stats.recordTaskSubmitted();
    try testing.expectEqual(@as(usize, 1), stats.tasks_submitted);
    try testing.expectEqual(@as(usize, 1), stats.queue_size);

    stats.recordTaskCompleted(1000);
    try testing.expectEqual(@as(usize, 1), stats.tasks_completed);
    try testing.expectEqual(@as(usize, 0), stats.queue_size);
    try testing.expectEqual(@as(u64, 1000), stats.averageExecutionTimeNs());

    stats.recordTaskSubmitted();
    stats.recordTaskFailed();
    try testing.expectEqual(@as(usize, 1), stats.tasks_failed);
    try testing.expectApproxEqAbs(@as(f64, 0.5), stats.successRate(), 0.01);
}

test "thread_pool_executor_basic" {
    var pool = try ThreadPoolExecutor(8).init(testing.allocator);

    try testing.expectEqual(@as(usize, 4), pool.getMaxWorkers()); // Default workers
    try testing.expect(!pool.isShutdown());

    try pool.start();
    try testing.expect(pool.base.isRunning());

    pool.shutdown(false);
    try testing.expect(pool.isShutdown());
}

test "thread_pool_executor_custom_config" {
    const config = ExecutorConfig{
        .max_workers = 2,
        .thread_name_prefix = "CustomPool",
    };
    var pool = try ThreadPoolExecutor(8).initWithConfig(testing.allocator, config);

    try testing.expectEqual(@as(usize, 2), pool.getMaxWorkers());
    try testing.expectEqualStrings("CustomPool", pool.thread_name_prefix);
}

test "thread_pool_shutdown_now" {
    var pool = try ThreadPoolExecutor(4).init(testing.allocator);
    try pool.start();

    // Simulate pending work
    pool.pending_count = 5;

    const cancelled = pool.shutdownNow();
    try testing.expectEqual(@as(usize, 5), cancelled);
    try testing.expectEqual(@as(usize, 0), pool.getPendingCount());
    try testing.expect(pool.isShutdown());
}

test "process_pool_executor_basic" {
    var pool = try ProcessPoolExecutor(4).init(testing.allocator);

    try testing.expectEqual(@as(usize, 4), pool.getMaxWorkers());
    try testing.expect(pool.getMaxTasksPerChild() == null);

    pool.setMaxTasksPerChild(100);
    try testing.expectEqual(@as(usize, 100), pool.getMaxTasksPerChild().?);

    try pool.start();
    pool.shutdown(true);
    try testing.expect(pool.isShutdown());
}

test "executor_uptime_tracking" {
    const config = ExecutorConfig.default();
    var executor = try Executor.init(testing.allocator, config);

    try executor.start();

    // Sleep briefly to accumulate uptime
    std.time.sleep(10 * std.time.ns_per_ms);

    const uptime = executor.getUptime();
    try testing.expect(uptime >= 10);

    executor.shutdown(false);
    const final_uptime = executor.getUptime();
    try testing.expect(final_uptime >= uptime);
}

test "executor_worker_stats_update" {
    var stats = ExecutorStats{};

    stats.updateWorkerCount(3, 1);
    try testing.expectEqual(@as(usize, 3), stats.active_workers);
    try testing.expectEqual(@as(usize, 1), stats.idle_workers);
    try testing.expectEqual(@as(usize, 4), stats.peak_workers);

    stats.updateWorkerCount(2, 0);
    try testing.expectEqual(@as(usize, 2), stats.active_workers);
    try testing.expectEqual(@as(usize, 4), stats.peak_workers); // Peak unchanged
}
