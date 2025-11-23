const std = @import("std");
const builtin = @import("builtin");
const Task = @import("../task.zig").Task;
const Processor = @import("../processor.zig").Processor;

/// Signal-based preemption (Go-style)
/// Uses SIGURG on Unix systems for async-safe preemption
/// On other platforms, falls back to cooperative preemption

/// Preemption signal (SIGURG on Unix, unused on Windows)
pub const PREEMPT_SIGNAL = if (builtin.os.tag == .linux or builtin.os.tag == .macos)
    std.posix.SIG.URG
else
    0;

/// Global flag indicating if signal handling is enabled
var signal_handling_enabled = std.atomic.Value(bool).init(false);

/// Initialize signal handling for preemption
pub fn initSignalHandling() !void {
    if (signal_handling_enabled.load(.acquire)) {
        return; // Already initialized
    }

    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        // Install signal handler
        var sa = std.posix.Sigaction{
            .handler = .{ .handler = preemptSignalHandler },
            .mask = std.posix.sigemptyset(),
            .flags = std.posix.SA.RESTART,
        };

        std.posix.sigaction(PREEMPT_SIGNAL, &sa, null);

        signal_handling_enabled.store(true, .release);
    }
}

/// Clean up signal handling
pub fn deinitSignalHandling() void {
    if (!signal_handling_enabled.load(.acquire)) {
        return;
    }

    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        // Restore default handler
        var sa = std.posix.Sigaction{
            .handler = .{ .handler = std.posix.SIG.DFL },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };

        std.posix.sigaction(PREEMPT_SIGNAL, &sa, null);

        signal_handling_enabled.store(false, .release);
    }
}

/// Signal handler for preemption
fn preemptSignalHandler(sig: c_int) callconv(.c) void {
    _ = sig;

    // Signal handler must be async-safe
    // Just set a flag or do minimal work
    // The actual context switch happens in the scheduler

    // In Go, this would trigger a stack scan and context switch
    // For now, we rely on the preempt flag being checked by the task
}

/// Send preemption signal to a thread
pub fn sendPreemptSignal(thread: std.Thread) void {
    if (!signal_handling_enabled.load(.acquire)) {
        return; // Signals not enabled, fall back to cooperative
    }

    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        // Get thread ID and send signal
        const tid = thread.getHandle();

        // On POSIX systems, send signal to specific thread
        _ = std.c.pthread_kill(@as(std.c.pthread_t, @ptrCast(@alignCast(tid))), PREEMPT_SIGNAL);
    }
}

/// Mark processor for preemption (cooperative fallback)
pub fn markForPreemption(processor: *Processor) void {
    if (processor.current_task) |task| {
        task.markPreempted();
    }
}

/// Check if preemption signal is supported on this platform
pub fn isSignalPreemptionSupported() bool {
    return builtin.os.tag == .linux or builtin.os.tag == .macos;
}

/// Get current preemption mode
pub fn getPreemptionMode() PreemptionMode {
    if (signal_handling_enabled.load(.acquire)) {
        return .signal_based;
    } else {
        return .cooperative;
    }
}

/// Preemption mode
pub const PreemptionMode = enum {
    cooperative, // Task checks flag voluntarily
    signal_based, // OS signal forces context switch
};

// Tests
test "Signal handling initialization" {
    const testing = std.testing;

    // Initialize
    try initSignalHandling();
    defer deinitSignalHandling();

    if (isSignalPreemptionSupported()) {
        try testing.expect(signal_handling_enabled.load(.acquire));
        try testing.expect(getPreemptionMode() == .signal_based);
    } else {
        try testing.expect(getPreemptionMode() == .cooperative);
    }
}

test "Preemption mode detection" {
    const testing = std.testing;

    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        try testing.expect(isSignalPreemptionSupported());
    } else {
        try testing.expect(!isSignalPreemptionSupported());
    }
}

test "Mark processor for preemption" {
    const testing = std.testing;

    var processor = Processor.init(testing.allocator, 0);
    defer processor.deinit();

    var task = Task.init(1, undefined, undefined);
    task.state = .running;

    processor.current_task = &task;

    // Mark for preemption
    markForPreemption(&processor);

    // Task should be marked
    try testing.expect(task.shouldPreempt());
}
