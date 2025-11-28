/// metal0 Event Loop for Python asyncio
///
/// Inspired by Bun's event_loop.zig but simplified for Python asyncio needs
/// Architecture based on Bun, implementation focused on asyncio API
const std = @import("std");
const builtin = @import("builtin");

const EventLoop = @This();

/// Task to execute
const Task = struct {
    callback: *const fn (*anyopaque) void,
    data: *anyopaque,
    next: ?*Task = null,
};

/// Timer entry
const Timer = struct {
    deadline: i64, // nanoseconds since epoch
    callback: *const fn (*anyopaque) void,
    data: *anyopaque,
    cancelled: bool = false,
};

/// Event loop state
allocator: std.mem.Allocator,
running: bool = false,
task_queue: ?*Task = null,
task_queue_tail: ?*Task = null,
timers: std.ArrayList(Timer),
platform_fd: if (builtin.os.tag == .macos or builtin.os.tag == .ios) c_int else if (builtin.os.tag == .linux) c_int else void,

/// Initialize event loop
pub fn init(allocator: std.mem.Allocator) !EventLoop {
    var loop = EventLoop{
        .allocator = allocator,
        .timers = std.ArrayList(Timer).init(allocator),
        .platform_fd = undefined,
    };

    // Initialize platform-specific event mechanism
    if (builtin.os.tag == .macos or builtin.os.tag == .ios) {
        // Create kqueue
        const kq = std.c.kqueue();
        if (kq == -1) return error.KqueueCreateFailed;
        loop.platform_fd = kq;
    } else if (builtin.os.tag == .linux) {
        // Create epoll
        const epfd = std.os.linux.epoll_create1(0);
        if (epfd < 0) return error.EpollCreateFailed;
        loop.platform_fd = @intCast(epfd);
    }

    return loop;
}

/// Deinitialize event loop
pub fn deinit(self: *EventLoop) void {
    // Clean up platform fd
    if (builtin.os.tag == .macos or builtin.os.tag == .ios or builtin.os.tag == .linux) {
        _ = std.c.close(self.platform_fd);
    }

    // Clean up timers
    self.timers.deinit();

    // Clean up task queue
    var task = self.task_queue;
    while (task) |t| {
        const next = t.next;
        self.allocator.destroy(t);
        task = next;
    }
}

/// Queue a task for execution
pub fn queueTask(self: *EventLoop, callback: *const fn (*anyopaque) void, data: *anyopaque) !void {
    const task = try self.allocator.create(Task);
    task.* = .{
        .callback = callback,
        .data = data,
        .next = null,
    };

    if (self.task_queue_tail) |tail| {
        tail.next = task;
        self.task_queue_tail = task;
    } else {
        self.task_queue = task;
        self.task_queue_tail = task;
    }
}

/// Schedule timer
pub fn scheduleTimer(self: *EventLoop, delay_ns: i64, callback: *const fn (*anyopaque) void, data: *anyopaque) !void {
    const now = std.time.nanoTimestamp();
    try self.timers.append(.{
        .deadline = now + delay_ns,
        .callback = callback,
        .data = data,
    });
}

/// Process all pending tasks
fn processTasks(self: *EventLoop) void {
    while (self.task_queue) |task| {
        self.task_queue = task.next;
        if (self.task_queue == null) {
            self.task_queue_tail = null;
        }

        task.callback(task.data);
        self.allocator.destroy(task);
    }
}

/// Process expired timers
fn processTimers(self: *EventLoop) void {
    const now = std.time.nanoTimestamp();
    var i: usize = 0;

    while (i < self.timers.items.len) {
        const timer = &self.timers.items[i];

        if (!timer.cancelled and timer.deadline <= now) {
            timer.callback(timer.data);
            _ = self.timers.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

/// Get time until next timer (nanoseconds)
fn getNextTimerDelay(self: *EventLoop) ?i64 {
    var min_deadline: ?i64 = null;

    for (self.timers.items) |timer| {
        if (timer.cancelled) continue;

        if (min_deadline) |min| {
            if (timer.deadline < min) {
                min_deadline = timer.deadline;
            }
        } else {
            min_deadline = timer.deadline;
        }
    }

    if (min_deadline) |deadline| {
        const now = std.time.nanoTimestamp();
        const delay = deadline - now;
        return if (delay > 0) delay else 0;
    }

    return null;
}

/// Run event loop
pub fn run(self: *EventLoop) !void {
    self.running = true;

    while (self.running) {
        // Process tasks
        self.processTasks();

        // Process timers
        self.processTimers();

        // Check if we have more work
        const has_tasks = self.task_queue != null;
        const has_timers = self.timers.items.len > 0;

        if (!has_tasks and !has_timers) {
            // No more work
            break;
        }

        // Wait for events or next timer
        if (self.getNextTimerDelay()) |delay| {
            // Sleep until next timer
            const sleep_ms = @divTrunc(delay, std.time.ns_per_ms);
            if (sleep_ms > 0) {
                std.time.sleep(@intCast(sleep_ms * std.time.ns_per_ms));
            }
        } else if (!has_tasks) {
            // No timers and no tasks - we're done
            break;
        }
    }

    self.running = false;
}

/// Stop event loop
pub fn stop(self: *EventLoop) void {
    self.running = false;
}

// Tests
test "EventLoop init/deinit" {
    var loop = try EventLoop.init(std.testing.allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.running);
}

test "EventLoop task queue" {
    var loop = try EventLoop.init(std.testing.allocator);
    defer loop.deinit();

    var called = false;
    const callback = struct {
        fn cb(data: *anyopaque) void {
            const ptr = @as(*bool, @ptrCast(@alignCast(data)));
            ptr.* = true;
        }
    }.cb;

    try loop.queueTask(callback, &called);
    loop.processTasks();

    try std.testing.expect(called);
}

test "EventLoop timer" {
    var loop = try EventLoop.init(std.testing.allocator);
    defer loop.deinit();

    var called = false;
    const callback = struct {
        fn cb(data: *anyopaque) void {
            const ptr = @as(*bool, @ptrCast(@alignCast(data)));
            ptr.* = true;
        }
    }.cb;

    // Schedule timer for 10ms from now
    try loop.scheduleTimer(10 * std.time.ns_per_ms, callback, &called);

    // Sleep a bit
    std.time.sleep(20 * std.time.ns_per_ms);

    loop.processTimers();
    try std.testing.expect(called);
}
