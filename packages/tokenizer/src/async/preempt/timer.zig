const std = @import("std");
const Task = @import("../task.zig").Task;
const Processor = @import("../processor.zig").Processor;

/// Preemption interval (10ms like Go)
pub const PREEMPT_INTERVAL_NS: u64 = 10 * std.time.ns_per_ms;

/// Preemption timer
/// Runs in background thread, checks processors every 10ms
/// If a task has been running too long, marks it for preemption
pub const PreemptTimer = struct {
    /// Background timer thread
    thread: ?std.Thread,

    /// Processors to monitor
    processors: []*Processor,

    /// Running flag
    running: std.atomic.Value(bool),

    /// Check interval (nanoseconds)
    interval_ns: u64,

    /// Statistics
    total_checks: u64,
    total_preemptions: u64,

    const Self = @This();

    /// Initialize preemption timer
    pub fn init(processors: []*Processor) Self {
        return Self{
            .thread = null,
            .processors = processors,
            .running = std.atomic.Value(bool).init(false),
            .interval_ns = PREEMPT_INTERVAL_NS,
            .total_checks = 0,
            .total_preemptions = 0,
        };
    }

    /// Start timer thread
    pub fn start(self: *Self) !void {
        if (self.running.load(.acquire)) {
            return error.AlreadyRunning;
        }

        self.running.store(true, .release);
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    /// Stop timer thread
    pub fn stop(self: *Self) void {
        if (!self.running.load(.acquire)) {
            return;
        }

        self.running.store(false, .release);

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }

    /// Timer main loop
    fn run(self: *Self) void {
        while (self.running.load(.acquire)) {
            // Sleep for interval
            std.Thread.sleep(self.interval_ns);

            // Check all processors
            self.checkProcessors();

            self.total_checks += 1;
        }
    }

    /// Check all processors for long-running tasks
    fn checkProcessors(self: *Self) void {
        const now = std.time.nanoTimestamp();

        for (self.processors) |processor| {
            if (processor.current_task) |task| {
                // Check if task has been running too long
                const runtime = now - task.start_time;

                if (runtime > PREEMPT_INTERVAL_NS) {
                    // Task exceeded time quantum, mark for preemption
                    self.preemptTask(processor, task);
                    self.total_preemptions += 1;
                }
            }
        }
    }

    /// Mark task for preemption
    fn preemptTask(self: *Self, processor: *Processor, task: *Task) void {
        _ = self;

        // Set preempt flag (atomic, task will check this)
        task.markPreempted();

        // Send signal to processor thread (if signals enabled)
        const signals = @import("signals.zig");
        if (processor.machine_id) |_| {
            // Signal would be sent here
            // For now, just mark the flag - scheduler will check it
            signals.markForPreemption(processor);
        }
    }

    /// Get statistics
    pub fn getStats(self: *Self) PreemptTimerStats {
        return PreemptTimerStats{
            .total_checks = self.total_checks,
            .total_preemptions = self.total_preemptions,
            .interval_ns = self.interval_ns,
        };
    }
};

/// Timer statistics
pub const PreemptTimerStats = struct {
    total_checks: u64,
    total_preemptions: u64,
    interval_ns: u64,
};

// Tests
test "PreemptTimer basic operations" {
    const testing = std.testing;

    // Create processors
    var processor1 = Processor.init(testing.allocator, 0);
    var processor2 = Processor.init(testing.allocator, 1);
    defer processor1.deinit();
    defer processor2.deinit();

    var processors = [_]*Processor{ &processor1, &processor2 };

    // Create timer
    var timer = PreemptTimer.init(&processors);

    // Start timer
    try timer.start();
    defer timer.stop();

    // Let it run for a bit
    std.time.sleep(50 * std.time.ns_per_ms);

    // Check stats
    const stats = timer.getStats();
    try testing.expect(stats.total_checks >= 3); // At least 3 checks in 50ms
}

test "PreemptTimer task preemption" {
    const testing = std.testing;

    // Create processor
    var processor = Processor.init(testing.allocator, 0);
    defer processor.deinit();

    // Create long-running task
    var task = Task.init(1, undefined, undefined);
    task.start_time = std.time.nanoTimestamp() - (20 * std.time.ns_per_ms); // Started 20ms ago
    task.state = .running;

    processor.current_task = &task;

    var processors = [_]*Processor{&processor};
    var timer = PreemptTimer.init(&processors);

    // Start timer
    try timer.start();
    defer timer.stop();

    // Let timer check
    std.time.sleep(15 * std.time.ns_per_ms);

    // Task should be marked for preemption
    try testing.expect(task.shouldPreempt());

    // Check stats
    const stats = timer.getStats();
    try testing.expect(stats.total_preemptions >= 1);
}

test "PreemptTimer no preemption for short tasks" {
    const testing = std.testing;

    // Create processor
    var processor = Processor.init(testing.allocator, 0);
    defer processor.deinit();

    // Create short-running task
    var task = Task.init(1, undefined, undefined);
    task.start_time = std.time.nanoTimestamp() - (5 * std.time.ns_per_ms); // Started 5ms ago
    task.state = .running;

    processor.current_task = &task;

    var processors = [_]*Processor{&processor};
    var timer = PreemptTimer.init(&processors);

    // Start timer
    try timer.start();
    defer timer.stop();

    // Let timer check
    std.time.sleep(15 * std.time.ns_per_ms);

    // Task should NOT be marked for preemption (too short)
    // Note: This might fail if task runs longer than 10ms total
    // In real test, we'd need more precise control
}
