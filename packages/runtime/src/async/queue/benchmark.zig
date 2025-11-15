const std = @import("std");
const lockfree = @import("lockfree.zig");
const Task = @import("../task.zig").Task;

/// Benchmark queue performance
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Lock-Free Queue Performance Benchmark\n", .{});
    try stdout.print("======================================\n\n", .{});

    // Benchmark push/pop
    try benchmarkPushPop(stdout);

    // Benchmark steal
    try benchmarkSteal(stdout);

    // Benchmark mixed operations
    try benchmarkMixed(stdout);
}

fn benchmarkPushPop(writer: anytype) !void {
    const iterations: usize = 1_000_000;

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

    // Benchmark push
    const push_start = std.time.nanoTimestamp();
    for (0..iterations) |i| {
        _ = queue.push(&tasks[i % 256]);
        _ = queue.pop(); // Keep queue from filling
    }
    const push_end = std.time.nanoTimestamp();

    const push_ns = @divTrunc(push_end - push_start, iterations);

    try writer.print("Push/Pop Performance:\n", .{});
    try writer.print("  Operations: {d}\n", .{iterations});
    try writer.print("  Time per op: {d} ns\n", .{push_ns});
    try writer.print("  Target: <50 ns\n", .{});
    try writer.print("  Status: {s}\n\n", .{if (push_ns < 50) "PASS" else "FAIL"});
}

fn benchmarkSteal(writer: anytype) !void {
    const iterations: usize = 1_000_000;

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
    const steal_start = std.time.nanoTimestamp();
    for (0..iterations) |i| {
        _ = queue.steal();
        _ = queue.push(&tasks[i % 256]); // Refill
    }
    const steal_end = std.time.nanoTimestamp();

    const steal_ns = @divTrunc(steal_end - steal_start, iterations);

    try writer.print("Steal Performance:\n", .{});
    try writer.print("  Operations: {d}\n", .{iterations});
    try writer.print("  Time per op: {d} ns\n", .{steal_ns});
    try writer.print("  Target: <100 ns\n", .{});
    try writer.print("  Status: {s}\n\n", .{if (steal_ns < 100) "PASS" else "FAIL"});
}

fn benchmarkMixed(writer: anytype) !void {
    const iterations: usize = 1_000_000;

    var queue = lockfree.Queue(256).init();

    var tasks: [256]Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = Task.init(i, undefined, undefined);
    }

    // Mixed operations
    const mixed_start = std.time.nanoTimestamp();
    for (0..iterations) |i| {
        if (i % 3 == 0) {
            _ = queue.push(&tasks[i % 256]);
        } else if (i % 3 == 1) {
            _ = queue.pop();
        } else {
            _ = queue.steal();
        }
    }
    const mixed_end = std.time.nanoTimestamp();

    const mixed_ns = @divTrunc(mixed_end - mixed_start, iterations);

    try writer.print("Mixed Operations Performance:\n", .{});
    try writer.print("  Operations: {d}\n", .{iterations});
    try writer.print("  Time per op: {d} ns\n", .{mixed_ns});
    try writer.print("  Target: <75 ns\n", .{});
    try writer.print("  Status: {s}\n\n", .{if (mixed_ns < 75) "PASS" else "FAIL"});
}
