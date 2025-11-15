const std = @import("std");

// Import core components
pub const Task = @import("task.zig").Task;
pub const TaskState = @import("task.zig").TaskState;
pub const TaskFn = @import("task.zig").TaskFn;

pub const Processor = @import("processor.zig").Processor;
pub const ProcessorState = @import("processor.zig").ProcessorState;

pub const Machine = @import("machine.zig").Machine;
pub const MachineState = @import("machine.zig").MachineState;

// Runtime components
pub const EventLoop = @import("runtime/loop.zig").EventLoop;
pub const SimpleScheduler = @import("runtime/loop.zig").SimpleScheduler;
pub const TaskSpawner = @import("runtime/spawn.zig").TaskSpawner;
pub const SimpleSpawner = @import("runtime/spawn.zig").SimpleSpawner;
pub const Yielder = @import("runtime/yield.zig").Yielder;
pub const SimpleYielder = @import("runtime/yield.zig").SimpleYielder;
pub const YieldStrategy = @import("runtime/yield.zig").YieldStrategy;

/// Async runtime configuration
pub const RuntimeConfig = struct {
    /// Number of processors (GOMAXPROCS)
    /// Default: CPU core count
    num_processors: usize,

    /// Number of OS threads (M in Go)
    /// Default: num_processors
    num_threads: usize,

    /// Enable work-stealing
    enable_work_stealing: bool,

    /// Enable preemption
    enable_preemption: bool,

    /// Task timeslice (milliseconds)
    timeslice_ms: u64,

    pub fn default() RuntimeConfig {
        const cpu_count = std.Thread.getCpuCount() catch 1;
        return RuntimeConfig{
            .num_processors = cpu_count,
            .num_threads = cpu_count,
            .enable_work_stealing = true,
            .enable_preemption = true,
            .timeslice_ms = 10, // 10ms like Go
        };
    }

    pub fn single_threaded() RuntimeConfig {
        return RuntimeConfig{
            .num_processors = 1,
            .num_threads = 1,
            .enable_work_stealing = false,
            .enable_preemption = false,
            .timeslice_ms = 10,
        };
    }
};

/// Simple async runtime (single-threaded FIFO scheduler)
/// Good for testing and simple use cases
pub const SimpleRuntime = struct {
    /// Scheduler
    scheduler: SimpleScheduler,

    /// Spawner
    spawner: SimpleSpawner,

    /// Yielder
    yielder: SimpleYielder,

    /// Task queue
    queue: std.ArrayList(*Task),

    /// Queue mutex
    mutex: std.Thread.Mutex,

    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SimpleRuntime {
        var runtime = SimpleRuntime{
            .scheduler = undefined,
            .spawner = undefined,
            .yielder = undefined,
            .queue = std.ArrayList(*Task){},
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
        };

        runtime.scheduler = SimpleScheduler.init(allocator);
        runtime.spawner = SimpleSpawner.init(allocator, &runtime.queue, &runtime.mutex);
        runtime.yielder = SimpleYielder.init(allocator, &runtime.queue, &runtime.mutex);

        return runtime;
    }

    pub fn deinit(self: *SimpleRuntime) void {
        // Free completed tasks
        for (self.scheduler.completed.items) |task| {
            self.allocator.destroy(task);
        }

        // Free any remaining tasks in queue
        for (self.scheduler.queue.items) |task| {
            self.allocator.destroy(task);
        }

        self.scheduler.deinit();
    }

    /// Spawn new task
    pub fn spawn(self: *SimpleRuntime, func: TaskFn, context: *anyopaque) !*Task {
        const task = try self.allocator.create(Task);
        errdefer self.allocator.destroy(task);

        task.* = Task.init(self.scheduler.total_spawned + 1, func, context);
        try self.scheduler.spawn(task);

        return task;
    }

    /// Yield current task
    pub fn yield(self: *SimpleRuntime, task: *Task) !void {
        try self.yielder.yield(task);
    }

    /// Run all tasks to completion
    pub fn run(self: *SimpleRuntime) !void {
        while (true) {
            const task = self.scheduler.next() orelse {
                if (self.scheduler.allCompleted()) {
                    break;
                }
                std.Thread.sleep(1_000); // 1�s
                continue;
            };

            try task.run();
            self.scheduler.complete(task);
        }
    }

    /// Get runtime statistics
    pub fn stats(self: *SimpleRuntime) SimpleRuntimeStats {
        const sched_stats = self.scheduler.stats();
        return SimpleRuntimeStats{
            .queue_size = sched_stats.queue_size,
            .total_spawned = sched_stats.total_spawned,
            .total_completed = sched_stats.total_completed,
            .total_yields = self.yielder.total_yields,
        };
    }
};

