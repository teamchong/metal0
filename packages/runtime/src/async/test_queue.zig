const std = @import("std");
const Task = @import("task.zig").Task;
const lockfree = @import("queue/lockfree.zig");
const local = @import("queue/local.zig");
const global = @import("queue/global.zig");

pub fn main() !void {
    const stdout = std.debug;

    stdout.print("Testing Lock-Free Queue Implementation\n", .{});
    stdout.print("=======================================\n\n", .{});

    // Test lockfree queue
    try testLockFreeQueue();

    // Test local queue
    try testLocalQueue();

    // Test global queue
    try testGlobalQueue();

    stdout.print("\nAll tests passed!\n", .{});
}

fn testLockFreeQueue() !void {
    std.debug.print("Testing Lock-Free Queue:\n", .{});

    var queue = lockfree.Queue(8).init();

    // Create tasks
    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);
    var task3 = Task.init(3, undefined, undefined);

    // Test push
    if (!queue.push(&task1)) return error.PushFailed;
    if (!queue.push(&task2)) return error.PushFailed;
    if (!queue.push(&task3)) return error.PushFailed;

    if (queue.size() != 3) return error.WrongSize;
    std.debug.print("  ✓ Push operations work\n", .{});

    // Test pop
    const t1 = queue.pop() orelse return error.PopFailed;
    if (t1.id != 1) return error.WrongOrder;

    const t2 = queue.pop() orelse return error.PopFailed;
    if (t2.id != 2) return error.WrongOrder;

    std.debug.print("  ✓ Pop operations work\n", .{});

    // Test steal
    const t3 = queue.steal() orelse return error.StealFailed;
    if (t3.id != 3) return error.WrongOrder;

    std.debug.print("  ✓ Steal operations work\n", .{});

    if (!queue.isEmpty()) return error.NotEmpty;
    std.debug.print("  ✓ Queue is empty after all operations\n\n", .{});
}

fn testLocalQueue() !void {
    std.debug.print("Testing Local Queue:\n", .{});

    var queue = local.LocalQueue.init(0);

    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);

    // Test push
    if (!queue.push(&task1)) return error.PushFailed;
    if (!queue.push(&task2)) return error.PushFailed;

    std.debug.print("  ✓ Push operations work\n", .{});

    // Test stats
    const stats = queue.getStats();
    if (stats.total_pushed != 2) return error.WrongStats;
    if (stats.current_size != 2) return error.WrongSize;

    std.debug.print("  ✓ Statistics tracking works\n", .{});

    // Test pop
    _ = queue.pop() orelse return error.PopFailed;

    // Test steal
    _ = queue.steal() orelse return error.StealFailed;

    if (!queue.isEmpty()) return error.NotEmpty;
    std.debug.print("  ✓ Queue is empty after operations\n\n", .{});
}

fn testGlobalQueue() !void {
    std.debug.print("Testing Global Queue:\n", .{});

    var queue = global.GlobalQueue.init();

    var task1 = Task.init(1, undefined, undefined);
    var task2 = Task.init(2, undefined, undefined);
    var task3 = Task.init(3, undefined, undefined);

    // Test push
    queue.push(&task1);
    queue.push(&task2);
    queue.push(&task3);

    std.debug.print("  ✓ Push operations work\n", .{});

    if (queue.size() != 3) return error.WrongSize;

    // Test pop
    const t1 = queue.pop() orelse return error.PopFailed;
    if (t1.id != 1) return error.WrongOrder;

    const t2 = queue.pop() orelse return error.PopFailed;
    if (t2.id != 2) return error.WrongOrder;

    std.debug.print("  ✓ Pop operations work (FIFO order)\n", .{});

    // Test batch push
    var tasks: [5]Task = undefined;
    var task_ptrs: [5]*Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = Task.init(i + 10, undefined, undefined);
        task_ptrs[i] = task;
    }

    queue.pushBatch(&task_ptrs);

    if (queue.size() != 6) return error.WrongSize; // 1 from before + 5 new

    std.debug.print("  ✓ Batch push works\n", .{});

    queue.clear();
    if (!queue.isEmpty()) return error.NotEmpty;

    std.debug.print("  ✓ Clear works\n\n", .{});
}
