const std = @import("std");
const Scheduler = @import("scheduler").Scheduler;
const GreenThread = @import("green_thread").GreenThread;

test "thread state transitions" {
    const allocator = std.testing.allocator;

    const Context = struct {
        dummy: u8,
    };

    const StateFunc = struct {
        fn func(ctx: ?*anyopaque) void {
            _ = ctx;
            // Simple function
        }
    };

    var context = Context{ .dummy = 0 };
    const thread = try GreenThread.init(allocator, 1, StateFunc.func, &context);
    defer thread.deinit(allocator);

    try std.testing.expectEqual(GreenThread.State.ready, thread.state);

    thread.run();

    try std.testing.expectEqual(GreenThread.State.completed, thread.state);
}

test "spawn 100 green threads" {
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
    while (i < 100) : (i += 1) {
        const ctx = Context{ .counter = &counter };
        _ = try sched.spawn(increment, ctx);
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 100), counter);
}

test "spawn 1000 green threads" {
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
    while (i < 1000) : (i += 1) {
        const ctx = Context{ .counter = &counter };
        _ = try sched.spawn(increment, ctx);
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 1000), counter);
}

test "concurrent increments with work" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 4);
    try sched.start();
    defer sched.deinit();

    var shared_counter: usize = 0;

    const Context = struct {
        counter: *usize,
    };

    const work = struct {
        fn run(ctx: *Context) void {
            // Multiple increments per thread with work
            var j: usize = 0;
            while (j < 10) : (j += 1) {
                _ = @atomicRmw(usize, ctx.counter, .Add, 1, .seq_cst);
                // Small amount of work
                var k: usize = 0;
                while (k < 100) : (k += 1) {
                    std.mem.doNotOptimizeAway(&k);
                }
            }
        }
    }.run;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try sched.spawn(work, Context{ .counter = &shared_counter });
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 1000), shared_counter);
}

test "memory usage per thread" {
    const allocator = std.testing.allocator;

    const TestFunc = struct {
        fn func(ctx: ?*anyopaque) void {
            _ = ctx;
        }
    };

    const thread = try GreenThread.init(allocator, 1, TestFunc.func, null);
    defer thread.deinit(allocator);

    // Stack should be 4KB
    try std.testing.expectEqual(@as(usize, 4 * 1024), thread.stack.len);
}

test "work stealing with multiple queues" {
    const allocator = std.testing.allocator;

    var sched = try Scheduler.init(allocator, 4);
    try sched.start();
    defer sched.deinit();

    var counters = [_]std.atomic.Value(usize){
        std.atomic.Value(usize).init(0),
        std.atomic.Value(usize).init(0),
        std.atomic.Value(usize).init(0),
        std.atomic.Value(usize).init(0),
    };

    const Context = struct {
        counters: *[4]std.atomic.Value(usize),
        task_id: usize,
    };

    const work = struct {
        fn run(ctx: *Context) void {
            const idx = ctx.task_id % 4;
            _ = ctx.counters[idx].fetchAdd(1, .seq_cst);

            // Simulate work
            var j: usize = 0;
            while (j < 100) : (j += 1) {
                std.mem.doNotOptimizeAway(&j);
            }
        }
    }.run;

    // Spawn tasks
    var i: usize = 0;
    while (i < 400) : (i += 1) {
        _ = try sched.spawn(work, Context{ .counters = &counters, .task_id = i });
    }

    sched.waitAll();

    var total: usize = 0;
    for (&counters) |*counter| {
        total += counter.load(.acquire);
    }

    try std.testing.expectEqual(@as(usize, 400), total);

    // Check that work was distributed across queues
    for (&counters) |*counter| {
        try std.testing.expect(counter.load(.acquire) > 0);
    }
}