/// Simple runtime statistics
pub const SimpleRuntimeStats = struct {
    queue_size: usize,
    total_spawned: u64,
    total_completed: u64,
    total_yields: u64,
};

/// Full async runtime with G-M-P scheduler
/// This will be implemented in later weeks (17-22)
pub const Runtime = struct {
    /// Configuration
    config: RuntimeConfig,

    /// Processors (P in Go)
    processors: []Processor,

    /// Machines (M in Go)
    machines: std.ArrayList(*Machine),

    /// Global task queue
    global_queue: std.ArrayList(*Task),

    /// Global queue mutex
    global_mutex: std.Thread.Mutex,

    /// Task spawner
    spawner: TaskSpawner,

    /// Yielder
    yielder: Yielder,

    /// Allocator
    allocator: std.mem.Allocator,

    /// Running flag
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator, config: RuntimeConfig) !Runtime {
        // Allocate processors
        const processors = try allocator.alloc(Processor, config.num_processors);
        errdefer allocator.free(processors);

        for (processors, 0..) |*p, i| {
            p.* = Processor.init(allocator, i);
        }

        var runtime = Runtime{
            .config = config,
            .processors = processors,
            .machines = std.ArrayList(*Machine){},
            .global_queue = std.ArrayList(*Task){},
            .global_mutex = std.Thread.Mutex{},
            .spawner = undefined,
            .yielder = undefined,
            .allocator = allocator,
            .running = std.atomic.Value(bool).init(false),
        };

        runtime.spawner = TaskSpawner.init(
            allocator,
            runtime.processors,
            &runtime.global_queue,
            &runtime.global_mutex,
        );

        runtime.yielder = Yielder.init(
            allocator,
            &runtime.global_queue,
            &runtime.global_mutex,
        );

        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        // Clean up processors
        for (self.processors) |*p| {
            p.deinit();
        }
        self.allocator.free(self.processors);

        // Clean up machines
        for (self.machines.items) |m| {
            m.stop();
            m.join();
            self.allocator.destroy(m);
        }
        self.machines.deinit(self.allocator);

        // Clean up global queue
        self.global_queue.deinit(self.allocator);
    }

    /// Spawn new task
    pub fn spawn(self: *Runtime, func: TaskFn, context: *anyopaque) !*Task {
        return self.spawner.spawn(func, context);
    }

    /// Yield current task
    pub fn yield(self: *Runtime, task: *Task) !void {
        try self.yielder.yield(task);
    }

    /// Start runtime (for future multi-threaded implementation)
    pub fn start(self: *Runtime) !void {
        self.running.store(true, .release);

        // TODO: Start machines and event loops (Week 17-18)
        // For now, this is a placeholder
    }

    /// Stop runtime
    pub fn stop(self: *Runtime) void {
        self.running.store(false, .release);

        // TODO: Stop all machines and event loops (Week 17-18)
    }

    /// Get runtime statistics
    pub fn stats(self: *Runtime) RuntimeStats {
        var total_tasks = self.global_queue.items.len;
        var total_executed: u64 = 0;

        for (self.processors) |*p| {
            total_tasks += p.queueSize();
            total_executed += p.tasks_executed;
        }

        return RuntimeStats{
            .num_processors = self.processors.len,
            .num_machines = self.machines.items.len,
            .total_tasks = total_tasks,
            .total_executed = total_executed,
            .global_queue_size = self.global_queue.items.len,
            .total_spawned = self.spawner.totalSpawned(),
            .total_yields = self.yielder.totalYields(),
        };
    }
};

/// Full runtime statistics
pub const RuntimeStats = struct {
    num_processors: usize,
    num_machines: usize,
    total_tasks: usize,
    total_executed: u64,
    global_queue_size: usize,
    total_spawned: u64,
    total_yields: u64,
};

// Global runtime instance (thread-local)
threadlocal var global_runtime: ?*SimpleRuntime = null;

/// Get or create global runtime
pub fn getRuntime(allocator: std.mem.Allocator) !*SimpleRuntime {
    if (global_runtime) |rt| {
        return rt;
    }

    const rt = try allocator.create(SimpleRuntime);
    rt.* = SimpleRuntime.init(allocator);
    global_runtime = rt;

    return rt;
}

/// Spawn task on global runtime
pub fn spawn(allocator: std.mem.Allocator, func: TaskFn, context: *anyopaque) !*Task {
    const rt = try getRuntime(allocator);
    return rt.spawn(func, context);
}

/// Yield current task on global runtime
pub fn yield(allocator: std.mem.Allocator, task: *Task) !void {
    const rt = try getRuntime(allocator);
    try rt.yield(task);
}

/// Run global runtime to completion
pub fn run(allocator: std.mem.Allocator) !void {
    const rt = try getRuntime(allocator);
    try rt.run();
}
