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

/// Async sleep (yields to event loop)
pub fn sleep(seconds: f64) void {
    const nanos = @as(u64, @intFromFloat(seconds * 1_000_000_000));
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
