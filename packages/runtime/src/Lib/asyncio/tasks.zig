//! asyncio.tasks - Task class and utilities
//! Reference: cpython/Lib/asyncio/tasks.py
//!
//! CPython __all__:
//!   ('Task', 'create_task', 'FIRST_COMPLETED', 'FIRST_EXCEPTION', 'ALL_COMPLETED',
//!    'wait', 'wait_for', 'as_completed', 'sleep', 'gather', 'shield',
//!    'ensure_future', 'run_coroutine_threadsafe', 'current_task', 'all_tasks',
//!    'create_eager_task_factory', 'eager_task_factory',
//!    '_register_task', '_unregister_task', '_enter_task', '_leave_task')

const std = @import("std");
const asyncio = @import("../asyncio.zig");
const futures = @import("futures.zig");
const exceptions = @import("exceptions.zig");

// Re-export Task types from main asyncio module (DRY)
pub const Task = asyncio.Task;
pub const TaskState = asyncio.TaskState;

// Re-export Future for type compatibility
pub const Future = asyncio.Future;

// Wait return_when constants (match CPython)
pub const FIRST_COMPLETED = asyncio.FIRST_COMPLETED;
pub const FIRST_EXCEPTION = asyncio.FIRST_EXCEPTION;
pub const ALL_COMPLETED = asyncio.ALL_COMPLETED;

/// Create a task wrapping a coroutine
/// CPython signature: create_task(coro, *, name=None, context=None)
pub const createTask = asyncio.createTask;

/// Get the currently running task
/// CPython signature: current_task(loop=None)
pub fn currentTask() ?*Task {
    // Would need per-thread tracking
    return null;
}

/// Get all tasks for the loop
/// CPython signature: all_tasks(loop=None)
pub fn allTasks(allocator: std.mem.Allocator) ![]const *Task {
    _ = allocator;
    return &[_]*Task{};
}

/// Sleep for specified seconds
/// CPython signature: sleep(delay, result=None)
pub const sleep = asyncio.sleep;

/// Wrap a coroutine or future into a Future
/// CPython signature: ensure_future(coro_or_future, *, loop=None)
pub const ensureFuture = futures.ensureFuture;

/// Wait for futures with timeout and return_when options
/// CPython signature: wait(fs, *, timeout=None, return_when=ALL_COMPLETED)
pub fn wait(
    allocator: std.mem.Allocator,
    tasks: []*Task,
    timeout_seconds: ?f64,
    return_when: i32,
) !struct { done: []*Task, pending: []*Task } {
    const start = std.time.milliTimestamp();
    const timeout_ms: ?i64 = if (timeout_seconds) |t| @intFromFloat(t * 1000) else null;

    var done_list: std.ArrayList(*Task) = .{};
    var pending_list: std.ArrayList(*Task) = .{};

    for (tasks) |task| {
        if (timeout_ms) |tm| {
            const elapsed = std.time.milliTimestamp() - start;
            if (elapsed >= tm) {
                try pending_list.append(allocator, task);
                continue;
            }
        }

        if (task.done()) {
            try done_list.append(allocator, task);
            if (return_when == FIRST_COMPLETED) break;
        } else {
            try pending_list.append(allocator, task);
        }
    }

    return .{
        .done = try done_list.toOwnedSlice(allocator),
        .pending = try pending_list.toOwnedSlice(allocator),
    };
}

/// Wait for a future with timeout
/// CPython signature: wait_for(fut, timeout)
pub fn waitFor(
    comptime T: type,
    future: *Future(T),
    timeout_seconds: f64,
) !T {
    const start = std.time.milliTimestamp();
    const timeout_ms: i64 = @intFromFloat(timeout_seconds * 1000);

    while (!future.done()) {
        const elapsed = std.time.milliTimestamp() - start;
        if (elapsed >= timeout_ms) {
            return exceptions.TimeoutError;
        }
        std.Thread.sleep(1_000); // 1µs
    }

    return future.getResult();
}

/// Shield a future from cancellation
/// CPython signature: shield(arg)
pub fn shield(comptime T: type, allocator: std.mem.Allocator, inner: *Future(T)) !*Future(T) {
    const outer = try Future(T).init(allocator);
    if (inner.tryGet()) |val| {
        outer.setResult(val);
    }
    return outer;
}

/// Run coroutine in a thread-safe manner from another thread
/// CPython signature: run_coroutine_threadsafe(coro, loop)
pub fn runCoroutineThreadsafe(
    allocator: std.mem.Allocator,
    comptime T: type,
    comptime coro: fn () anyerror!T,
) !*Future(T) {
    const future = try Future(T).init(allocator);
    const thread = try std.Thread.spawn(.{}, struct {
        fn threadFn(fut: *Future(T)) void {
            const result = coro() catch |err| {
                fut.setException(err);
                return;
            };
            fut.setResult(result);
        }
    }.threadFn, .{future});
    thread.detach();
    return future;
}

/// Internal: Register task
pub fn registerTask(task: *Task) void {
    _ = task;
}

/// Internal: Unregister task
pub fn unregisterTask(task: *Task) void {
    _ = task;
}

/// Internal: Enter task context
pub fn enterTask(task: *Task) void {
    task.state = .running;
}

/// Internal: Leave task context
pub fn leaveTask(task: *Task) void {
    _ = task;
}

// Tests
test "Task state constants" {
    try std.testing.expectEqual(@as(i32, 0), FIRST_COMPLETED);
    try std.testing.expectEqual(@as(i32, 1), FIRST_EXCEPTION);
    try std.testing.expectEqual(@as(i32, 2), ALL_COMPLETED);
}

test "Task creation" {
    const callback = struct {
        fn cb(_: *anyopaque) anyerror!void {}
    }.cb;

    var dummy: i64 = 0;
    const task = Task.init(1, callback, @ptrCast(&dummy));

    try std.testing.expectEqual(@as(usize, 1), task.id);
    try std.testing.expectEqual(TaskState.pending, task.state);
}
