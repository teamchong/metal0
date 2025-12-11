/// Queue benchmark using Zig 0.15 compatible APIs
const std = @import("std");
const lockfree = @import("lockfree.zig");
const Task = @import("task.zig").Task;

/// Benchmark queue performance
pub fn main() !void {
    const allocator = allocator_helper.fast_allocator;
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.io.getStdOut().writer();
    var buffered = std.io.bufferedWriter(stdout);
    var writer = buffered.writer();

    try writer.print("Queue Benchmark\n", .{});
    try writer.print("===============\n\n", .{});

    // Single-threaded push/pop benchmark
    {
        const Queue = lockfree.LockFreeQueue(*Task);
        var queue = Queue.init(allocator);
        defer queue.deinit();

        const iterations: usize = 100_000;
        var timer = try std.time.Timer.start();

        // Push phase
        for (0..iterations) |_| {
            const task = allocator.create(Task) catch continue;
            queue.push(task);
        }

        const push_elapsed = timer.lap();

        // Pop phase
        var pop_count: usize = 0;
        while (queue.pop()) |task| {
            allocator.destroy(task);
            pop_count += 1;
        }

        const pop_elapsed = timer.read();

        try writer.print("Single-threaded ({d} iterations):\n", .{iterations});
        try writer.print("  Push: {d:.2}ms ({d:.0} ops/sec)\n", .{
            @as(f64, @floatFromInt(push_elapsed)) / std.time.ns_per_ms,
            @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(push_elapsed)) / std.time.ns_per_s),
        });
        try writer.print("  Pop:  {d:.2}ms ({d:.0} ops/sec)\n", .{
            @as(f64, @floatFromInt(pop_elapsed)) / std.time.ns_per_ms,
            @as(f64, @floatFromInt(pop_count)) / (@as(f64, @floatFromInt(pop_elapsed)) / std.time.ns_per_s),
        });
        try writer.print("\n", .{});

        _ = stdout_buf;
    }

    try buffered.flush();
}
