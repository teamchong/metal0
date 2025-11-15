const std = @import("std");
const testing = std.testing;
const Future = @import("future.zig").Future;
const Poll = @import("future.zig").Poll;
const Waker = @import("future.zig").Waker;
const Context = @import("future.zig").Context;
const Task = @import("task.zig").Task;
const TaskState = @import("task.zig").TaskState;
const poll_mod = @import("future/poll.zig");
const combinator = @import("future/combinator.zig");

test "Future - basic creation and resolution" {
    const allocator = testing.allocator;

    const future = try Future(i32).init(allocator);
    defer future.deinit();

    try testing.expect(!future.isReady());
    try testing.expect(future.tryGet() == null);

    future.resolve(42);

    try testing.expect(future.isReady());
    try testing.expectEqual(@as(i32, 42), future.tryGet().?);
}

test "Future - poll pending" {
    const allocator = testing.allocator;

    const future = try Future(i32).init(allocator);
    defer future.deinit();

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);

    var waker = Waker.init(temp_task);
    const ctx = Context.init(&waker);

    const result = future.poll(&ctx);
    try testing.expect(result.isPending());
}

test "Future - poll ready" {
    const allocator = testing.allocator;

    const future = try Future(i32).init(allocator);
    defer future.deinit();

    future.resolve(123);

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);

    var waker = Waker.init(temp_task);
    const ctx = Context.init(&waker);

    const result = future.poll(&ctx);
    try testing.expect(result.isReady());
    try testing.expectEqual(@as(i32, 123), result.unwrap());
}

test "Future - waker registration" {
    const allocator = testing.allocator;

    const future = try Future(i32).init(allocator);
    defer future.deinit();

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .running;

    var waker = Waker.init(temp_task);
    const ctx = Context.init(&waker);

    // Poll while pending - should register waker
    _ = future.poll(&ctx);

    // Resolve - should wake task
    future.resolve(99);

    // Task should be runnable
    try testing.expectEqual(TaskState.runnable, temp_task.state);
}

test "Future - resolved helper" {
    const allocator = testing.allocator;

    const future = try @import("future.zig").resolved(i32, allocator, 777);
    defer future.deinit();

    try testing.expect(future.isReady());
    try testing.expectEqual(@as(i32, 777), future.tryGet().?);
}

test "Future - blockOn" {
    const allocator = testing.allocator;

    const future = try Future(i32).init(allocator);
    defer future.deinit();

    // Resolve immediately for this test
    future.resolve(456);

    const result = try poll_mod.blockOn(i32, future, allocator);
    try testing.expectEqual(@as(i32, 456), result);
}

test "Future - join two futures" {
    const allocator = testing.allocator;

    const f1 = try Future(i32).init(allocator);
    defer f1.deinit();
    f1.resolve(10);

    const f2 = try Future(i32).init(allocator);
    defer f2.deinit();
    f2.resolve(20);

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .running;

    const result = try combinator.join(i32, i32, f1, f2, allocator, temp_task);
    try testing.expectEqual(@as(i32, 10), result[0]);
    try testing.expectEqual(@as(i32, 20), result[1]);
}

test "Future - join3" {
    const allocator = testing.allocator;

    const f1 = try Future(i32).init(allocator);
    defer f1.deinit();
    f1.resolve(1);

    const f2 = try Future(i32).init(allocator);
    defer f2.deinit();
    f2.resolve(2);

    const f3 = try Future(i32).init(allocator);
    defer f3.deinit();
    f3.resolve(3);

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .running;

    const result = try combinator.join3(i32, i32, i32, f1, f2, f3, allocator, temp_task);
    try testing.expectEqual(@as(i32, 1), result[0]);
    try testing.expectEqual(@as(i32, 2), result[1]);
    try testing.expectEqual(@as(i32, 3), result[2]);
}

test "Future - race" {
    const allocator = testing.allocator;

    const f1 = try Future(i32).init(allocator);
    defer f1.deinit();

    const f2 = try Future(i32).init(allocator);
    defer f2.deinit();
    f2.resolve(99); // This one is ready first

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .running;

    var futures = [_]*Future(i32){ f1, f2 };
    const result = try combinator.race(i32, &futures, allocator, temp_task);
    try testing.expectEqual(@as(i32, 99), result);
}

