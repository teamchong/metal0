//! asyncio.base_tasks - Task helper functions
//! Reference: cpython/Lib/asyncio/base_tasks.py

const std = @import("std");
const tasks = @import("tasks.zig");

/// Get task representation info
/// CPython: _task_repr_info(task)
pub fn taskReprInfo(task: *tasks.Task) []const u8 {
    return switch (task.state) {
        .idle => "pending",
        .runnable => "pending",
        .running => "running",
        .waiting => "waiting",
        .dead => "done",
    };
}

/// Get task stack trace (simplified)
/// CPython: _task_get_stack(task, limit)
pub fn taskGetStack(task: *tasks.Task, limit: ?usize) ![]const []const u8 {
    _ = task;
    _ = limit;
    // In Zig, we don't have Python stack traces
    // Return empty slice
    return &[_][]const u8{};
}

/// Print task stack trace
/// CPython: _task_print_stack(task, limit, file)
pub fn taskPrintStack(task: *tasks.Task, limit: ?usize, writer: anytype) !void {
    const stack = try taskGetStack(task, limit);

    if (stack.len == 0) {
        try writer.print("No stack for task {d} (state: {s})\n", .{ task.id, taskReprInfo(task) });
        return;
    }

    for (stack) |frame| {
        try writer.print("  {s}\n", .{frame});
    }
}

/// Format task for debugging
pub fn formatTask(task: *tasks.Task) []const u8 {
    return taskReprInfo(task);
}

// Tests
test "taskReprInfo" {
    const callback = struct {
        fn cb(_: *anyopaque) anyerror!void {}
    }.cb;

    var dummy: i64 = 0;
    var task = tasks.Task.init(1, callback, @ptrCast(&dummy));

    try std.testing.expectEqualStrings("pending", taskReprInfo(&task));

    task.makeRunning();
    try std.testing.expectEqualStrings("running", taskReprInfo(&task));

    task.makeDead();
    try std.testing.expectEqualStrings("done", taskReprInfo(&task));
}
