const std = @import("std");
const Task = @import("task.zig").Task;

/// Processor state
pub const ProcessorState = enum {
    idle, // Not running
    running, // Executing tasks
    spinning, // Looking for work
    parked, // Waiting for work
};

/// Processor (P in Go's GMP model)
/// Each P has a local run queue and can execute tasks independently
pub const Processor = struct {
    /// Processor ID (0 to GOMAXPROCS-1)
    id: usize,

    /// Current state
    state: ProcessorState,

    /// Current running task (G in Go)
    current_task: ?*Task,

    /// Next task (hot slot for cache locality - Tokio optimization)
    next_task: ?*Task,

    /// Local run queue (256 task capacity, lock-free)
    local_queue: std.ArrayList(*Task),

    /// Local queue head/tail for FIFO scheduling
    queue_head: usize,
    queue_tail: usize,

    /// Attached machine (M in Go) - OS thread running this P
    machine_id: ?usize,

    /// Statistics
    tasks_executed: u64,
    tasks_stolen: u64, // Tasks stolen by other Ps
    tasks_acquired: u64, // Tasks acquired from global queue

    /// Allocator for this processor
    allocator: std.mem.Allocator,

    /// Local run queue capacity (256 like Go)
    pub const LOCAL_QUEUE_CAP: usize = 256;

    pub fn init(allocator: std.mem.Allocator, id: usize) Processor {
        return Processor{
            .id = id,
            .state = .idle,
            .current_task = null,
            .next_task = null,
            .local_queue = std.ArrayList(*Task){},
            .queue_head = 0,
            .queue_tail = 0,
            .machine_id = null,
            .tasks_executed = 0,
            .tasks_stolen = 0,
            .tasks_acquired = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Processor) void {
        self.local_queue.deinit(self.allocator);
    }

    /// Attach to machine (OS thread)
    pub fn attachToMachine(self: *Processor, machine_id: usize) void {
        self.machine_id = machine_id;
        self.state = .running;
    }

    /// Detach from machine
    pub fn detachFromMachine(self: *Processor) void {
        self.machine_id = null;
        self.state = .idle;
    }

    /// Push task to local queue (returns false if full)
    pub fn pushTask(self: *Processor, task: *Task) !bool {
        // Try to use next_task slot first (Tokio optimization)
        if (self.next_task == null) {
            self.next_task = task;
            task.processor_id = self.id;
            return true;
        }

        // Check if queue is full
        const queue_size = self.local_queue.items.len;
        if (queue_size >= LOCAL_QUEUE_CAP) {
            return false; // Queue full, need to push to global queue
        }

        // Add to local queue
        try self.local_queue.append(self.allocator, task);
        task.processor_id = self.id;
        self.queue_tail += 1;

        return true;
    }

    /// Pop task from local queue (returns null if empty)
    pub fn popTask(self: *Processor) ?*Task {
        // Check next_task slot first (hot slot)
        if (self.next_task) |task| {
            self.next_task = null;
            return task;
        }

        // Pop from local queue
        if (self.local_queue.items.len > 0) {
            const task = self.local_queue.pop();
            self.queue_head += 1;
            return task;
        }

        return null;
    }

    /// Peek at next task without removing it
    pub fn peekTask(self: *Processor) ?*Task {
        if (self.next_task) |task| {
            return task;
        }

        if (self.local_queue.items.len > 0) {
            return self.local_queue.items[self.local_queue.items.len - 1];
        }

        return null;
    }

    /// Steal half of the tasks from this processor (for work-stealing)
    pub fn stealTasks(self: *Processor, allocator: std.mem.Allocator) !std.ArrayList(*Task) {
        var stolen = std.ArrayList(*Task){};

        const queue_size = self.local_queue.items.len;
        if (queue_size == 0) {
            return stolen;
        }

        // Steal half of the tasks (Go's strategy)
        const steal_count = queue_size / 2;
        if (steal_count == 0) {
            return stolen;
        }

        // Take from the front (oldest tasks)
        var i: usize = 0;
        while (i < steal_count) : (i += 1) {
            const task = self.local_queue.orderedRemove(0);
            task.processor_id = null; // Detach from this P
            try stolen.append(allocator, task);
        }

        self.tasks_stolen += steal_count;

        return stolen;
    }

    /// Run a task on this processor
    pub fn runTask(self: *Processor, task: *Task) !void {
        self.current_task = task;
        task.processor_id = self.id;

        try task.run();

        self.tasks_executed += 1;
        self.current_task = null;
    }

    /// Check if processor has work
    pub fn hasWork(self: *Processor) bool {
        return self.next_task != null or self.local_queue.items.len > 0;
    }

    /// Get queue size
    pub fn queueSize(self: *Processor) usize {
        var size: usize = 0;
        if (self.next_task != null) size += 1;
        size += self.local_queue.items.len;
        return size;
    }

    /// Get processor statistics
    pub fn stats(self: *Processor) ProcessorStats {
        return ProcessorStats{
            .id = self.id,
            .state = self.state,
            .queue_size = self.queueSize(),
            .tasks_executed = self.tasks_executed,
            .tasks_stolen = self.tasks_stolen,
            .tasks_acquired = self.tasks_acquired,
            .has_machine = self.machine_id != null,
        };
    }
};

/// Processor statistics
pub const ProcessorStats = struct {
    id: usize,
    state: ProcessorState,
    queue_size: usize,
    tasks_executed: u64,
    tasks_stolen: u64,
    tasks_acquired: u64,
    has_machine: bool,
};
