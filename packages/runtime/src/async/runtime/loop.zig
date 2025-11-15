const std = @import("std");
const Task = @import("../task.zig").Task;
const Processor = @import("../processor.zig").Processor;
const Machine = @import("../machine.zig").Machine;

/// Event loop state
pub const LoopState = enum {
    idle,
    running,
    stopping,
    stopped,
};

/// Event loop (main scheduler loop for each processor)
/// This is the core scheduling loop that runs on each M (machine/OS thread)
pub const EventLoop = struct {
    /// Loop state
    state: LoopState,

    /// Attached processor
    processor: *Processor,

    /// Attached machine
    machine: *Machine,

    /// Global task queue (shared across all processors)
    global_queue: *std.ArrayList(*Task),

    /// Global queue mutex
    global_mutex: *std.Thread.Mutex,

    /// All processors (for work-stealing)
    all_processors: []Processor,

    /// Allocator
    allocator: std.mem.Allocator,

    /// Loop iteration count
    iterations: u64,

    /// Idle iterations (no work found)
    idle_iterations: u64,

    /// Max idle iterations before parking (100 like Go)
    max_idle_iterations: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        processor: *Processor,
        machine: *Machine,
        global_queue: *std.ArrayList(*Task),
        global_mutex: *std.Thread.Mutex,
        all_processors: []Processor,
    ) EventLoop {
        return EventLoop{
            .state = .idle,
            .processor = processor,
            .machine = machine,
            .global_queue = global_queue,
            .global_mutex = global_mutex,
            .all_processors = all_processors,
            .allocator = allocator,
            .iterations = 0,
            .idle_iterations = 0,
            .max_idle_iterations = 100,
        };
    }

    /// Start event loop (blocks until stopped)
    pub fn run(self: *EventLoop) !void {
        self.state = .running;

        while (self.state == .running) {
            self.iterations += 1;

            // Try to find and execute a task
            const executed = try self.findAndExecuteTask();

            if (!executed) {
                // No work found
                self.idle_iterations += 1;

                // If idle for too long, consider parking
                if (self.idle_iterations >= self.max_idle_iterations) {
                    self.parkMachine();
                    self.idle_iterations = 0;
                }

                // Brief sleep to avoid busy-waiting
                std.time.sleep(100); // 100ns
            } else {
                // Reset idle counter when work is found
                self.idle_iterations = 0;
            }
        }

        self.state = .stopped;
    }

    /// Try to find and execute a task (returns true if executed)
    fn findAndExecuteTask(self: *EventLoop) !bool {
        // 1. Check local processor queue first (fast path)
        if (self.processor.popTask()) |task| {
            try self.executeTask(task);
            return true;
        }

        // 2. Check global queue (every 61 iterations like Go)
        if (self.iterations % 61 == 0) {
            if (try self.tryGlobalQueue()) |task| {
                try self.executeTask(task);
                return true;
            }
        }

        // 3. Try work-stealing from other processors
        if (try self.tryStealWork()) |task| {
            try self.executeTask(task);
            return true;
        }

        // 4. Check global queue again (last resort)
        if (try self.tryGlobalQueue()) |task| {
            try self.executeTask(task);
            return true;
        }

        return false; // No work found
    }

    /// Execute a task
    fn executeTask(self: *EventLoop, task: *Task) !void {
        // Mark task as runnable first
        task.makeRunnable();

        // Execute on processor
        try self.processor.runTask(task);

        // Record execution on machine
        self.machine.recordContextSwitch();
    }

    /// Try to get task from global queue
    fn tryGlobalQueue(self: *EventLoop) !?*Task {
        // Lock global queue
        self.global_mutex.lock();
        defer self.global_mutex.unlock();

        if (self.global_queue.items.len == 0) {
            return null;
        }

        // Take one task from global queue
        const task = self.global_queue.pop();

        // Update stats
        self.processor.tasks_acquired += 1;

        return task;
    }

    /// Try to steal work from other processors
    fn tryStealWork(self: *EventLoop) !?*Task {
        if (self.all_processors.len <= 1) {
            return null; // Only one processor, nothing to steal from
        }

        // Try to steal from random processor
        const victim_idx = self.randomProcessorIndex();
        if (victim_idx == self.processor.id) {
            return null; // Don't steal from ourselves
        }

        const victim = &self.all_processors[victim_idx];

        // Try to steal half of victim's tasks
        var stolen = try victim.stealTasks(self.allocator);
        defer stolen.deinit(self.allocator);

        if (stolen.items.len == 0) {
            return null; // Nothing to steal
        }

        // Take first task for immediate execution
        const task = stolen.orderedRemove(0);

        // Put remaining stolen tasks in our local queue
        for (stolen.items) |t| {
            _ = try self.processor.pushTask(t);
        }

        return task;
    }

    /// Get random processor index for work-stealing
    fn randomProcessorIndex(self: *EventLoop) usize {
        // Simple pseudo-random based on iterations
        // In production, use proper RNG
        return (self.iterations * 7919) % self.all_processors.len;
    }

    /// Park machine (block until work available)
    fn parkMachine(self: *EventLoop) void {
        self.machine.park();
    }

    /// Stop event loop
    pub fn stop(self: *EventLoop) void {
        self.state = .stopping;
    }

    /// Get loop statistics
    pub fn stats(self: *EventLoop) LoopStats {
        return LoopStats{
            .state = self.state,
            .iterations = self.iterations,
            .idle_iterations = self.idle_iterations,
            .processor_id = self.processor.id,
            .machine_id = self.machine.id,
        };
    }
};

