//! test.test_asyncio.test_taskgroups - Tests for asyncio TaskGroup
//! Reference: cpython/Lib/test/test_asyncio/test_taskgroups.py
//!
//! Tests for TaskGroup structured concurrency (Python 3.11+)

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");
const test_tasks = @import("test_tasks.zig");

// ============================================================================
// TaskGroup Implementation
// ============================================================================

/// A TaskGroup for structured concurrency
pub const TaskGroup = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _loop: *test_events.EventLoop,
    _tasks: std.ArrayList(*test_tasks.Task),
    _errors: std.ArrayList(TaskError),
    _base_error: ?anyerror = null,
    _entered: bool = false,
    _exited: bool = false,
    _aborting: bool = false,

    pub const TaskError = struct {
        task: *test_tasks.Task,
        err: anyerror,
    };

    pub fn init(allocator: std.mem.Allocator, loop: *test_events.EventLoop) Self {
        return .{
            .allocator = allocator,
            ._loop = loop,
            ._tasks = std.ArrayList(*test_tasks.Task).init(allocator),
            ._errors = std.ArrayList(TaskError).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self._tasks.items) |task| {
            task.deinit();
            self.allocator.destroy(task);
        }
        self._tasks.deinit();
        self._errors.deinit();
    }

    /// Enter the task group (async context manager __aenter__)
    pub fn enter(self: *Self) !void {
        if (self._entered) {
            return error.AlreadyEntered;
        }
        self._entered = true;
    }

    /// Create a task within the group
    pub fn create_task(self: *Self) !*test_tasks.Task {
        if (!self._entered) {
            return error.NotEntered;
        }
        if (self._aborting) {
            return error.Aborting;
        }

        const task = try self.allocator.create(test_tasks.Task);
        task.* = test_tasks.Task.init(self.allocator, self._loop);
        try self._tasks.append(task);
        return task;
    }

    /// Exit the task group (async context manager __aexit__)
    pub fn exit(self: *Self, propagate_cancellation: bool) !void {
        if (!self._entered) {
            return error.NotEntered;
        }
        if (self._exited) {
            return;
        }

        self._exited = true;

        // Wait for all tasks to complete
        for (self._tasks.items) |task| {
            if (!task.done()) {
                // In real implementation, would await task
                if (propagate_cancellation) {
                    _ = task.cancel(null);
                }
            }

            // Collect any exceptions
            if (task.exception()) |exc| {
                try self._errors.append(.{
                    .task = task,
                    .err = exc,
                });
            }
        }

        // Raise ExceptionGroup if there were errors
        if (self._errors.items.len > 0) {
            return error.ExceptionGroup;
        }
    }

    /// Abort the task group
    pub fn abort(self: *Self) void {
        self._aborting = true;
        for (self._tasks.items) |task| {
            if (!task.done()) {
                _ = task.cancel("TaskGroup aborting");
            }
        }
    }

    /// Get the number of tasks
    pub fn task_count(self: *const Self) usize {
        return self._tasks.items.len;
    }

    /// Check if any tasks are still pending
    pub fn has_pending(self: *const Self) bool {
        for (self._tasks.items) |task| {
            if (!task.done()) {
                return true;
            }
        }
        return false;
    }
};

// ============================================================================
// ExceptionGroup
// ============================================================================

/// An exception group containing multiple exceptions
pub const ExceptionGroup = struct {
    const Self = @This();

    message: []const u8,
    exceptions: std.ArrayList(anyerror),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, message: []const u8) Self {
        return .{
            .allocator = allocator,
            .message = message,
            .exceptions = std.ArrayList(anyerror).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.exceptions.deinit();
    }

    pub fn add(self: *Self, exc: anyerror) !void {
        try self.exceptions.append(exc);
    }

    pub fn count(self: *const Self) usize {
        return self.exceptions.items.len;
    }

    pub fn subgroup(self: *Self, filter: *const fn (anyerror) bool) !ExceptionGroup {
        var sub = ExceptionGroup.init(self.allocator, self.message);
        for (self.exceptions.items) |exc| {
            if (filter(exc)) {
                try sub.add(exc);
            }
        }
        return sub;
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testTaskGroupCreate() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    try std.testing.expect(!tg._entered);
    try std.testing.expect(!tg._exited);
}

fn testTaskGroupEnter() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    try tg.enter();
    try std.testing.expect(tg._entered);
}

fn testTaskGroupDoubleEnter() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    try tg.enter();
    const err = tg.enter();
    try std.testing.expectError(error.AlreadyEntered, err);
}

fn testTaskGroupCreateTask() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    try tg.enter();
    const task = try tg.create_task();

    try std.testing.expect(task != undefined);
    try std.testing.expectEqual(@as(usize, 1), tg.task_count());
}

fn testTaskGroupCreateTaskBeforeEnter() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    const err = tg.create_task();
    try std.testing.expectError(error.NotEntered, err);
}

fn testTaskGroupExit() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    try tg.enter();
    const task = try tg.create_task();
    try task.set_result(null);

    try tg.exit(false);
    try std.testing.expect(tg._exited);
}

fn testTaskGroupExitWithException() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    try tg.enter();
    const task = try tg.create_task();
    try task.set_exception(error.TestError);

    const err = tg.exit(false);
    try std.testing.expectError(error.ExceptionGroup, err);
}

fn testTaskGroupAbort() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    try tg.enter();
    _ = try tg.create_task();

    tg.abort();
    try std.testing.expect(tg._aborting);
}

fn testTaskGroupHasPending() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    try tg.enter();
    const task = try tg.create_task();

    try std.testing.expect(tg.has_pending());

    try task.set_result(null);
    try std.testing.expect(!tg.has_pending());
}

fn testExceptionGroup() !void {
    const allocator = std.testing.allocator;
    var eg = ExceptionGroup.init(allocator, "unhandled errors");
    defer eg.deinit();

    try eg.add(error.Error1);
    try eg.add(error.Error2);

    try std.testing.expectEqual(@as(usize, 2), eg.count());
}

fn testExceptionGroupSubgroup() !void {
    const allocator = std.testing.allocator;
    var eg = ExceptionGroup.init(allocator, "unhandled errors");
    defer eg.deinit();

    try eg.add(error.Error1);
    try eg.add(error.Error2);
    try eg.add(error.Error1);

    const filter = struct {
        fn f(e: anyerror) bool {
            return e == error.Error1;
        }
    }.f;

    var sub = try eg.subgroup(filter);
    defer sub.deinit();

    try std.testing.expectEqual(@as(usize, 2), sub.count());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "TaskGroup create" {
    try testTaskGroupCreate();
}

test "TaskGroup enter" {
    try testTaskGroupEnter();
}

test "TaskGroup double enter" {
    try testTaskGroupDoubleEnter();
}

test "TaskGroup create_task" {
    try testTaskGroupCreateTask();
}

test "TaskGroup create_task before enter" {
    try testTaskGroupCreateTaskBeforeEnter();
}

test "TaskGroup exit" {
    try testTaskGroupExit();
}

test "TaskGroup exit with exception" {
    try testTaskGroupExitWithException();
}

test "TaskGroup abort" {
    try testTaskGroupAbort();
}

test "TaskGroup has_pending" {
    try testTaskGroupHasPending();
}

test "ExceptionGroup" {
    try testExceptionGroup();
}

test "ExceptionGroup subgroup" {
    try testExceptionGroupSubgroup();
}

// Error types for testing
const TestError = error{ TestError, Error1, Error2 };