test "Future - select with index" {
    const allocator = testing.allocator;

    const f1 = try Future(i32).init(allocator);
    defer f1.deinit();

    const f2 = try Future(i32).init(allocator);
    defer f2.deinit();
    f2.resolve(88);

    const f3 = try Future(i32).init(allocator);
    defer f3.deinit();

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .running;

    var futures = [_]*Future(i32){ f1, f2, f3 };
    const result = try combinator.select(i32, &futures, allocator, temp_task);

    try testing.expectEqual(@as(usize, 1), result[0]); // Index of f2
    try testing.expectEqual(@as(i32, 88), result[1]); // Value from f2
}

test "Future - joinAll" {
    const allocator = testing.allocator;

    const f1 = try Future(i32).init(allocator);
    defer f1.deinit();
    f1.resolve(10);

    const f2 = try Future(i32).init(allocator);
    defer f2.deinit();
    f2.resolve(20);

    const f3 = try Future(i32).init(allocator);
    defer f3.deinit();
    f3.resolve(30);

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .running;

    var futures = [_]*Future(i32){ f1, f2, f3 };
    const results = try combinator.joinAll(i32, &futures, allocator, temp_task);
    defer allocator.free(results);

    try testing.expectEqual(@as(i32, 10), results[0]);
    try testing.expectEqual(@as(i32, 20), results[1]);
    try testing.expectEqual(@as(i32, 30), results[2]);
}

test "Poll - isReady and isPending" {
    const p1 = Poll(i32){ .ready = 42 };
    const p2 = Poll(i32){ .pending = {} };

    try testing.expect(p1.isReady());
    try testing.expect(!p1.isPending());
    try testing.expect(!p2.isReady());
    try testing.expect(p2.isPending());
}

test "Poll - unwrap" {
    const p = Poll(i32){ .ready = 123 };
    try testing.expectEqual(@as(i32, 123), p.unwrap());
}

test "Waker - wake task" {
    const allocator = testing.allocator;

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .waiting;

    var waker = Waker.init(temp_task);
    waker.wake();

    try testing.expectEqual(TaskState.runnable, temp_task.state);
}

test "Waker - wakeByRef" {
    const allocator = testing.allocator;

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .waiting;

    const waker = Waker.init(temp_task);
    waker.wakeByRef();

    try testing.expectEqual(TaskState.runnable, temp_task.state);
}

test "Context - wake via context" {
    const allocator = testing.allocator;

    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);
    temp_task.* = Task.init(1, undefined, undefined);
    temp_task.state = .waiting;

    const waker = Waker.init(temp_task);
    const ctx = Context.init(&waker);

    ctx.wake();

    try testing.expectEqual(TaskState.runnable, temp_task.state);
}

test "Future - multiple wakers" {
    const allocator = testing.allocator;

    const future = try Future(i32).init(allocator);
    defer future.deinit();

    const task1 = try allocator.create(Task);
    defer allocator.destroy(task1);
    task1.* = Task.init(1, undefined, undefined);
    task1.state = .waiting;

    const task2 = try allocator.create(Task);
    defer allocator.destroy(task2);
    task2.* = Task.init(2, undefined, undefined);
    task2.state = .waiting;

    var waker1 = Waker.init(task1);
    var waker2 = Waker.init(task2);

    const ctx1 = Context.init(&waker1);
    const ctx2 = Context.init(&waker2);

    // Both poll and register
    _ = future.poll(&ctx1);
    _ = future.poll(&ctx2);

    // Resolve should wake both
    future.resolve(100);

    try testing.expectEqual(TaskState.runnable, task1.state);
    try testing.expectEqual(TaskState.runnable, task2.state);
}

test "Future - error handling (reject)" {
    const allocator = testing.allocator;

    const future = try Future(i32).init(allocator);
    defer future.deinit();

    try testing.expect(!future.isReady());

    future.reject(error.TestError);

    // Future should be in error state (not ready)
    try testing.expect(!future.isReady());
}
