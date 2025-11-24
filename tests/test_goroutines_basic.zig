const std = @import("std");
const Scheduler = @import("scheduler").Scheduler;
const GreenThread = @import("green_thread").GreenThread;

test "thread state transitions" {
    const allocator = std.testing.allocator;

    const StateFunc = struct {
        fn func(thread: *GreenThread) void {
            _ = thread;
            // Simple function
        }
    };

    const thread = try GreenThread.init(allocator, 1, StateFunc.func);
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

    const CounterFunc = struct {
        fn run(thread: *GreenThread) void {
            const c: *usize = @alignCast(@ptrCast(thread.result.?));
            _ = @atomicRmw(usize, c, .Add, 1, .seq_cst);
        }
    };

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const thread = try sched.spawn(CounterFunc.run);
        thread.result = @ptrCast(&counter);
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

    const CounterFunc = struct {
        fn run(thread: *GreenThread) void {
            const c: *usize = @alignCast(@ptrCast(thread.result.?));
            _ = @atomicRmw(usize, c, .Add, 1, .seq_cst);
        }
    };

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const thread = try sched.spawn(CounterFunc.run);
        thread.result = @ptrCast(&counter);
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

    const IncrementFunc = struct {
        fn run(thread: *GreenThread) void {
            const c: *usize = @alignCast(@ptrCast(thread.result.?));

            // Multiple increments per thread with work
            var j: usize = 0;
            while (j < 10) : (j += 1) {
                _ = @atomicRmw(usize, c, .Add, 1, .seq_cst);
                // Small amount of work
                var k: usize = 0;
                while (k < 100) : (k += 1) {
                    std.mem.doNotOptimizeAway(&k);
                }
            }
        }
    };

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const thread = try sched.spawn(IncrementFunc.run);
        thread.result = @ptrCast(&shared_counter);
    }

    sched.waitAll();

    try std.testing.expectEqual(@as(usize, 1000), shared_counter);
}

test "memory usage per thread" {
    const allocator = std.testing.allocator;

    const TestFunc = struct {
        fn func(thread: *GreenThread) void {
            _ = thread;
        }
    };

    const thread = try GreenThread.init(allocator, 1, TestFunc.func);
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

    const WorkFunc = struct {
        fn run(thread: *GreenThread) void {
            const cs: *[4]std.atomic.Value(usize) = @alignCast(@ptrCast(thread.result.?));
            const idx = thread.id % 4;

            _ = cs[idx].fetchAdd(1, .seq_cst);

            // Simulate work
            var j: usize = 0;
            while (j < 100) : (j += 1) {
                std.mem.doNotOptimizeAway(&j);
            }
        }
    };

    // Spawn tasks
    var i: usize = 0;
    while (i < 400) : (i += 1) {
        const thread = try sched.spawn(WorkFunc.run);
        thread.result = @ptrCast(&counters);
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
