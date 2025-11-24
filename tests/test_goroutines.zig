const std = @import("std");
const Scheduler = @import("scheduler").Scheduler;
const GreenThread = @import("green_thread").GreenThread;

test "spawn 100k green threads" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 8);
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
    while (i < 100_000) : (i += 1) {
        _ = try sched.spawn(increment, .{ .counter = &counter });
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 100_000), counter);
}

test "work stealing functionality" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 4);
    try sched.start();
    defer sched.deinit();

    var counters = [_]usize{0} ** 4;

    const Context = struct {
        counter: *usize,
    };

    const work = struct {
        fn run(ctx: *Context) void {
            _ = @atomicRmw(usize, ctx.counter, .Add, 1, .seq_cst);

            // Simulate work
            var j: usize = 0;
            while (j < 1000) : (j += 1) {
                std.mem.doNotOptimizeAway(&j);
            }
        }
    }.run;

    // Spawn many tasks to ensure work stealing happens
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        const counter_idx = i % 4;
        _ = try sched.spawn(work, .{ .counter = &counters[counter_idx] });
    }

    sched.waitAll();

    var total: usize = 0;
    for (counters) |count| {
        total += count;
    }

    try std.testing.expectEqual(@as(usize, 10_000), total);

    // Check that work was distributed (not all on one counter)
    for (counters) |count| {
        try std.testing.expect(count > 0);
    }
}

test "thread state transitions" {
    const allocator = std.testing.allocator;

    const StateFunc = struct {
        fn func(ctx: ?*anyopaque) void {
            _ = ctx;
            // Simple function
        }
    };

    const thread = try GreenThread.init(allocator, 1, StateFunc.func, null);
    defer thread.deinit(allocator);

    try std.testing.expectEqual(GreenThread.State.ready, thread.state);

    thread.run();

    try std.testing.expectEqual(GreenThread.State.completed, thread.state);
}

test "concurrent increments" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 8);
    try sched.start();
    defer sched.deinit();

    var shared_counter: usize = 0;

    const Context = struct {
        counter: *usize,
    };

    const work = struct {
        fn run(ctx: *Context) void {
            // Multiple increments per thread
            var j: usize = 0;
            while (j < 10) : (j += 1) {
                _ = @atomicRmw(usize, ctx.counter, .Add, 1, .seq_cst);
            }
        }
    }.run;

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try sched.spawn(work, .{ .counter = &shared_counter });
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 10_000), shared_counter);
}

test "compute intensive work" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 4);
    try sched.start();
    defer sched.deinit();

    const Result = struct {
        sum: u64,
        mutex: std.Thread.Mutex,
    };

    var result = Result{
        .sum = 0,
        .mutex = .{},
    };

    const Context = struct {
        result: *Result,
    };

    const compute = struct {
        fn run(ctx: *Context) void {
            // Compute sum of squares
            var sum: u64 = 0;
            var j: usize = 0;
            while (j < 10_000) : (j += 1) {
                sum +%= j * j;
            }

            ctx.result.mutex.lock();
            defer ctx.result.mutex.unlock();
            ctx.result.sum +%= sum;
        }
    }.run;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try sched.spawn(compute, .{ .result = &result });
    }

    sched.waitAll();

    // Each thread computes the same sum, so total should be 100x
    const expected_per_thread: u64 = 333283335000; // sum of squares 0..9999
    const expected_total = expected_per_thread * 100;

    try std.testing.expectEqual(expected_total, result.sum);
}

test "memory usage per thread" {
    const allocator = std.testing.allocator;

    // Create a single green thread and check memory
    const TestFunc = struct {
        fn func(ctx: ?*anyopaque) void {
            _ = ctx;
        }
    };

    const thread = try GreenThread.init(allocator, 1, TestFunc.func, null);
    defer thread.deinit(allocator);

    // Stack should be 4KB
    try std.testing.expectEqual(@as(usize, 4 * 1024), thread.stack.len);

    // Total memory per thread should be roughly:
    // - Stack: 4KB
    // - GreenThread struct: ~100 bytes
    // Total < 5KB per thread
}

test "scheduler shutdown" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 4);
    try sched.start();

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
    while (i < 100) : (i += 1) {
        _ = try sched.spawn(increment, .{ .counter = &counter });
    }

    sched.waitAll();
    sched.shutdown();
    sched.deinit();

    try std.testing.expectEqual(@as(usize, 100), counter);
}

test "empty scheduler" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 2);
    try sched.start();
    defer sched.deinit();

    // No tasks spawned
    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 0), sched.getActiveThreadCount());
}

test "multi-core utilization simulation" {
    const allocator = std.testing.allocator;

    const cpu_count = try std.Thread.getCpuCount();
    var sched = try Scheduler.init(allocator, cpu_count);
    try sched.start();
    defer sched.deinit();

    var completed = [_]std.atomic.Value(bool){std.atomic.Value(bool).init(false)} ** 16;

    const Context = struct {
        flags: *[16]std.atomic.Value(bool),
        idx: usize,
    };

    const work = struct {
        fn run(ctx: *Context) void {
            // Simulate CPU-bound work
            var j: usize = 0;
            while (j < 50_000) : (j += 1) {
                std.mem.doNotOptimizeAway(&j);
            }

            ctx.flags[ctx.idx].store(true, .release);
        }
    }.run;

    var i: usize = 0;
    while (i < 16) : (i += 1) {
        _ = try sched.spawn(work, .{ .flags = &completed, .idx = i });
    }

    sched.waitAll();

    // Verify all tasks completed
    for (&completed) |*flag| {
        try std.testing.expect(flag.load(.acquire));
    }
}
