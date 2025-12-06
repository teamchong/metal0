const std = @import("std");
const Future = @import("../future.zig").Future;
const Poll = @import("../future.zig").Poll;
const Waker = @import("../future.zig").Waker;
const Context = @import("../future.zig").Context;
const Task = @import("../task.zig").Task;
const TaskState = @import("../task.zig").TaskState;

/// Await a future (blocks current task until ready)
pub fn awaitFuture(comptime T: type, future: *Future(T), current_task: *Task) !T {
    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    // Polling loop
    const max_spins: usize = 1000;
    var spin_count: usize = 0;

    while (true) {
        const result = future.poll(&ctx);

        switch (result) {
            .ready => |value| {
                // Future is ready, return value
                current_task.state = .running;
                return value;
            },
            .pending => {
                // Fast path: spin a bit before yielding
                if (spin_count < max_spins) {
                    spin_count += 1;
                    std.atomic.spinLoopHint();
                    continue;
                }

                // Slow path: yield to scheduler
                current_task.state = .waiting;
                current_task.recordYield();

                // Simulated yield - in real implementation, scheduler would resume us
                // For now, we'll check again after a brief pause
                std.Thread.sleep(1000); // 1 microsecond

                // Reset spin count for next poll
                spin_count = 0;

                // Check if we were woken up
                if (current_task.state == .runnable) {
                    current_task.state = .running;
                }
            },
        }
    }
}

/// Await future with timeout
pub fn awaitFutureTimeout(
    comptime T: type,
    future: *Future(T),
    current_task: *Task,
    timeout_ns: u64,
) !T {
    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    const start_time = std.time.nanoTimestamp();
    const max_spins: usize = 1000;
    var spin_count: usize = 0;

    while (true) {
        // Check timeout
        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now - start_time));
        if (elapsed >= timeout_ns) {
            return error.Timeout;
        }

        const result = future.poll(&ctx);

        switch (result) {
            .ready => |value| {
                current_task.state = .running;
                return value;
            },
            .pending => {
                if (spin_count < max_spins) {
                    spin_count += 1;
                    std.atomic.spinLoopHint();
                    continue;
                }

                current_task.state = .waiting;
                current_task.recordYield();

                std.time.sleep(1000);
                spin_count = 0;

                if (current_task.state == .runnable) {
                    current_task.state = .running;
                }
            },
        }
    }
}

/// Poll future once without blocking
pub fn pollOnce(comptime T: type, future: *Future(T), current_task: *Task) Poll(T) {
    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);
    return future.poll(&ctx);
}

/// Block on future until complete (for testing)
pub fn blockOn(comptime T: type, future: *Future(T), allocator: std.mem.Allocator) !T {
    // Create temporary task for blocking
    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);

    temp_task.* = Task.init(
        0,
        struct {
            fn dummy(_: *anyopaque) !void {}
        }.dummy,
        undefined,
    );
    temp_task.state = .running;

    return awaitFuture(T, future, temp_task);
}

/// Block on future with timeout
pub fn blockOnTimeout(
    comptime T: type,
    future: *Future(T),
    allocator: std.mem.Allocator,
    timeout_ns: u64,
) !T {
    const temp_task = try allocator.create(Task);
    defer allocator.destroy(temp_task);

    temp_task.* = Task.init(
        0,
        struct {
            fn dummy(_: *anyopaque) !void {}
        }.dummy,
        undefined,
    );
    temp_task.state = .running;

    return awaitFutureTimeout(T, future, temp_task, timeout_ns);
}

/// Yielding strategy for polling
pub const YieldStrategy = enum {
    /// Spin briefly then yield to scheduler
    adaptive,
    /// Always yield immediately
    immediate,
    /// Never yield (busy wait)
    busy,
};

/// Configurable polling
pub const PollConfig = struct {
    yield_strategy: YieldStrategy = .adaptive,
    max_spins: usize = 1000,
    sleep_ns: u64 = 1000, // 1 microsecond
};

/// Await with custom poll config
pub fn awaitFutureWithConfig(
    comptime T: type,
    future: *Future(T),
    current_task: *Task,
    config: PollConfig,
) !T {
    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    var spin_count: usize = 0;

    while (true) {
        const result = future.poll(&ctx);

        switch (result) {
            .ready => |value| {
                current_task.state = .running;
                return value;
            },
            .pending => {
                switch (config.yield_strategy) {
                    .adaptive => {
                        if (spin_count < config.max_spins) {
                            spin_count += 1;
                            std.atomic.spinLoopHint();
                            continue;
                        }

                        current_task.state = .waiting;
                        current_task.recordYield();
                        std.Thread.sleep(config.sleep_ns);
                        spin_count = 0;

                        if (current_task.state == .runnable) {
                            current_task.state = .running;
                        }
                    },
                    .immediate => {
                        current_task.state = .waiting;
                        current_task.recordYield();
                        std.Thread.sleep(config.sleep_ns);

                        if (current_task.state == .runnable) {
                            current_task.state = .running;
                        }
                    },
                    .busy => {
                        std.atomic.spinLoopHint();
                    },
                }
            },
        }
    }
}

/// Helper to create a future that polls a function
pub fn pollFn(
    comptime T: type,
    allocator: std.mem.Allocator,
    func: *const fn () Poll(T),
) !*Future(T) {
    const future = try Future(T).init(allocator);

    // Immediately poll once
    const result = func();
    if (result.isReady()) {
        future.resolve(result.unwrap());
    }

    return future;
}

/// Helper to yield to scheduler
pub fn yieldNow(current_task: *Task) void {
    current_task.state = .waiting;
    current_task.recordYield();
    std.Thread.sleep(1);
    current_task.state = .runnable;
}
