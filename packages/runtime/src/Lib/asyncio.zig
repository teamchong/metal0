/// Python asyncio module implementation
/// Powered by metal0's goroutine + channel infrastructure
///
/// Usage in Python:
///   import asyncio
///
///   async def fetch(url):
///       return await http.get(url)
///
///   async def main():
///       results = await asyncio.gather(fetch(url1), fetch(url2))
///
///   asyncio.run(main())
///
/// Under the hood:
///   - async def -> GreenThread (goroutine)
///   - await -> scheduler yield
///   - asyncio.gather -> spawn goroutines, collect via channel
///   - asyncio.run -> start scheduler, run until complete
const std = @import("std");
const Scheduler = @import("scheduler").Scheduler;
const GreenThread = @import("green_thread").GreenThread;
const channel = @import("async/channel.zig");

/// Global scheduler instance (initialized on first use)
var global_scheduler: ?*Scheduler = null;
var scheduler_mutex: std.Thread.Mutex = .{};

/// Get or create global scheduler
fn getScheduler(allocator: std.mem.Allocator) !*Scheduler {
    scheduler_mutex.lock();
    defer scheduler_mutex.unlock();

    if (global_scheduler) |s| return s;

    const s = try allocator.create(Scheduler);
    s.* = try Scheduler.init(allocator, 0); // 0 = auto-detect CPU count
    try s.start();
    global_scheduler = s;
    return s;
}

/// asyncio.run(coro) - Run coroutine until complete
/// This is the main entry point for async Python code
pub fn run(allocator: std.mem.Allocator, comptime coro: anytype) !@typeInfo(@TypeOf(coro)).@"fn".return_type.? {
    const scheduler = try getScheduler(allocator);

    // Spawn the coroutine as a goroutine
    const ResultType = @typeInfo(@TypeOf(coro)).@"fn".return_type.?;
    var result: ResultType = undefined;
    var done = std.atomic.Value(bool).init(false);

    const Context = struct {
        result_ptr: *ResultType,
        done_flag: *std.atomic.Value(bool),

        fn wrapper(ctx: *@This()) void {
            ctx.result_ptr.* = coro() catch |err| {
                std.debug.print("asyncio.run error: {}\n", .{err});
                return;
            };
            ctx.done_flag.store(true, .release);
        }
    };

    var ctx = Context{
        .result_ptr = &result,
        .done_flag = &done,
    };

    _ = try scheduler.spawn(Context.wrapper, .{&ctx});

    // Wait for completion
    while (!done.load(.acquire)) {
        std.Thread.yield() catch {};
    }

    return result;
}

/// asyncio.run for void-returning coroutines
pub fn runVoid(allocator: std.mem.Allocator, comptime coro: fn () void) !void {
    const scheduler = try getScheduler(allocator);

    var done = std.atomic.Value(bool).init(false);

    const Context = struct {
        done_flag: *std.atomic.Value(bool),

        fn wrapper(ctx: *@This()) void {
            coro();
            ctx.done_flag.store(true, .release);
        }
    };

    var ctx = Context{ .done_flag = &done };
    _ = try scheduler.spawn(Context.wrapper, .{&ctx});

    while (!done.load(.acquire)) {
        std.Thread.yield() catch {};
    }
}

/// asyncio.sleep(seconds) - Sleep without blocking the scheduler
pub fn sleep(allocator: std.mem.Allocator, seconds: f64) !void {
    _ = allocator;
    const ns = @as(u64, @intFromFloat(seconds * 1_000_000_000));
    std.Thread.sleep(ns);
}

/// asyncio.create_task(coro) - Spawn coroutine as background task
pub fn createTask(allocator: std.mem.Allocator, comptime coro: anytype) !*GreenThread {
    const scheduler = try getScheduler(allocator);
    return scheduler.spawn0(coro);
}

/// Task result for gather operations
pub fn TaskResult(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: anyerror,
    };
}

