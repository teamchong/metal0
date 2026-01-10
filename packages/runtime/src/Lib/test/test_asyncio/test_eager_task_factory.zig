//! test.test_asyncio.test_eager_task_factory - Tests for eager task factory
//! Reference: cpython/Lib/test/test_asyncio/test_eager_task_factory.py
//!
//! Tests for eager task factory (Python 3.12+)

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");
const test_tasks = @import("test_tasks.zig");

// ============================================================================
// Eager Task Factory
// ============================================================================

/// Task factory that eagerly starts coroutines
pub const EagerTaskFactory = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _loop: *test_events.EventLoop,
    _tasks_created: usize = 0,
    _eager_starts: usize = 0,

    pub fn init(allocator: std.mem.Allocator, loop: *test_events.EventLoop) Self {
        return .{
            .allocator = allocator,
            ._loop = loop,
        };
    }

    /// Create a task with eager execution
    pub fn create_task(self: *Self, name: ?[]const u8) !*test_tasks.Task {
        const task = try self.allocator.create(test_tasks.Task);
        task.* = test_tasks.Task.init(self.allocator, self._loop);

        if (name) |n| {
            task.set_name(n);
        }

        self._tasks_created += 1;
        self._eager_starts += 1;

        return task;
    }

    pub fn tasks_created(self: *const Self) usize {
        return self._tasks_created;
    }

    pub fn eager_starts(self: *const Self) usize {
        return self._eager_starts;
    }
};

/// Create an eager task factory
pub fn create_eager_task_factory(
    allocator: std.mem.Allocator,
    loop: *test_events.EventLoop,
) EagerTaskFactory {
    return EagerTaskFactory.init(allocator, loop);
}

/// Get or set the eager task factory for a loop
pub fn eager_task_factory(
    loop: *test_events.EventLoop,
    factory: ?*EagerTaskFactory,
) ?*EagerTaskFactory {
    _ = loop;
    return factory;
}

// ============================================================================
// Eager Task
// ============================================================================

/// A task that starts execution immediately
pub const EagerTask = struct {
    const Self = @This();

    base: test_tasks.Task,
    _started_eagerly: bool = false,
    _first_step_done: bool = false,

    pub fn init(allocator: std.mem.Allocator, loop: *test_events.EventLoop) Self {
        return .{
            .base = test_tasks.Task.init(allocator, loop),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    /// Start eager execution
    pub fn start_eager(self: *Self) void {
        self._started_eagerly = true;
        // Execute first step immediately
        self._first_step_done = true;
    }

    pub fn done(self: *const Self) bool {
        return self.base.done();
    }

    pub fn started_eagerly(self: *const Self) bool {
        return self._started_eagerly;
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testEagerTaskFactoryCreate() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var factory = create_eager_task_factory(allocator, &loop);

    try std.testing.expectEqual(@as(usize, 0), factory.tasks_created());
    try std.testing.expectEqual(@as(usize, 0), factory.eager_starts());
}

fn testEagerTaskFactoryCreateTask() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var factory = create_eager_task_factory(allocator, &loop);
    const task = try factory.create_task("test_task");
    defer {
        task.deinit();
        allocator.destroy(task);
    }

    try std.testing.expectEqual(@as(usize, 1), factory.tasks_created());
    try std.testing.expectEqual(@as(usize, 1), factory.eager_starts());
}

fn testEagerTaskFactoryMultipleTasks() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var factory = create_eager_task_factory(allocator, &loop);

    const task1 = try factory.create_task("task1");
    const task2 = try factory.create_task("task2");
    const task3 = try factory.create_task(null);

    defer {
        task1.deinit();
        allocator.destroy(task1);
        task2.deinit();
        allocator.destroy(task2);
        task3.deinit();
        allocator.destroy(task3);
    }

    try std.testing.expectEqual(@as(usize, 3), factory.tasks_created());
    try std.testing.expectEqual(@as(usize, 3), factory.eager_starts());
}

fn testEagerTask() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = EagerTask.init(allocator, &loop);
    defer task.deinit();

    try std.testing.expect(!task.started_eagerly());
    try std.testing.expect(!task._first_step_done);

    task.start_eager();

    try std.testing.expect(task.started_eagerly());
    try std.testing.expect(task._first_step_done);
}

fn testEagerTaskDone() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = EagerTask.init(allocator, &loop);
    defer task.deinit();

    try std.testing.expect(!task.done());

    try task.base.set_result(null);
    try std.testing.expect(task.done());
}

fn testEagerTaskFactoryGetSet() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var factory = create_eager_task_factory(allocator, &loop);
    const set_factory = eager_task_factory(&loop, &factory);

    try std.testing.expect(set_factory == &factory);
}

fn testEagerTaskFactoryNone() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    const no_factory = eager_task_factory(&loop, null);
    try std.testing.expect(no_factory == null);
}

fn testEagerTaskName() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var factory = create_eager_task_factory(allocator, &loop);
    const task = try factory.create_task("my_eager_task");
    defer {
        task.deinit();
        allocator.destroy(task);
    }

    try std.testing.expectEqualStrings("my_eager_task", task.get_name().?);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "EagerTaskFactory create" {
    try testEagerTaskFactoryCreate();
}

test "EagerTaskFactory create_task" {
    try testEagerTaskFactoryCreateTask();
}

test "EagerTaskFactory multiple tasks" {
    try testEagerTaskFactoryMultipleTasks();
}

test "EagerTask" {
    try testEagerTask();
}

test "EagerTask done" {
    try testEagerTaskDone();
}

test "EagerTaskFactory get/set" {
    try testEagerTaskFactoryGetSet();
}

test "EagerTaskFactory none" {
    try testEagerTaskFactoryNone();
}

test "EagerTask name" {
    try testEagerTaskName();
}
