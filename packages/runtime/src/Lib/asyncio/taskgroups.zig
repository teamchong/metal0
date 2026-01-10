//! asyncio.taskgroups - TaskGroup for structured concurrency
//! Reference: cpython/Lib/asyncio/taskgroups.py
//! Python 3.11+ feature

const std = @import("std");
const tasks = @import("tasks.zig");
const futures = @import("futures.zig");
const exceptions = @import("exceptions.zig");

/// TaskGroup - structured concurrency primitive
/// CPython: class TaskGroup
pub const TaskGroup = struct {
    tasks_list: std.ArrayList(*tasks.Task),
    errors: std.ArrayList(anyerror),
    entered: bool,
    exiting: bool,
    aborting: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TaskGroup {
        return .{
            .tasks_list = .{},
            .errors = .{},
            .entered = false,
            .exiting = false,
            .aborting = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TaskGroup) void {
        self.tasks_list.deinit(self.allocator);
        self.errors.deinit(self.allocator);
    }

    /// Enter context (__aenter__)
    pub fn enter(self: *TaskGroup) !*TaskGroup {
        if (self.entered) {
            return error.AlreadyEntered;
        }
        self.entered = true;
        return self;
    }

    /// Exit context (__aexit__)
    pub fn exit(self: *TaskGroup) !void {
        self.exiting = true;

        // Wait for all tasks to complete
        for (self.tasks_list.items) |task| {
            while (!task.isDead()) {
                std.Thread.sleep(1_000);
            }
        }

        // If there were errors, propagate as ExceptionGroup
        if (self.errors.items.len > 0) {
            return error.ExceptionGroup;
        }
    }

    /// Create a task in this group
    pub fn createTask(self: *TaskGroup, func: tasks.TaskFn, context: *anyopaque) !*tasks.Task {
        if (!self.entered) {
            return error.NotEntered;
        }
        if (self.exiting) {
            return error.AlreadyExiting;
        }

        const task = try self.allocator.create(tasks.Task);
        task.* = tasks.Task.init(self.tasks_list.items.len + 1, func, context);
        try self.tasks_list.append(self.allocator, task);

        return task;
    }

    /// Cancel all running tasks
    fn cancelAll(self: *TaskGroup) void {
        self.aborting = true;
        for (self.tasks_list.items) |task| {
            task.markPreempted();
        }
    }

    /// Record an error from a task
    fn recordError(self: *TaskGroup, err: anyerror) !void {
        try self.errors.append(self.allocator, err);
        // Cancel other tasks on first error
        self.cancelAll();
    }
};

// Tests
test "TaskGroup lifecycle" {
    const allocator = std.testing.allocator;

    var tg = TaskGroup.init(allocator);
    defer tg.deinit();

    try std.testing.expect(!tg.entered);

    _ = try tg.enter();
    try std.testing.expect(tg.entered);
    try std.testing.expect(!tg.exiting);
}