/// asyncio.gather(*coros) - Run multiple coroutines concurrently
/// Returns when all complete
pub fn gather(
    allocator: std.mem.Allocator,
    comptime ResultType: type,
    tasks: []const *const fn () anyerror!ResultType,
) ![]ResultType {
    const scheduler = try getScheduler(allocator);

    // Create result channel
    const ResultChan = channel.Channel(TaskResult(ResultType));
    const result_chan = try ResultChan.initBuffered(allocator, tasks.len);
    defer result_chan.deinit();

    // Spawn all tasks
    for (tasks) |task_fn| {
        const Context = struct {
            func: *const fn () anyerror!ResultType,
            chan: *ResultChan,
            alloc: std.mem.Allocator,

            fn wrapper(ctx: *@This()) void {
                const result = ctx.func() catch |err| {
                    _ = ctx.chan.trySend(.{ .err = err }) catch {};
                    return;
                };
                _ = ctx.chan.trySend(.{ .ok = result }) catch {};
            }
        };

        const ctx = try allocator.create(Context);
        ctx.* = .{
            .func = task_fn,
            .chan = result_chan,
            .alloc = allocator,
        };

        _ = try scheduler.spawn(Context.wrapper, .{ctx});
    }

    // Collect results
    var results = try allocator.alloc(ResultType, tasks.len);
    errdefer allocator.free(results);

    var collected: usize = 0;
    while (collected < tasks.len) {
        if (result_chan.tryRecv()) |task_result| {
            switch (task_result) {
                .ok => |val| {
                    results[collected] = val;
                    collected += 1;
                },
                .err => |err| {
                    allocator.free(results);
                    return err;
                },
            }
        } else {
            std.Thread.yield() catch {};
        }
    }

    return results;
}

/// asyncio.wait(tasks, timeout) - Wait for tasks with optional timeout
pub fn wait(
    allocator: std.mem.Allocator,
    tasks: []*GreenThread,
    timeout_seconds: ?f64,
) !struct { done: []*GreenThread, pending: []*GreenThread } {
    const start = std.time.milliTimestamp();
    const timeout_ms: ?i64 = if (timeout_seconds) |t| @intFromFloat(t * 1000) else null;

    var done_list = std.ArrayList(*GreenThread).init(allocator);
    defer done_list.deinit();

    var pending_list = std.ArrayList(*GreenThread).init(allocator);
    defer pending_list.deinit();

    for (tasks) |task| {
        // Check timeout
        if (timeout_ms) |tm| {
            const elapsed = std.time.milliTimestamp() - start;
            if (elapsed >= tm) {
                try pending_list.append(task);
                continue;
            }
        }

        // Check if task is done
        if (task.state == .completed) {
            try done_list.append(task);
        } else {
            try pending_list.append(task);
        }
    }

    return .{
        .done = try done_list.toOwnedSlice(),
        .pending = try pending_list.toOwnedSlice(),
    };
}

/// Shutdown the global scheduler
pub fn shutdown() void {
    scheduler_mutex.lock();
    defer scheduler_mutex.unlock();

    if (global_scheduler) |s| {
        s.deinit();
        s.allocator.destroy(s);
        global_scheduler = null;
    }
}

/// asyncio.Queue - Thread-safe queue backed by channel
pub fn Queue(comptime T: type) type {
    return struct {
        chan: *channel.Channel(T),
        allocator: std.mem.Allocator,

        const Self = @This();

        /// Create queue with maxsize (0 = unbounded)
        pub fn init(allocator: std.mem.Allocator, maxsize: usize) !*Self {
            const self = try allocator.create(Self);
            self.* = Self{
                .chan = try channel.makeBuffered(T, allocator, if (maxsize == 0) 1024 else maxsize),
                .allocator = allocator,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.chan.deinit();
            self.allocator.destroy(self);
        }

        /// Non-blocking put
        pub fn put_nowait(self: *Self, item: T) !void {
            const sent = try self.chan.trySend(item);
            if (!sent) return error.QueueFull;
        }

        /// Non-blocking get
        pub fn get_nowait(self: *Self) !T {
            return self.chan.tryRecv() orelse error.QueueEmpty;
        }

        /// Check if queue is empty
        pub fn empty(self: *Self) bool {
            return self.chan.isEmpty();
        }

        /// Check if queue is full
        pub fn full(self: *Self) bool {
            return self.chan.isFull();
        }

        /// Get current queue size
        pub fn qsize(self: *Self) usize {
            return self.chan.len();
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "asyncio.Queue with channel" {
    const testing = std.testing;
    const IntQueue = Queue(i64);

    var queue = try IntQueue.init(testing.allocator, 10);
    defer queue.deinit();

    try testing.expect(queue.empty());
    try testing.expect(!queue.full());
    try testing.expectEqual(@as(usize, 0), queue.qsize());

    // Put/get
    try queue.put_nowait(42);
    try testing.expectEqual(@as(usize, 1), queue.qsize());

    const val = try queue.get_nowait();
    try testing.expectEqual(@as(i64, 42), val);
    try testing.expect(queue.empty());
}

test "asyncio.sleep" {
    const start = std.time.milliTimestamp();
    try sleep(std.testing.allocator, 0.01); // 10ms
    const elapsed = std.time.milliTimestamp() - start;
    try std.testing.expect(elapsed >= 10);
}
