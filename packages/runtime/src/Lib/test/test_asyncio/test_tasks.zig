//! test.test_asyncio.test_tasks - Tests for asyncio Task class
//! Reference: cpython/Lib/test/test_asyncio/test_tasks.py
//!
//! Tests for Task creation, cancellation, and coroutine scheduling

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Task Implementation
// ============================================================================

/// Task state
pub const TaskState = enum {
    pending,
    running,
    done,
    cancelled,
};

/// A Task wraps a coroutine and schedules it on an event loop
pub const Task = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _loop: *test_events.EventLoop,
    _state: TaskState = .pending,
    _result: ?*anyopaque = null,
    _exception: ?anyerror = null,
    _callbacks: std.ArrayList(*const fn (*Self) void),
    _name: ?[]const u8 = null,
    _cancel_message: ?[]const u8 = null,
    _must_cancel: bool = false,

    pub fn init(allocator: std.mem.Allocator, loop: *test_events.EventLoop) Self {
        return .{
            .allocator = allocator,
            ._loop = loop,
            ._callbacks = std.ArrayList(*const fn (*Self) void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._callbacks.deinit();
    }

    pub fn done(self: *const Self) bool {
        return self._state == .done or self._state == .cancelled;
    }

    pub fn cancelled(self: *const Self) bool {
        return self._state == .cancelled;
    }

    pub fn result(self: *const Self) !?*anyopaque {
        if (self._state == .cancelled) {
            return error.CancelledError;
        }
        if (!self.done()) {
            return error.InvalidStateError;
        }
        if (self._exception) |exc| {
            return exc;
        }
        return self._result;
    }

    pub fn exception(self: *const Self) ?anyerror {
        if (self._state == .cancelled) {
            return error.CancelledError;
        }
        return self._exception;
    }

    pub fn cancel(self: *Self, msg: ?[]const u8) bool {
        if (self.done()) {
            return false;
        }
        self._cancel_message = msg;
        self._must_cancel = true;
        return true;
    }

    pub fn cancelling(self: *const Self) bool {
        return self._must_cancel;
    }

    pub fn uncancel(self: *Self) bool {
        if (!self._must_cancel) {
            return false;
        }
        self._must_cancel = false;
        self._cancel_message = null;
        return true;
    }

    pub fn get_name(self: *const Self) ?[]const u8 {
        return self._name;
    }

    pub fn set_name(self: *Self, name: []const u8) void {
        self._name = name;
    }

    pub fn get_loop(self: *const Self) *test_events.EventLoop {
        return self._loop;
    }

    pub fn add_done_callback(self: *Self, callback: *const fn (*Self) void) !void {
        if (self.done()) {
            callback(self);
        } else {
            try self._callbacks.append(callback);
        }
    }

    pub fn remove_done_callback(self: *Self, callback: *const fn (*Self) void) usize {
        var removed: usize = 0;
        var i: usize = 0;
        while (i < self._callbacks.items.len) {
            if (self._callbacks.items[i] == callback) {
                _ = self._callbacks.orderedRemove(i);
                removed += 1;
            } else {
                i += 1;
            }
        }
        return removed;
    }

    fn schedule_callbacks(self: *Self) void {
        for (self._callbacks.items) |callback| {
            callback(self);
        }
        self._callbacks.clearRetainingCapacity();
    }

    /// Complete the task with a result
    pub fn set_result(self: *Self, res: ?*anyopaque) !void {
        if (self.done()) {
            return error.InvalidStateError;
        }
        self._result = res;
        self._state = .done;
        self.schedule_callbacks();
    }

    /// Complete the task with an exception
    pub fn set_exception(self: *Self, exc: anyerror) !void {
        if (self.done()) {
            return error.InvalidStateError;
        }
        self._exception = exc;
        self._state = .done;
        self.schedule_callbacks();
    }

    /// Mark task as cancelled
    pub fn mark_cancelled(self: *Self) void {
        self._state = .cancelled;
        self.schedule_callbacks();
    }
};

// ============================================================================
// Task Creation Functions
// ============================================================================

/// Create a new task
pub fn create_task(allocator: std.mem.Allocator, loop: *test_events.EventLoop) Task {
    return Task.init(allocator, loop);
}

/// Get the current task (mock for testing)
pub fn current_task(_: *test_events.EventLoop) ?*Task {
    return null;
}

/// Get all tasks (mock for testing)
pub fn all_tasks(_: *test_events.EventLoop) []const *Task {
    return &[_]*Task{};
}

// ============================================================================
// Task Group Implementation
// ============================================================================

/// A TaskGroup for structured concurrency
pub const TaskGroup = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _loop: *test_events.EventLoop,
    _tasks: std.ArrayList(*Task),
    _errors: std.ArrayList(anyerror),
    _entered: bool = false,
    _exiting: bool = false,

    pub fn init(allocator: std.mem.Allocator, loop: *test_events.EventLoop) Self {
        return .{
            .allocator = allocator,
            ._loop = loop,
            ._tasks = std.ArrayList(*Task).init(allocator),
            ._errors = std.ArrayList(anyerror).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._tasks.deinit();
        self._errors.deinit();
    }

    pub fn create_task(self: *Self) !*Task {
        const task = try self.allocator.create(Task);
        task.* = Task.init(self.allocator, self._loop);
        try self._tasks.append(task);
        return task;
    }

    /// Enter the task group context
    pub fn enter(self: *Self) void {
        self._entered = true;
    }

    /// Exit the task group, waiting for all tasks
    pub fn exit(self: *Self) !void {
        self._exiting = true;

        // Cancel all tasks if there were errors
        if (self._errors.items.len > 0) {
            for (self._tasks.items) |task| {
                if (!task.done()) {
                    _ = task.cancel(null);
                }
            }
        }

        // Wait for all tasks
        for (self._tasks.items) |task| {
            while (!task.done()) {
                std.atomic.spinLoopHint();
            }
        }

        if (self._errors.items.len > 0) {
            return error.ExceptionGroup;
        }
    }
};

// ============================================================================
// Wait Functions
// ============================================================================

pub const WaitMode = enum {
    FIRST_COMPLETED,
    FIRST_EXCEPTION,
    ALL_COMPLETED,
};

/// Wait for tasks based on mode
pub fn wait(
    allocator: std.mem.Allocator,
    tasks: []*Task,
    mode: WaitMode,
) !struct { done: std.ArrayList(*Task), pending: std.ArrayList(*Task) } {
    var done_list = std.ArrayList(*Task).init(allocator);
    var pending_list = std.ArrayList(*Task).init(allocator);

    for (tasks) |task| {
        if (task.done()) {
            try done_list.append(task);
        } else {
            try pending_list.append(task);
        }
    }

    switch (mode) {
        .FIRST_COMPLETED => {
            if (done_list.items.len > 0) {
                return .{ .done = done_list, .pending = pending_list };
            }
        },
        .FIRST_EXCEPTION => {
            for (done_list.items) |task| {
                if (task.exception() != null) {
                    return .{ .done = done_list, .pending = pending_list };
                }
            }
        },
        .ALL_COMPLETED => {
            // Return when all are done
        },
    }

    return .{ .done = done_list, .pending = pending_list };
}

// ============================================================================
// Test Cases
// ============================================================================

fn testTaskCreate() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = Task.init(allocator, &loop);
    defer task.deinit();

    try std.testing.expect(!task.done());
    try std.testing.expect(!task.cancelled());
    try std.testing.expectEqual(&loop, task.get_loop());
}

