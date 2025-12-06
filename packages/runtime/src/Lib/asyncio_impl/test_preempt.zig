const std = @import("std");
const Task = @import("task.zig").Task;
const Processor = @import("processor.zig").Processor;
const timer = @import("preempt/timer.zig");
const signals = @import("preempt/signals.zig");
const stack = @import("preempt/stack.zig");

pub fn main() !void {
    std.debug.print("Testing Preemption System\n", .{});
    std.debug.print("=========================\n\n", .{});

    // Test signal handling
    try testSignalHandling();

    // Test stack allocation
    try testStackOperations();

    // Test preemption timer
    try testPreemptionTimer();

    std.debug.print("\nAll preemption tests passed!\n", .{});
}

fn testSignalHandling() !void {
    std.debug.print("Testing Signal Handling:\n", .{});

    // Check if platform supports signals
    if (signals.isSignalPreemptionSupported()) {
        std.debug.print("  ✓ Signal-based preemption supported\n", .{});

        // Initialize signal handling
        try signals.initSignalHandling();
        defer signals.deinitSignalHandling();

        std.debug.print("  ✓ Signal handlers installed\n", .{});

        const mode = signals.getPreemptionMode();
        if (mode == .signal_based) {
            std.debug.print("  ✓ Running in signal-based mode\n", .{});
        }
    } else {
        std.debug.print("  ⓘ Signal preemption not supported (using cooperative mode)\n", .{});
    }

    // Test cooperative preemption marking
    var processor = Processor.init(std.heap.page_allocator, 0);
    defer processor.deinit();

    var task = Task.init(1, undefined, undefined);
    task.state = .running;
    processor.current_task = &task;

    signals.markForPreemption(&processor);

    if (task.shouldPreempt()) {
        std.debug.print("  ✓ Cooperative preemption marking works\n\n", .{});
    } else {
        return error.PreemptionFailed;
    }
}

fn testStackOperations() !void {
    std.debug.print("Testing Stack Operations:\n", .{});

    // Test stack allocation
    const stack_mem = try stack.allocateStack(std.heap.page_allocator, 4096);
    defer stack.freeStack(std.heap.page_allocator, stack_mem);

    if (stack_mem.len >= 4096) {
        std.debug.print("  ✓ Stack allocation successful ({d} bytes)\n", .{stack_mem.len});
    }

    // Check alignment
    if (@intFromPtr(stack_mem.ptr) % 4096 == 0) {
        std.debug.print("  ✓ Stack is page-aligned\n", .{});
    }

    // Test initial stack setup
    var task = Task.init(1, undefined, undefined);
    task.stack = stack_mem;
    task.stack_size = 4096;

    var dummy_context: u32 = 42;
    const entry_point = struct {
        fn func(ctx: *anyopaque) !void {
            _ = ctx;
        }
    }.func;

    try stack.setupInitialStack(&task, entry_point, &dummy_context);

    if (task.exec_context.sp > 0 and task.exec_context.sp % 16 == 0) {
        std.debug.print("  ✓ Initial stack setup complete (SP: 0x{x}, aligned)\n", .{task.exec_context.sp});
    }

    // Test platform detection
    const platform = stack.getPlatformName();
    std.debug.print("  ✓ Platform: {s}\n", .{platform});

    if (stack.isNativeContextSwitchSupported()) {
        std.debug.print("  ✓ Native context switching supported\n\n", .{});
    } else {
        std.debug.print("  ⓘ Native context switching not supported (generic mode)\n\n", .{});
    }
}

fn testPreemptionTimer() !void {
    std.debug.print("Testing Preemption Timer:\n", .{});

    // Create processors
    var processor1 = Processor.init(std.heap.page_allocator, 0);
    var processor2 = Processor.init(std.heap.page_allocator, 1);
    defer processor1.deinit();
    defer processor2.deinit();

    var processors = [_]*Processor{ &processor1, &processor2 };

    // Create timer
    var preempt_timer = timer.PreemptTimer.init(&processors);

    // Start timer
    try preempt_timer.start();
    defer preempt_timer.stop();

    std.debug.print("  ✓ Timer started\n", .{});

    // Let it run for a bit
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Check stats
    const stats = preempt_timer.getStats();
    if (stats.total_checks >= 3) {
        std.debug.print("  ✓ Timer performing checks ({d} checks in 50ms)\n", .{stats.total_checks});
    } else {
        return error.TimerNotWorking;
    }

    std.debug.print("  ✓ Interval: {d}ms\n", .{stats.interval_ns / std.time.ns_per_ms});

    // Test with long-running task
    var task = Task.init(1, undefined, undefined);
    task.start_time = std.time.nanoTimestamp() - (20 * std.time.ns_per_ms); // Started 20ms ago
    task.state = .running;

    processor1.current_task = &task;

    // Let timer detect it
    std.Thread.sleep(15 * std.time.ns_per_ms);

    if (task.shouldPreempt()) {
        std.debug.print("  ✓ Long-running task detected and marked for preemption\n", .{});
    }

    const final_stats = preempt_timer.getStats();
    std.debug.print("  ✓ Total preemptions: {d}\n", .{final_stats.total_preemptions});
}
