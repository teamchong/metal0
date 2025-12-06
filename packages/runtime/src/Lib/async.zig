const std = @import("std");

// Re-export async runtime components
pub const runtime = @import("async/runtime.zig");

// Core types
pub const Task = runtime.Task;
pub const TaskState = runtime.TaskState;
pub const TaskFn = runtime.TaskFn;

pub const Processor = runtime.Processor;
pub const ProcessorState = runtime.ProcessorState;

pub const Machine = runtime.Machine;
pub const MachineState = runtime.MachineState;

// Runtimes
pub const SimpleRuntime = runtime.SimpleRuntime;
pub const Runtime = runtime.Runtime;
pub const RuntimeConfig = runtime.RuntimeConfig;

// Runtime components
pub const EventLoop = runtime.EventLoop;
pub const SimpleScheduler = runtime.SimpleScheduler;
pub const TaskSpawner = runtime.TaskSpawner;
pub const Yielder = runtime.Yielder;
pub const YieldStrategy = runtime.YieldStrategy;

// Async primitives
pub const future = @import("async/future.zig");
pub const Future = future.Future;
pub const Poll = future.Poll;
pub const Waker = future.Waker;
pub const Context = future.Context;

pub const channel = @import("async/channel.zig");
pub const Channel = channel.Channel;
pub const Sender = channel.Sender;
pub const Receiver = channel.Receiver;

pub const poller = @import("async/poller/common.zig");
pub const Poller = poller.Poller;
pub const Event = poller.Event;

// Global runtime functions
pub const spawn = runtime.spawn;
pub const yield = runtime.yield;
pub const run = runtime.run;
pub const getRuntime = runtime.getRuntime;

/// Async sleep using busy-wait with yields
/// This is a simple implementation - for true async we need coroutines
pub fn sleep(seconds: f64) void {
    const nanos: u64 = @intFromFloat(seconds * 1_000_000_000);

    // For very short sleeps (< 100µs), just busy-wait
    if (nanos < 100_000) {
        const deadline = std.time.nanoTimestamp() + @as(i128, nanos);
        while (std.time.nanoTimestamp() < deadline) {
            std.atomic.spinLoopHint();
        }
        return;
    }

    // For short sleeps (<= 10ms), yield loop - allows other threads to run
    if (nanos <= 10_000_000) {
        const deadline = std.time.nanoTimestamp() + @as(i128, nanos);
        while (std.time.nanoTimestamp() < deadline) {
            std.Thread.yield() catch {};
        }
        return;
    }

    // For longer sleeps, use OS timer
    std.Thread.sleep(nanos);
}

/// Async sleep returning when done
pub fn sleepAsync(seconds: f64) !void {
    sleep(seconds);
}

/// Get current timestamp (for benchmarks)
pub fn now() f64 {
    const ns = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}
