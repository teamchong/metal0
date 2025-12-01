/// Goroutine Fan-out/Fan-in Benchmark
///
/// This benchmark tests the performance of metal0's goroutine infrastructure:
/// - Spawns N worker goroutines using spawn0 (no context)
/// - Uses atomic counters for synchronization
///
/// Comparison target: CPython asyncio (bench_fanout.py)

const std = @import("std");
const Scheduler = @import("scheduler").Scheduler;
const GreenThread = @import("green_thread").GreenThread;

const NUM_TASKS: usize = 1000;
const WORK_PER_TASK: usize = 10000;

// Global state for workers (since spawn0 takes no context)
var g_results: []std.atomic.Value(i64) = undefined;
var g_completed: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var g_task_counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

fn worker() void {
    // Get task ID atomically
    const task_id = g_task_counter.fetchAdd(1, .acq_rel);

    // Do work
    var result: i64 = 0;
    for (0..WORK_PER_TASK) |i| {
        result += @as(i64, @intCast(i)) * @as(i64, @intCast(task_id));
    }

    // Store result
    if (task_id < g_results.len) {
        g_results[task_id].store(result, .release);
    }

    // Increment completion counter
    _ = g_completed.fetchAdd(1, .acq_rel);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize scheduler with auto CPU count
    var scheduler = try Scheduler.init(allocator, 0);
    defer scheduler.deinit();
    try scheduler.start();

    // Results storage
    g_results = try allocator.alloc(std.atomic.Value(i64), NUM_TASKS);
    defer allocator.free(g_results);
    for (g_results) |*r| {
        r.* = std.atomic.Value(i64).init(0);
    }

    // Reset counters
    g_completed = std.atomic.Value(usize).init(0);
    g_task_counter = std.atomic.Value(usize).init(0);

    const start = std.time.nanoTimestamp();

    // Spawn all worker goroutines
    for (0..NUM_TASKS) |_| {
        _ = try scheduler.spawn0(worker);
    }

    // Wait for all tasks to complete
    while (g_completed.load(.acquire) < NUM_TASKS) {
        std.Thread.yield() catch {};
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

    // Sum results
    var total: i64 = 0;
    for (g_results) |r| {
        total += r.load(.acquire);
    }

    const tasks_per_sec = @as(f64, @floatFromInt(NUM_TASKS)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

    std.debug.print("Tasks: {d}\n", .{NUM_TASKS});
    std.debug.print("Work per task: {d}\n", .{WORK_PER_TASK});
    std.debug.print("Total result: {d}\n", .{total});
    std.debug.print("Time: {d:.2}ms\n", .{elapsed_ms});
    std.debug.print("Tasks/sec: {d:.0}\n", .{tasks_per_sec});
}
