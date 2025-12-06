const std = @import("std");
const Task = @import("../task.zig").Task;
const Processor = @import("../processor.zig").Processor;

/// Yield strategies
pub const YieldStrategy = enum {
    /// Cooperative yield (task voluntarily gives up CPU)
    cooperative,

    /// Preemptive yield (forced by timer)
    preemptive,

    /// I/O wait (task waiting for I/O)
    io_wait,

    /// Channel wait (task waiting on channel)
    channel_wait,
};

/// Yield context - information about why and how a task yielded
pub const YieldContext = struct {
    /// Why did the task yield?
    strategy: YieldStrategy,

    /// Current task that's yielding
    task: *Task,

    /// Processor the task is running on
    processor: ?*Processor,

    /// Timestamp of yield
    timestamp: i128,

    /// Should task be re-queued immediately?
    requeue: bool,

    pub fn init(task: *Task, strategy: YieldStrategy) YieldContext {
        return YieldContext{
            .strategy = strategy,
            .task = task,
            .processor = null,
            .timestamp = std.time.nanoTimestamp(),
            .requeue = true,
        };
    }
};

/// Yielder - handles task yielding
pub const Yielder = struct {
    /// Current processor (if in processor context)
    current_processor: ?*Processor,

    /// Global task queue (for re-queuing)
    global_queue: *std.ArrayList(*Task),

    /// Global queue mutex
    global_mutex: *std.Thread.Mutex,

    /// Total yields
    total_yields: std.atomic.Value(u64),

    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        global_queue: *std.ArrayList(*Task),
        global_mutex: *std.Thread.Mutex,
    ) Yielder {
        return Yielder{
            .current_processor = null,
            .global_queue = global_queue,
            .global_mutex = global_mutex,
            .total_yields = std.atomic.Value(u64).init(0),
            .allocator = allocator,
        };
    }

    /// Yield current task (cooperative)
    pub fn yield(self: *Yielder, task: *Task) !void {
        var ctx = YieldContext.init(task, .cooperative);
        ctx.processor = self.current_processor;

        try self.yieldWithContext(&ctx);
    }

    /// Yield with specific strategy
    pub fn yieldWithContext(self: *Yielder, ctx: *YieldContext) !void {
        const task = ctx.task;

        // Record yield event
        task.recordYield();

        // Mark task as runnable (will be re-scheduled)
        task.makeRunnable();

        // Re-queue task based on strategy
        switch (ctx.strategy) {
            .cooperative => {
                // Try to re-queue to processor first
                if (ctx.processor) |p| {
                    const pushed = try p.pushTask(task);
                    if (pushed) {
                        _ = self.total_yields.fetchAdd(1, .monotonic);
                        return;
                    }
                }

                // Processor queue full, push to global
                try self.requeueToGlobal(task);
            },

            .preemptive => {
                // Preemptive yield - put at end of queue (lower priority)
                try self.requeueToGlobal(task);
            },

            .io_wait, .channel_wait => {
                // Don't re-queue waiting tasks
                // They will be re-queued when I/O/channel is ready
                task.makeWaiting();
            },
        }

        _ = self.total_yields.fetchAdd(1, .monotonic);
    }

    /// Re-queue task to global queue
    fn requeueToGlobal(self: *Yielder, task: *Task) !void {
        self.global_mutex.lock();
        defer self.global_mutex.unlock();

        try self.global_queue.append(self.allocator, task);
    }

    /// Get total yield count
    pub fn totalYields(self: *Yielder) u64 {
        return self.total_yields.load(.monotonic);
    }
};

/// Simple yielder (for basic scheduler)
pub const SimpleYielder = struct {
    /// Task queue
    queue: *std.ArrayList(*Task),

    /// Queue mutex
    mutex: *std.Thread.Mutex,

    /// Allocator
    allocator: std.mem.Allocator,

    /// Total yields
    total_yields: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        queue: *std.ArrayList(*Task),
        mutex: *std.Thread.Mutex,
    ) SimpleYielder {
        return SimpleYielder{
            .queue = queue,
            .mutex = mutex,
            .allocator = allocator,
            .total_yields = 0,
        };
    }

    /// Yield task
    pub fn yield(self: *SimpleYielder, task: *Task) !void {
        task.recordYield();
        task.makeRunnable();

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.queue.append(self.allocator, task);
        self.total_yields += 1;
    }
};

/// Cooperative yielding helpers
pub const CoopYield = struct {
    /// Yield point - task can yield here
    pub fn yieldPoint(task: *Task) bool {
        // Check if task should be preempted
        if (task.shouldPreempt()) {
            return true;
        }

        // Check if task has been running too long (10ms like Go)
        const now = std.time.nanoTimestamp();
        const elapsed = now - task.scheduled_at;
        const max_timeslice_ns = 10_000_000; // 10ms

        return elapsed > max_timeslice_ns;
    }

    /// Yield if needed
    pub fn yieldIfNeeded(task: *Task, yielder: *Yielder) !bool {
        if (yieldPoint(task)) {
            try yielder.yield(task);
            return true;
        }
        return false;
    }
};

/// Preemptive yielding (triggered by timer)
pub const PreemptYield = struct {
    /// Mark task for preemption
    pub fn markForPreemption(task: *Task) void {
        task.markPreempted();
    }

    /// Check if task should be preempted
    pub fn shouldPreempt(task: *Task) bool {
        return task.shouldPreempt();
    }

    /// Force preemption and re-queue
    pub fn forcePreempt(task: *Task, yielder: *Yielder) !void {
        var ctx = YieldContext.init(task, .preemptive);
        try yielder.yieldWithContext(&ctx);
    }
};
