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

    /// Simple spawn for compatibility with legacy API (function takes *GreenThread)
    pub fn spawnSimple(self: *Scheduler, func: *const fn (*GreenThread) void) !*GreenThread {
        const id = self.next_id.fetchAdd(1, .monotonic);

        // Wrapper that converts anyopaque to GreenThread
        const Wrapper = struct {
            fn call(ctx: ?*anyopaque) void {
                const thread: *GreenThread = @ptrCast(@alignCast(ctx.?));
                const f: *const fn (*GreenThread) void = @ptrCast(@alignCast(thread.result.?));
                f(thread);
            }
        };

        const thread = try GreenThread.init(self.allocator, id, Wrapper.call, null, null);
        thread.result = @ptrCast(&func);

        // Round-robin assignment to queues
        const queue_idx = @as(usize, @intCast(id % self.num_workers));
        try self.queues[queue_idx].push(thread);

        // Increment counter (workers will pick it up)
        _ = self.active_threads.fetchAdd(1, .acq_rel);

        return thread;
    }

    /// Spawn a green thread with type-safe context (comptime generic)
    pub fn spawn(
        self: *Scheduler,
        comptime func: anytype,
        context: anytype,
    ) !*GreenThread {
        // Extract expected context type from function signature
        const func_info = @typeInfo(@TypeOf(func));
        if (func_info != .@"fn") {
            @compileError("spawn expects a function");
        }

        const params = func_info.@"fn".params;
        if (params.len != 1) {
            @compileError("Function must take exactly 1 parameter");
        }

        const ExpectedPtrType = params[0].type orelse @compileError("Function parameter must have explicit type");
        const ptr_info = @typeInfo(ExpectedPtrType);
        if (ptr_info != .pointer) {
            @compileError("Function parameter must be a pointer");
        }

        const ExpectedContext = ptr_info.pointer.child;

        // Allocate expected context type on heap
        const ctx = try self.allocator.create(ExpectedContext);
        errdefer self.allocator.destroy(ctx);

        // Convert anonymous struct to expected type at comptime
        ctx.* = convertToType(ExpectedContext, context);

        // Create type-erased wrapper and cleanup function
        const Gen = struct {
            fn wrapper(user_ctx: ?*anyopaque) void {
                const typed_ctx: *ExpectedContext = @ptrCast(@alignCast(user_ctx.?));
                @call(.auto, func, .{typed_ctx});
            }

            fn cleanup(thread: *GreenThread, allocator: std.mem.Allocator) void {
                if (thread.user_context) |user_ctx| {
                    const typed_ctx: *ExpectedContext = @ptrCast(@alignCast(user_ctx));
                    allocator.destroy(typed_ctx);
                }
            }
        };

        // Create GreenThread with wrapper, context, and cleanup
        const id = self.next_id.fetchAdd(1, .monotonic);
        const thread = try GreenThread.init(self.allocator, id, Gen.wrapper, @ptrCast(ctx), Gen.cleanup);

        // Round-robin assignment to queues
        const queue_idx = @as(usize, @intCast(id % self.num_workers));
        try self.queues[queue_idx].push(thread);

        // Increment counter (workers will pick it up)
        _ = self.active_threads.fetchAdd(1, .acq_rel);

        return thread;
    }

    /// Convert anonymous struct to expected type at comptime
    fn convertToType(comptime T: type, value: anytype) T {
        const ValueType = @TypeOf(value);
        const value_info = @typeInfo(ValueType);

        if (value_info != .@"struct") {
            @compileError("Expected struct value");
        }

        // Create instance of target type
        var result: T = undefined;

        // Copy fields from value to result
        inline for (@typeInfo(T).@"struct".fields) |field| {
            if (@hasField(ValueType, field.name)) {
                @field(result, field.name) = @field(value, field.name);
            } else {
                @compileError("Missing required field: " ++ field.name);
            }
        }

        return result;
    }

    fn workerLoop(self: *Scheduler, worker_id: usize) void {
        const queue = &self.queues[worker_id];

        while (!self.shutdown_flag.load(.acquire)) {
            // Try local queue first (LIFO for cache locality)
            if (queue.pop()) |task| {
                if (task.state == .ready) {
                    task.run();
                    // Cleanup user context if needed
                    if (task.context_cleanup) |cleanup| {
                        cleanup(task, self.allocator);
                    }
                }
                _ = self.active_threads.fetchSub(1, .release);
                continue;
            }

            // Try stealing from other queues (FIFO)
            if (self.trySteal(worker_id)) |task| {
                if (task.state == .ready) {
                    task.run();
                    // Cleanup user context if needed
                    if (task.context_cleanup) |cleanup| {
                        cleanup(task, self.allocator);
                    }
                }
                _ = self.active_threads.fetchSub(1, .release);
                continue;
            }

            // No work available, yield CPU
            std.Thread.yield() catch {};
        }
    }

    /// Determines optimal SIMD width for current architecture
    fn optimalSIMDWidth() comptime_int {
        const builtin = @import("builtin");
        if (builtin.cpu.arch == .x86_64) {
            // AVX2: 8-wide (256-bit registers)
            return 8;
        } else if (builtin.cpu.arch == .aarch64) {
            // NEON: 4-wide (128-bit registers)
            return 4;
        }
        return 1; // No SIMD
    }

    fn trySteal(self: *Scheduler, worker_id: usize) ?*GreenThread {
        const vec_size = comptime optimalSIMDWidth();

        if (vec_size > 1 and self.num_workers >= vec_size) {
            return self.simdSteal(worker_id, vec_size);
        } else {
            return self.scalarSteal(worker_id);
        }
    }

    fn simdSteal(self: *Scheduler, worker_id: usize, comptime vec_size: comptime_int) ?*GreenThread {
        const num_workers = self.num_workers;
        var start_offset: usize = 1; // Start checking from worker_id + 1

        // Process queues in batches of vec_size
        while (start_offset < num_workers) {
            const remaining = num_workers - start_offset;
            const batch_size = @min(vec_size, remaining);

            if (batch_size == vec_size) {
                // Full SIMD batch
                var sizes: @Vector(vec_size, u32) = undefined;

                // Gather queue sizes
                inline for (0..vec_size) |j| {
                    const target = (worker_id + start_offset + j) % num_workers;
                    sizes[j] = @intCast(self.queues[target].size());
                }

                // Find first non-empty queue
                const zero_vec: @Vector(vec_size, u32) = @splat(0);
                const has_work = sizes > zero_vec;

                // Try stealing from any non-empty queue in this batch
                inline for (0..vec_size) |j| {
                    if (has_work[j]) {
                        const target = (worker_id + start_offset + j) % num_workers;
                        if (self.queues[target].steal()) |task| {
                            return task;
                        }
                    }
                }
            } else {
                // Handle remainder with scalar code
                for (0..batch_size) |j| {
                    const target = (worker_id + start_offset + j) % num_workers;
                    if (self.queues[target].steal()) |task| {
                        return task;
                    }
                }
            }

            start_offset += vec_size;
        }

        return null;
    }

    fn scalarSteal(self: *Scheduler, worker_id: usize) ?*GreenThread {
        // Original scalar implementation
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

    const Context = struct {
        counter: *usize,
    };

    const increment = struct {
        fn run(ctx: *Context) void {
            _ = @atomicRmw(usize, ctx.counter, .Add, 1, .seq_cst);
        }
    }.run;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const ctx = Context{ .counter = &counter };
        _ = try sched.spawn(increment, ctx);
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

    const Context = struct {
        counter: *usize,
    };

    const increment = struct {
        fn run(ctx: *Context) void {
            _ = @atomicRmw(usize, ctx.counter, .Add, 1, .seq_cst);
        }
    }.run;

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const ctx = Context{ .counter = &counter };
        _ = try sched.spawn(increment, ctx);
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 1000), counter);
}

test "spawn with anonymous struct" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 2);
    try sched.start();
    defer sched.deinit();

    var counter: usize = 0;

    const Context = struct {
        counter: *usize,
    };

    const increment = struct {
        fn run(ctx: *Context) void {
            _ = @atomicRmw(usize, ctx.counter, .Add, 1, .seq_cst);
        }
    }.run;

    // Test both named struct and anonymous struct syntax
    _ = try sched.spawn(increment, Context{ .counter = &counter });
    _ = try sched.spawn(increment, .{ .counter = &counter });

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 2), counter);
}
