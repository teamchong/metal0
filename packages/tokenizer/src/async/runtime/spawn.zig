const std = @import("std");
const Task = @import("../task.zig").Task;
const Processor = @import("../processor.zig").Processor;

/// Task spawner - handles creating and scheduling new tasks
pub const TaskSpawner = struct {
    /// Next task ID (atomic counter)
    next_task_id: std.atomic.Value(usize),

    /// All processors (for load balancing)
    processors: []Processor,

    /// Global task queue (for overflow)
    global_queue: *std.ArrayList(*Task),

    /// Global queue mutex
    global_mutex: *std.Thread.Mutex,

    /// Allocator
    allocator: std.mem.Allocator,

    /// Total tasks spawned
    total_spawned: std.atomic.Value(u64),

    /// Round-robin index for processor selection
    rr_index: std.atomic.Value(usize),

    pub fn init(
        allocator: std.mem.Allocator,
        processors: []Processor,
        global_queue: *std.ArrayList(*Task),
        global_mutex: *std.Thread.Mutex,
    ) TaskSpawner {
        return TaskSpawner{
            .next_task_id = std.atomic.Value(usize).init(1),
            .processors = processors,
            .global_queue = global_queue,
            .global_mutex = global_mutex,
            .allocator = allocator,
            .total_spawned = std.atomic.Value(u64).init(0),
            .rr_index = std.atomic.Value(usize).init(0),
        };
    }

    /// Spawn new task (like Go's `go` keyword)
    pub fn spawn(self: *TaskSpawner, func: @import("../task.zig").TaskFn, context: *anyopaque) !*Task {
        // Create new task with unique ID
        const task_id = self.next_task_id.fetchAdd(1, .monotonic);
        const task = try self.allocator.create(Task);
        errdefer self.allocator.destroy(task);

        task.* = Task.init(task_id, func, context);

        // Try to push to a processor's local queue (load balancing)
        const pushed = try self.pushToProcessor(task);

        if (!pushed) {
            // Processor queue was full, push to global queue
            try self.pushToGlobalQueue(task);
        }

        // Update stats
        _ = self.total_spawned.fetchAdd(1, .monotonic);

        return task;
    }

    /// Spawn task with stack allocation
    pub fn spawnWithStack(self: *TaskSpawner, func: @import("../task.zig").TaskFn, context: *anyopaque) !*Task {
        const task_id = self.next_task_id.fetchAdd(1, .monotonic);
        const task = try self.allocator.create(Task);
        errdefer self.allocator.destroy(task);

        task.* = try Task.initWithStack(self.allocator, task_id, func, context);

        // Try to push to processor
        const pushed = try self.pushToProcessor(task);

        if (!pushed) {
            try self.pushToGlobalQueue(task);
        }

        _ = self.total_spawned.fetchAdd(1, .monotonic);

        return task;
    }

    /// Push task to a processor's local queue (round-robin load balancing)
    fn pushToProcessor(self: *TaskSpawner, task: *Task) !bool {
        if (self.processors.len == 0) {
            return false;
        }

        // Round-robin processor selection
        const idx = self.rr_index.fetchAdd(1, .monotonic) % self.processors.len;
        const processor = &self.processors[idx];

        // Try to push to processor's local queue
        return processor.pushTask(task);
    }

    /// Push task to global queue (when processor queues are full)
    fn pushToGlobalQueue(self: *TaskSpawner, task: *Task) !void {
        self.global_mutex.lock();
        defer self.global_mutex.unlock();

        task.makeRunnable();
        try self.global_queue.append(self.allocator, task);
    }

    /// Get total spawned count
    pub fn totalSpawned(self: *TaskSpawner) u64 {
        return self.total_spawned.load(.monotonic);
    }

    /// Get global queue size
    pub fn globalQueueSize(self: *TaskSpawner) usize {
        self.global_mutex.lock();
        defer self.global_mutex.unlock();

        return self.global_queue.items.len;
    }
};

/// Simple task spawner (for basic scheduler without processors)
pub const SimpleSpawner = struct {
    /// Next task ID
    next_task_id: usize,

    /// Task queue
    queue: *std.ArrayList(*Task),

    /// Queue mutex
    mutex: *std.Thread.Mutex,

    /// Allocator
    allocator: std.mem.Allocator,

    /// Total spawned
    total_spawned: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        queue: *std.ArrayList(*Task),
        mutex: *std.Thread.Mutex,
    ) SimpleSpawner {
        return SimpleSpawner{
            .next_task_id = 1,
            .queue = queue,
            .mutex = mutex,
            .allocator = allocator,
            .total_spawned = 0,
        };
    }

    /// Spawn task
    pub fn spawn(self: *SimpleSpawner, func: @import("../task.zig").TaskFn, context: *anyopaque) !*Task {
        const task = try self.allocator.create(Task);
        errdefer self.allocator.destroy(task);

        task.* = Task.init(self.next_task_id, func, context);
        self.next_task_id += 1;

        // Add to queue
        self.mutex.lock();
        defer self.mutex.unlock();

        task.makeRunnable();
        try self.queue.append(self.allocator, task);
        self.total_spawned += 1;

        return task;
    }

    /// Spawn with stack
    pub fn spawnWithStack(self: *SimpleSpawner, func: @import("../task.zig").TaskFn, context: *anyopaque) !*Task {
        const task = try self.allocator.create(Task);
        errdefer self.allocator.destroy(task);

        task.* = try Task.initWithStack(self.allocator, self.next_task_id, func, context);
        self.next_task_id += 1;

        self.mutex.lock();
        defer self.mutex.unlock();

        task.makeRunnable();
        try self.queue.append(self.allocator, task);
        self.total_spawned += 1;

        return task;
    }
};

/// Batch spawner for spawning multiple tasks efficiently
pub const BatchSpawner = struct {
    spawner: *TaskSpawner,
    tasks: std.ArrayList(*Task),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, spawner: *TaskSpawner) BatchSpawner {
        return BatchSpawner{
            .spawner = spawner,
            .tasks = std.ArrayList(*Task){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BatchSpawner) void {
        self.tasks.deinit(self.allocator);
    }

    /// Add task to batch
    pub fn add(self: *BatchSpawner, func: @import("../task.zig").TaskFn, context: *anyopaque) !void {
        const task = try self.spawner.spawn(func, context);
        try self.tasks.append(self.allocator, task);
    }

    /// Spawn all tasks in batch
    pub fn spawnAll(self: *BatchSpawner) ![]const *Task {
        return self.tasks.items;
    }

    /// Get batch size
    pub fn size(self: *BatchSpawner) usize {
        return self.tasks.items.len;
    }
};
