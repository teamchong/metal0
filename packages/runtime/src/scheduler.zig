const std = @import("std");
const GreenThread = @import("green_thread").GreenThread;
const WorkQueue = @import("work_queue").WorkQueue;

pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    queues: []WorkQueue,
    workers: []std.Thread,
    next_id: std.atomic.Value(u64),
    active_threads: std.atomic.Value(usize),
    shutdown_flag: std.atomic.Value(bool),
    num_workers: usize,

    pub fn init(allocator: std.mem.Allocator, num_threads: usize) !Scheduler {
        const thread_count = if (num_threads == 0)
            try std.Thread.getCpuCount()
        else
            num_threads;

        const queues = try allocator.alloc(WorkQueue, thread_count);
        errdefer allocator.free(queues);

        for (queues) |*queue| {
            queue.* = WorkQueue.init(allocator);
        }

        const workers = try allocator.alloc(std.Thread, thread_count);
        errdefer allocator.free(workers);

        return Scheduler{
            .allocator = allocator,
            .queues = queues,
            .workers = workers,
            .next_id = std.atomic.Value(u64).init(1),
            .active_threads = std.atomic.Value(usize).init(0),
            .shutdown_flag = std.atomic.Value(bool).init(false),
            .num_workers = thread_count,
        };
    }

    pub fn start(self: *Scheduler) !void {
        // Pre-spawn persistent workers
        for (0..self.num_workers) |i| {
            self.workers[i] = try std.Thread.spawn(.{}, workerLoop, .{ self, i });
        }
    }

    pub fn deinit(self: *Scheduler) void {
        // Wait for all active tasks to complete
        while (self.active_threads.load(.acquire) > 0) {
            std.Thread.yield() catch {};
        }

        // Signal workers to stop
        self.shutdown_flag.store(true, .release);

        // Join all workers
        for (self.workers) |worker| {
            worker.join();
        }

        // Cleanup
        for (self.queues) |*queue| {
            queue.deinit();
        }
        self.allocator.free(self.queues);
        self.allocator.free(self.workers);
    }

    pub fn spawn(self: *Scheduler, func: *const fn (*GreenThread) void) !*GreenThread {
        const id = self.next_id.fetchAdd(1, .monotonic);
        const thread = try GreenThread.init(self.allocator, id, func);

        // Round-robin assignment to queues
        const queue_idx = @as(usize, @intCast(id % self.num_workers));
        try self.queues[queue_idx].push(thread);

        // Increment counter (workers will pick it up)
        _ = self.active_threads.fetchAdd(1, .acq_rel);

        return thread;
    }

    fn workerLoop(self: *Scheduler, worker_id: usize) void {
        const queue = &self.queues[worker_id];

        while (!self.shutdown_flag.load(.acquire)) {
            // Try local queue first (LIFO for cache locality)
            if (queue.pop()) |task| {
                if (task.state == .ready) {
                    task.run();
                }
                _ = self.active_threads.fetchSub(1, .release);
                continue;
            }

            // Try stealing from other queues (FIFO)
            if (self.trySteal(worker_id)) |task| {
                if (task.state == .ready) {
                    task.run();
                }
                _ = self.active_threads.fetchSub(1, .release);
                continue;
            }

            // No work available, yield CPU
            std.Thread.yield() catch {};
        }
    }

    fn trySteal(self: *Scheduler, worker_id: usize) ?*GreenThread {
        // Try to steal from other workers' queues
        var i: usize = 0;
        while (i < self.num_workers) : (i += 1) {
            const target = (worker_id + i + 1) % self.num_workers;
            if (target == worker_id) continue;

            if (self.queues[target].steal()) |task| {
                return task;
            }
        }
        return null;
    }

    pub fn wait(self: *Scheduler, thread: *GreenThread) void {
        _ = self;
        while (!thread.isCompleted()) {
            std.Thread.yield() catch {};
        }
    }

    pub fn waitAll(self: *Scheduler) void {
        while (self.active_threads.load(.acquire) > 0) {
            std.Thread.yield() catch {};
        }
    }

    pub fn shutdown(self: *Scheduler) void {
        self.shutdown_flag.store(true, .release);
    }

    pub fn getActiveThreadCount(self: *const Scheduler) usize {
        return self.active_threads.load(.acquire);
    }

    pub fn getTotalQueuedTasks(self: *const Scheduler) usize {
        var total: usize = 0;
        for (self.queues) |*queue| {
            total += queue.len();
        }
        return total;
    }
};

test "Scheduler basic spawn" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 2);
    try sched.start();
    defer sched.deinit();

    var counter: usize = 0;

    const TestFunc = struct {
        fn run(thread: *GreenThread) void {
            const c: *usize = @ptrCast(@alignCast(thread.result.?));
            _ = @atomicRmw(usize, c, .Add, 1, .seq_cst);
        }
    };

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const thread = try sched.spawn(TestFunc.run);
        thread.result = @ptrCast(&counter);
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 10), counter);
}

test "Scheduler many threads" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 4);
    try sched.start();
    defer sched.deinit();

    var counter: usize = 0;

    const TestFunc = struct {
        fn run(thread: *GreenThread) void {
            const c: *usize = @ptrCast(@alignCast(thread.result.?));
            _ = @atomicRmw(usize, c, .Add, 1, .seq_cst);
        }
    };

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const thread = try sched.spawn(TestFunc.run);
        thread.result = @ptrCast(&counter);
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 1000), counter);
}