/// Event loop statistics
pub const LoopStats = struct {
    state: LoopState,
    iterations: u64,
    idle_iterations: u64,
    processor_id: usize,
    machine_id: usize,
};

/// Simple FIFO scheduler (for initial implementation)
/// This is a basic scheduler without work-stealing or preemption
pub const SimpleScheduler = struct {
    /// Task queue
    queue: std.ArrayList(*Task),

    /// Completed tasks (for cleanup)
    completed: std.ArrayList(*Task),

    /// Mutex for queue access
    mutex: std.Thread.Mutex,

    /// Allocator
    allocator: std.mem.Allocator,

    /// Total tasks spawned
    total_spawned: u64,

    /// Total tasks completed
    total_completed: u64,

    pub fn init(allocator: std.mem.Allocator) SimpleScheduler {
        return SimpleScheduler{
            .queue = std.ArrayList(*Task){},
            .completed = std.ArrayList(*Task){},
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
            .total_spawned = 0,
            .total_completed = 0,
        };
    }

    pub fn deinit(self: *SimpleScheduler) void {
        self.queue.deinit(self.allocator);
        self.completed.deinit(self.allocator);
    }

    /// Spawn task (add to queue)
    pub fn spawn(self: *SimpleScheduler, task: *Task) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        task.makeRunnable();
        try self.queue.append(self.allocator, task);
        self.total_spawned += 1;
    }

    /// Get next task (returns null if queue empty)
    pub fn next(self: *SimpleScheduler) ?*Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.queue.items.len == 0) {
            return null;
        }

        return self.queue.orderedRemove(0); // FIFO
    }

    /// Mark task as completed
    pub fn complete(self: *SimpleScheduler, task: *Task) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.completed.append(self.allocator, task) catch {};
        self.total_completed += 1;
    }

    /// Check if all tasks completed
    pub fn allCompleted(self: *SimpleScheduler) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.total_spawned == self.total_completed and self.queue.items.len == 0;
    }

    /// Run all tasks to completion (blocking)
    pub fn runAll(self: *SimpleScheduler) !void {
        while (true) {
            const task = self.next() orelse {
                // No more tasks
                if (self.allCompleted()) {
                    break;
                }
                // Wait for more tasks
                std.Thread.sleep(1_000); // 1�s
                continue;
            };

            // Execute task
            try task.run();

            // Mark completed
            self.complete(task);
        }
    }

    /// Get scheduler statistics
    pub fn stats(self: *SimpleScheduler) SimpleSchedulerStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return SimpleSchedulerStats{
            .queue_size = self.queue.items.len,
            .total_spawned = self.total_spawned,
            .total_completed = self.total_completed,
        };
    }
};

/// Simple scheduler statistics
pub const SimpleSchedulerStats = struct {
    queue_size: usize,
    total_spawned: u64,
    total_completed: u64,
};
