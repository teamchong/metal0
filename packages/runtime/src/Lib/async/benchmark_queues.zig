const std = @import("std");
const Task = @import("task.zig").Task;
const lockfree = @import("queue/lockfree.zig");

pub fn main() !void {
    std.debug.print("Lock-Free Queue Performance Benchmark\n", .{});
    std.debug.print("======================================\n\n", .{});

    const iterations: usize = 1_000_000;

    // Benchmark push/pop
    try benchmarkPushPop(iterations);

    // Benchmark steal
    try benchmarkSteal(iterations);

    // Benchmark mixed operations
    try benchmarkMixed(iterations);
}

fn benchmarkPushPop(iterations: usize) !void {
    var queue = lockfree.Queue(256).init();

    // Create dummy tasks
    var tasks: [256]Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = Task.init(i, undefined, undefined);
    }

    // Warmup
    for (0..100) |i| {
        _ = queue.push(&tasks[i % 256]);
        _ = queue.pop();
    }

    // Benchmark push/pop
    const start = std.time.nanoTimestamp();
    for (0..iterations) |i| {
        _ = queue.push(&tasks[i % 256]);
        _ = queue.pop(); // Keep queue from filling
    }
    const end = std.time.nanoTimestamp();

    const ns_per_op = @divTrunc(end - start, iterations);

    std.debug.print("Push/Pop Performance:\n", .{});
    std.debug.print("  Operations: {d}\n", .{iterations});
    std.debug.print("  Time per op: {d} ns\n", .{ns_per_op});
    std.debug.print("  Target: <50 ns\n", .{});

    if (ns_per_op < 50) {
        std.debug.print("  Status: ✓ PASS\n\n", .{});
    } else {
        std.debug.print("  Status: ✗ FAIL (exceeded target)\n\n", .{});
    }
}

fn benchmarkSteal(iterations: usize) !void {
    var queue = lockfree.Queue(256).init();

    var tasks: [256]Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = Task.init(i, undefined, undefined);
    }

    // Fill queue
    for (&tasks) |*task| {
        _ = queue.push(task);
    }

    // Benchmark steal
    const start = std.time.nanoTimestamp();
    for (0..iterations) |i| {
        _ = queue.steal();
        _ = queue.push(&tasks[i % 256]); // Refill
    }
    const end = std.time.nanoTimestamp();

    const ns_per_op = @divTrunc(end - start, iterations);

    std.debug.print("Steal Performance:\n", .{});
    std.debug.print("  Operations: {d}\n", .{iterations});
    std.debug.print("  Time per op: {d} ns\n", .{ns_per_op});
    std.debug.print("  Target: <100 ns\n", .{});

    if (ns_per_op < 100) {
        std.debug.print("  Status: ✓ PASS\n\n", .{});
    } else {
        std.debug.print("  Status: ✗ FAIL (exceeded target)\n\n", .{});
    }
}

fn benchmarkMixed(iterations: usize) !void {
    var queue = lockfree.Queue(256).init();

    var tasks: [256]Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = Task.init(i, undefined, undefined);
    }

    // Mixed operations
    const start = std.time.nanoTimestamp();
    for (0..iterations) |i| {
        if (i % 3 == 0) {
            _ = queue.push(&tasks[i % 256]);
        } else if (i % 3 == 1) {
            _ = queue.pop();
        } else {
            _ = queue.steal();
        }
    }
    const end = std.time.nanoTimestamp();

    const ns_per_op = @divTrunc(end - start, iterations);

    std.debug.print("Mixed Operations Performance:\n", .{});
    std.debug.print("  Operations: {d}\n", .{iterations});
    std.debug.print("  Time per op: {d} ns\n", .{ns_per_op});
    std.debug.print("  Target: <75 ns\n", .{});

    if (ns_per_op < 75) {
        std.debug.print("  Status: ✓ PASS\n\n", .{});
    } else {
        std.debug.print("  Status: ✗ FAIL (exceeded target)\n\n", .{});
    }
}
