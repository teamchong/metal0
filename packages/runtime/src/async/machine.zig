const std = @import("std");
const Processor = @import("processor.zig").Processor;
const Task = @import("task.zig").Task;

/// Machine state
pub const MachineState = enum {
    idle, // Not started
    running, // Executing tasks
    spinning, // Looking for work
    parked, // Waiting for work
    dead, // Thread finished
};

/// Machine (M in Go's GMP model)
/// Represents an OS thread that executes tasks on processors
pub const Machine = struct {
    /// Machine ID
    id: usize,

    /// Current state
    state: MachineState,

    /// Attached processor (P in Go)
    processor: ?*Processor,

    /// OS thread handle
    thread: ?std.Thread,

    /// Running flag (atomic for thread coordination)
    running: std.atomic.Value(bool),

    /// Spinning flag (looking for work without blocking)
    spinning: std.atomic.Value(bool),

    /// Statistics
    tasks_executed: u64,
    context_switches: u64,
    spin_count: u64,

    /// Last activity timestamp (for detecting idle threads)
    last_active: i128,

    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: usize) Machine {
        return Machine{
            .id = id,
            .state = .idle,
            .processor = null,
            .thread = null,
            .running = std.atomic.Value(bool).init(false),
            .spinning = std.atomic.Value(bool).init(false),
            .tasks_executed = 0,
            .context_switches = 0,
            .spin_count = 0,
            .last_active = 0,
            .allocator = allocator,
        };
    }

    /// Attach processor to this machine
    pub fn attachProcessor(self: *Machine, processor: *Processor) void {
        self.processor = processor;
        processor.attachToMachine(self.id);
        self.state = .running;
        self.last_active = std.time.nanoTimestamp();
    }

    /// Detach processor from this machine
    pub fn detachProcessor(self: *Machine) void {
        if (self.processor) |p| {
            p.detachFromMachine();
            self.processor = null;
        }
        self.state = .idle;
    }

    /// Start machine (spawn OS thread)
    pub fn start(self: *Machine, entry_fn: *const fn (*Machine) void) !void {
        if (self.thread != null) {
            return error.AlreadyRunning;
        }

        self.running.store(true, .release);
        self.state = .running;

        // Spawn OS thread
        self.thread = try std.Thread.spawn(.{}, entry_fn, .{self});
    }

    /// Stop machine (signal thread to exit)
    pub fn stop(self: *Machine) void {
        self.running.store(false, .release);
        self.state = .dead;
    }

    /// Wait for machine thread to finish
    pub fn join(self: *Machine) void {
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }

    /// Enter spinning state (looking for work)
    pub fn startSpinning(self: *Machine) void {
        self.spinning.store(true, .release);
        self.state = .spinning;
        self.spin_count += 1;
    }

    /// Exit spinning state
    pub fn stopSpinning(self: *Machine) void {
        self.spinning.store(false, .release);
        if (self.state == .spinning) {
            self.state = .running;
        }
    }

    /// Check if machine is spinning
    pub fn isSpinning(self: *Machine) bool {
        return self.spinning.load(.acquire);
    }

    /// Park machine (block until work available)
    pub fn park(self: *Machine) void {
        self.state = .parked;
        // TODO: Implement actual parking with futex/condition variable
        // For now, just sleep briefly
        std.Thread.sleep(1_000_000); // 1ms
    }

    /// Unpark machine (wake up from parked state)
    pub fn unpark(self: *Machine) void {
        if (self.state == .parked) {
            self.state = .running;
            self.last_active = std.time.nanoTimestamp();
        }
    }

    /// Execute a task on this machine's processor
    pub fn executeTask(self: *Machine, task: *Task) !void {
        if (self.processor) |p| {
            try p.runTask(task);
            self.tasks_executed += 1;
            self.last_active = std.time.nanoTimestamp();
        } else {
            return error.NoProcessor;
        }
    }

    /// Record context switch
    pub fn recordContextSwitch(self: *Machine) void {
        self.context_switches += 1;
        self.last_active = std.time.nanoTimestamp();
    }

    /// Check if machine is idle (no activity for a while)
    pub fn isIdle(self: *Machine, idle_threshold_ns: i128) bool {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_active;
        return elapsed > idle_threshold_ns;
    }

    /// Get machine statistics
    pub fn stats(self: *Machine) MachineStats {
        return MachineStats{
            .id = self.id,
            .state = self.state,
            .has_processor = self.processor != null,
            .tasks_executed = self.tasks_executed,
            .context_switches = self.context_switches,
            .spin_count = self.spin_count,
            .is_spinning = self.isSpinning(),
        };
    }
};

/// Machine statistics
pub const MachineStats = struct {
    id: usize,
    state: MachineState,
    has_processor: bool,
    tasks_executed: u64,
    context_switches: u64,
    spin_count: u64,
    is_spinning: bool,
};

/// Machine pool for managing OS threads
pub const MachinePool = struct {
    /// All machines
    machines: std.ArrayList(*Machine),

    /// Idle machines
    idle_machines: std.ArrayList(*Machine),

    /// Allocator
    allocator: std.mem.Allocator,

    /// Next machine ID
    next_id: usize,

    /// Maximum number of machines (GOMAXPROCS)
    max_machines: usize,

    pub fn init(allocator: std.mem.Allocator, max_machines: usize) MachinePool {
        return MachinePool{
            .machines = std.ArrayList(*Machine){},
            .idle_machines = std.ArrayList(*Machine){},
            .allocator = allocator,
            .next_id = 0,
            .max_machines = max_machines,
        };
    }

    pub fn deinit(self: *MachinePool) void {
        // Stop all machines
        for (self.machines.items) |machine| {
            machine.stop();
            machine.join();
            machine.allocator.destroy(machine);
        }

        self.machines.deinit(self.allocator);
        self.idle_machines.deinit(self.allocator);
    }

    /// Create new machine
    pub fn createMachine(self: *MachinePool) !*Machine {
        if (self.machines.items.len >= self.max_machines) {
            return error.TooManyMachines;
        }

        const machine = try self.allocator.create(Machine);
        machine.* = Machine.init(self.allocator, self.next_id);
        self.next_id += 1;

        try self.machines.append(self.allocator, machine);

        return machine;
    }

    /// Get idle machine or create new one
    pub fn acquireMachine(self: *MachinePool) !*Machine {
        // Try to get idle machine first
        if (self.idle_machines.items.len > 0) {
            return self.idle_machines.pop();
        }

        // Create new machine if under limit
        return self.createMachine();
    }

    /// Return machine to idle pool
    pub fn releaseMachine(self: *MachinePool, machine: *Machine) !void {
        machine.detachProcessor();
        machine.state = .idle;
        try self.idle_machines.append(self.allocator, machine);
    }

    /// Get total machine count
    pub fn count(self: *MachinePool) usize {
        return self.machines.items.len;
    }

    /// Get idle machine count
    pub fn idleCount(self: *MachinePool) usize {
        return self.idle_machines.items.len;
    }

    /// Get running machine count
    pub fn runningCount(self: *MachinePool) usize {
        return self.machines.items.len - self.idle_machines.items.len;
    }
};
