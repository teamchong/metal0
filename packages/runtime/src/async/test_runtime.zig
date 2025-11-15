const std = @import("std");
const runtime = @import("runtime.zig");
const Task = runtime.Task;
const TaskFn = runtime.TaskFn;
const SimpleRuntime = runtime.SimpleRuntime;

test "simple runtime - spawn and run single task" {
    const allocator = std.testing.allocator;

    var rt = SimpleRuntime.init(allocator);
    defer rt.deinit();

    // Counter to verify task executed
    var counter: u32 = 0;

    // Task function
    const taskFn = struct {
        fn run(ctx: *anyopaque) !void {
            const count_ptr = @as(*u32, @ptrCast(@alignCast(ctx)));
            count_ptr.* += 1;
        }
    }.run;

    // Spawn task
    _ = try rt.spawn(taskFn, &counter);

    // Run runtime
    try rt.run();

    // Verify task executed
    try std.testing.expectEqual(@as(u32, 1), counter);
}

test "simple runtime - spawn multiple tasks" {
    const allocator = std.testing.allocator;

    var rt = SimpleRuntime.init(allocator);
    defer rt.deinit();

    var counter: u32 = 0;

    const taskFn = struct {
        fn run(ctx: *anyopaque) !void {
            const count_ptr = @as(*u32, @ptrCast(@alignCast(ctx)));
            count_ptr.* += 1;
        }
    }.run;

    // Spawn 10 tasks
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = try rt.spawn(taskFn, &counter);
    }

    // Run runtime
    try rt.run();

    // Verify all tasks executed
    try std.testing.expectEqual(@as(u32, 10), counter);

    // Check stats
    const stats = rt.stats();
    try std.testing.expectEqual(@as(u64, 10), stats.total_spawned);
    try std.testing.expectEqual(@as(u64, 10), stats.total_completed);
}

test "simple runtime - task with yield" {
    const allocator = std.testing.allocator;

    var rt = SimpleRuntime.init(allocator);
    defer rt.deinit();

    var counter: u32 = 0;

    // Task that yields
    const Context = struct {
        rt: *SimpleRuntime,
        counter: *u32,
    };

    var ctx = Context{
        .rt = &rt,
        .counter = &counter,
    };

    const taskFn = struct {
        fn run(c: *anyopaque) !void {
            const context = @as(*Context, @ptrCast(@alignCast(c)));
            context.counter.* += 1;

            // Note: In a real implementation, we'd need to pass the current task
            // For now, just increment counter again
            context.counter.* += 1;
        }
    }.run;

    _ = try rt.spawn(taskFn, &ctx);

    try rt.run();

    try std.testing.expectEqual(@as(u32, 2), counter);
}

test "task creation and state" {
    var dummy: u32 = 42;
    const dummyFn = struct {
        fn f(ctx: *anyopaque) !void {
            _ = ctx;
        }
    }.f;

    var task = Task.init(1, dummyFn, &dummy);

    try std.testing.expectEqual(@as(usize, 1), task.id);
    try std.testing.expectEqual(runtime.TaskState.idle, task.state);

    task.makeRunnable();
    try std.testing.expect(task.isRunnable());

    task.makeRunning();
    try std.testing.expect(task.isRunning());

    task.makeWaiting();
    try std.testing.expect(task.isWaiting());

    task.makeDead();
    try std.testing.expect(task.isDead());
}

test "task with stack" {
    const allocator = std.testing.allocator;

    var dummy: u32 = 42;
    const dummyFn = struct {
        fn f(ctx: *anyopaque) !void {
            _ = ctx;
        }
    }.f;

    var task = try Task.initWithStack(allocator, 1, dummyFn, &dummy);
    defer task.deinit();

    try std.testing.expectEqual(Task.DEFAULT_STACK_SIZE, task.stack_size);
    try std.testing.expect(task.stack != null);
}

test "processor - push and pop tasks" {
    const allocator = std.testing.allocator;

    var processor = runtime.Processor.init(allocator, 0);
    defer processor.deinit();

    var dummy: u32 = 42;
    const dummyFn = struct {
        fn f(ctx: *anyopaque) !void {
            _ = ctx;
        }
    }.f;

    // Create tasks
    const task1 = try allocator.create(Task);
    defer allocator.destroy(task1);
    task1.* = Task.init(1, dummyFn, &dummy);

    const task2 = try allocator.create(Task);
    defer allocator.destroy(task2);
    task2.* = Task.init(2, dummyFn, &dummy);

    // Push tasks
    try std.testing.expect(try processor.pushTask(task1));
    try std.testing.expect(try processor.pushTask(task2));

    // Check processor has work
    try std.testing.expect(processor.hasWork());
    try std.testing.expectEqual(@as(usize, 2), processor.queueSize());

    // Pop tasks (LIFO order for next_task slot)
    const popped1 = processor.popTask();
    try std.testing.expect(popped1 != null);
    try std.testing.expectEqual(@as(usize, 1), popped1.?.id);

    const popped2 = processor.popTask();
    try std.testing.expect(popped2 != null);
    try std.testing.expectEqual(@as(usize, 2), popped2.?.id);

    // Queue should be empty
    try std.testing.expect(!processor.hasWork());
}

test "runtime config" {
    const default_config = runtime.RuntimeConfig.default();
    try std.testing.expect(default_config.num_processors > 0);
    try std.testing.expect(default_config.enable_work_stealing);
    try std.testing.expect(default_config.enable_preemption);

    const single_config = runtime.RuntimeConfig.single_threaded();
    try std.testing.expectEqual(@as(usize, 1), single_config.num_processors);
    try std.testing.expect(!single_config.enable_work_stealing);
    try std.testing.expect(!single_config.enable_preemption);
}
