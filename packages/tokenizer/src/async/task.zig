const std = @import("std");

/// Task state matching Go's goroutine states
pub const TaskState = enum {
    idle, // Not started
    runnable, // Ready to run (Go's _Grunnable)
    running, // Currently executing (Go's _Grunning)
    waiting, // Blocked on I/O or channel (Go's _Gwaiting)
    dead, // Finished execution (Go's _Gdead)
};

/// Task priority for scheduling
pub const TaskPriority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
};

/// Task execution context (registers, stack pointer, etc.)
pub const TaskContext = struct {
    sp: usize, // Stack pointer
    pc: usize, // Program counter
    fp: usize, // Frame pointer
    regs: [16]usize, // General purpose registers

    pub fn init() TaskContext {
        return TaskContext{
            .sp = 0,
            .pc = 0,
            .fp = 0,
            .regs = [_]usize{0} ** 16,
        };
    }
};

/// Task function signature
pub const TaskFn = *const fn (*anyopaque) anyerror!void;

/// Async task (Go goroutine equivalent)
pub const Task = struct {
    /// Unique task ID
    id: usize,

    /// Task function to execute
    func: TaskFn,

    /// Context data (passed to func)
    context: *anyopaque,

    /// Current state
    state: TaskState,

    /// Priority level
    priority: TaskPriority,

    /// Stack (4KB default like Go, can grow)
    stack: ?[]u8,

    /// Stack size
    stack_size: usize,

    /// Execution context (registers, PC, SP)
    exec_context: TaskContext,

    /// Saved stack pointer (during context switch)
    saved_sp: ?usize,

    /// Start timestamp (for preemption)
    start_time: i128,

    /// Last scheduled timestamp
    scheduled_at: i128,

    /// Total CPU time consumed (nanoseconds)
    cpu_time: u64,

    /// Number of times yielded
    yield_count: u64,

    /// Preempt flag (set by timer, checked by task)
    preempt: std.atomic.Value(bool),

    /// Next task in queue (linked list for queues)
    next: ?*Task,

    /// Parent processor ID (which P owns this task)
    processor_id: ?usize,

    /// Allocator for this task
    allocator: ?std.mem.Allocator,

    /// I/O file descriptor (for async I/O)
    io_fd: ?std.posix.fd_t,

    /// I/O event mask (READABLE | WRITABLE)
    io_events: u32,

    /// Default stack size (4KB like Go)
    pub const DEFAULT_STACK_SIZE: usize = 4096;

    /// Maximum stack size (can grow to 1MB)
    pub const MAX_STACK_SIZE: usize = 1024 * 1024;

    pub fn init(id: usize, func: TaskFn, context: *anyopaque) Task {
        return Task{
            .id = id,
            .func = func,
            .context = context,
            .state = .idle,
            .priority = .normal,
            .stack = null,
            .stack_size = 0,
            .exec_context = TaskContext.init(),
            .saved_sp = null,
            .start_time = 0,
            .scheduled_at = 0,
            .cpu_time = 0,
            .yield_count = 0,
            .preempt = std.atomic.Value(bool).init(false),
            .next = null,
            .processor_id = null,
            .allocator = null,
            .io_fd = null,
            .io_events = 0,
        };
    }

    /// Initialize with allocator and stack
    pub fn initWithStack(allocator: std.mem.Allocator, id: usize, func: TaskFn, context: *anyopaque) !Task {
        const stack = try allocator.alloc(u8, DEFAULT_STACK_SIZE);
        errdefer allocator.free(stack);

        var task = init(id, func, context);
        task.stack = stack;
        task.stack_size = DEFAULT_STACK_SIZE;
        task.allocator = allocator;

        return task;
    }

    /// Free task resources
    pub fn deinit(self: *Task) void {
        if (self.stack) |stack| {
            if (self.allocator) |allocator| {
                allocator.free(stack);
                self.stack = null;
            }
        }
    }

    /// Execute task function
    pub fn run(self: *Task) !void {
        self.state = .running;
        self.start_time = std.time.nanoTimestamp();
        self.scheduled_at = self.start_time;
        self.preempt.store(false, .release);

        try self.func(self.context);

        self.state = .dead;

        // Update final CPU time
        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now - self.scheduled_at));
        self.cpu_time += elapsed;
    }

    /// Mark task as runnable
    pub fn makeRunnable(self: *Task) void {
        self.state = .runnable;
    }

    /// Mark task as running
    pub fn makeRunning(self: *Task) void {
        self.state = .running;
        self.scheduled_at = std.time.nanoTimestamp();
    }

    /// Mark task as waiting
    pub fn makeWaiting(self: *Task) void {
        self.state = .waiting;
    }

    /// Mark task as dead
    pub fn makeDead(self: *Task) void {
        self.state = .dead;
    }

    /// Check if task is runnable
    pub fn isRunnable(self: *Task) bool {
        return self.state == .runnable;
    }

    /// Check if task is running
    pub fn isRunning(self: *Task) bool {
        return self.state == .running;
    }

    /// Check if task is waiting
    pub fn isWaiting(self: *Task) bool {
        return self.state == .waiting;
    }

    /// Check if task is dead
    pub fn isDead(self: *Task) bool {
        return self.state == .dead;
    }

    /// Check if task should be preempted
    pub fn shouldPreempt(self: *Task) bool {
        return self.preempt.load(.acquire);
    }

    /// Mark task as preempted (back to runnable)
    pub fn markPreempted(self: *Task) void {
        self.preempt.store(true, .release);
        self.state = .runnable;
    }

    /// Record yield event
    pub fn recordYield(self: *Task) void {
        self.yield_count += 1;

        // Update CPU time
        const now = std.time.nanoTimestamp();
        if (self.scheduled_at > 0) {
            const elapsed = @as(u64, @intCast(now - self.scheduled_at));
            self.cpu_time += elapsed;
        }
    }

    /// Grow stack if needed (returns true if grew)
    pub fn growStack(self: *Task) !bool {
        if (self.stack == null) return false;
        if (self.allocator == null) return false;

        const allocator = self.allocator.?;
        const old_stack = self.stack.?;

        // Double the stack size
        var new_size = self.stack_size * 2;
        if (new_size > MAX_STACK_SIZE) {
            new_size = MAX_STACK_SIZE;
        }

        if (new_size <= self.stack_size) {
            return error.StackOverflow;
        }

        // Allocate new stack
        const new_stack = try allocator.alloc(u8, new_size);

        // Copy old stack contents
        @memcpy(new_stack[0..self.stack_size], old_stack);

        // Free old stack
        allocator.free(old_stack);

        // Update task
        self.stack = new_stack;
        self.stack_size = new_size;

        return true;
    }

    /// Get stack usage percentage (simplified)
    pub fn stackUsage(self: *Task) f64 {
        const used = self.exec_context.sp;
        if (used == 0) return 0.0;

        return @as(f64, @floatFromInt(used)) / @as(f64, @floatFromInt(self.stack_size)) * 100.0;
    }
};
