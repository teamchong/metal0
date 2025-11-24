const std = @import("std");
const Scheduler = @import("scheduler").Scheduler;
const GreenThread = @import("green_thread").GreenThread;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test with different thread counts
    const thread_counts = [_]usize{ 4, 8, 16 };

    for (thread_counts) |num_threads| {
        std.debug.print("\n=== Benchmarking with {} threads ===\n", .{num_threads});

        var sched = try Scheduler.init(allocator, num_threads);
        try sched.start();
        defer sched.deinit();

        var counter: usize = 0;

        const Context = struct {
            counter: *usize,
        };

        const TestFunc = struct {
            fn run(ctx: *Context) void {
                _ = @atomicRmw(usize, ctx.counter, .Add, 1, .seq_cst);
            }
        };

        const num_tasks: usize = 100_000;
        const start = std.time.nanoTimestamp();

        // Spawn all tasks
        var i: usize = 0;
        while (i < num_tasks) : (i += 1) {
            _ = try sched.spawn(TestFunc.run, .{ .counter = &counter });
        }

        // Wait for completion
        sched.waitAll();

        const elapsed = std.time.nanoTimestamp() - start;
        const elapsed_ms = @divTrunc(elapsed, 1_000_000);
        const elapsed_us = @divTrunc(elapsed, 1_000);

        std.debug.print("Tasks completed: {}\n", .{counter});
        std.debug.print("Time: {} ms ({} μs)\n", .{ elapsed_ms, elapsed_us });
        std.debug.print("Tasks/sec: {}\n", .{@divTrunc(num_tasks * 1_000_000_000, @as(usize, @intCast(elapsed)))});
        std.debug.print("Avg task time: {} ns\n", .{@divTrunc(elapsed, num_tasks)});
    }

    std.debug.print("\n=== Work-Stealing Stress Test ===\n", .{});
    std.debug.print("(Many threads competing for work)\n", .{});

    // Stress test: 16 threads, unbalanced workload
    var sched = try Scheduler.init(allocator, 16);
    try sched.start();
    defer sched.deinit();

    var counter: usize = 0;

    const Context = struct {
        counter: *usize,
    };

    const StressFunc = struct {
        fn run(ctx: *Context) void {
            // Simulate varying work
            var sum: usize = 0;
            for (0..100) |j| {
                sum +%= j;
            }
            std.mem.doNotOptimizeAway(&sum);

            _ = @atomicRmw(usize, ctx.counter, .Add, 1, .seq_cst);
        }
    };

    const num_tasks: usize = 50_000;
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < num_tasks) : (i += 1) {
        _ = try sched.spawn(StressFunc.run, .{ .counter = &counter });
    }

    sched.waitAll();

    const elapsed = std.time.nanoTimestamp() - start;
    const elapsed_ms = @divTrunc(elapsed, 1_000_000);

    std.debug.print("Tasks completed: {}\n", .{counter});
    std.debug.print("Time: {} ms\n", .{elapsed_ms});
    std.debug.print("Tasks/sec: {}\n", .{@divTrunc(num_tasks * 1_000_000_000, @as(usize, @intCast(elapsed)))});
}