fn testTaskSetResult() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = Task.init(allocator, &loop);
    defer task.deinit();

    try task.set_result(null);
    try std.testing.expect(task.done());
    try std.testing.expect(!task.cancelled());
}

fn testTaskCancel() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = Task.init(allocator, &loop);
    defer task.deinit();

    try std.testing.expect(task.cancel(null));
    try std.testing.expect(task.cancelling());

    task.mark_cancelled();
    try std.testing.expect(task.cancelled());
    try std.testing.expect(task.done());
}

fn testTaskUncancel() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = Task.init(allocator, &loop);
    defer task.deinit();

    try std.testing.expect(task.cancel("test"));
    try std.testing.expect(task.cancelling());
    try std.testing.expect(task.uncancel());
    try std.testing.expect(!task.cancelling());
}

fn testTaskName() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = Task.init(allocator, &loop);
    defer task.deinit();

    try std.testing.expect(task.get_name() == null);
    task.set_name("my_task");
    try std.testing.expectEqualStrings("my_task", task.get_name().?);
}

fn testTaskCallback() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = Task.init(allocator, &loop);
    defer task.deinit();

    const callback = struct {
        fn cb(_: *Task) void {}
    }.cb;

    try task.add_done_callback(callback);
    try std.testing.expectEqual(@as(usize, 1), task._callbacks.items.len);

    const removed = task.remove_done_callback(callback);
    try std.testing.expectEqual(@as(usize, 1), removed);
    try std.testing.expectEqual(@as(usize, 0), task._callbacks.items.len);
}

fn testTaskSetException() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task = Task.init(allocator, &loop);
    defer task.deinit();

    try task.set_exception(error.TestError);
    try std.testing.expect(task.done());
    try std.testing.expectEqual(@as(?anyerror, error.TestError), task.exception());
}

fn testTaskGroupBasic() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var tg = TaskGroup.init(allocator, &loop);
    defer tg.deinit();

    tg.enter();
    const task = try tg.create_task();
    try task.set_result(null);

    try tg.exit();
}

fn testWaitMode() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var task1 = Task.init(allocator, &loop);
    defer task1.deinit();
    var task2 = Task.init(allocator, &loop);
    defer task2.deinit();

    try task1.set_result(null);

    var tasks = [_]*Task{ &task1, &task2 };
    var result = try wait(allocator, &tasks, .FIRST_COMPLETED);
    defer result.done.deinit();
    defer result.pending.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.done.items.len);
    try std.testing.expectEqual(@as(usize, 1), result.pending.items.len);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "Task create" {
    try testTaskCreate();
}

test "Task set_result" {
    try testTaskSetResult();
}

test "Task cancel" {
    try testTaskCancel();
}

test "Task uncancel" {
    try testTaskUncancel();
}

test "Task name" {
    try testTaskName();
}

test "Task callback" {
    try testTaskCallback();
}

test "Task set_exception" {
    try testTaskSetException();
}

test "TaskGroup basic" {
    try testTaskGroupBasic();
}

test "wait mode" {
    try testWaitMode();
}

// Test error type
const TestError = error{TestError};
