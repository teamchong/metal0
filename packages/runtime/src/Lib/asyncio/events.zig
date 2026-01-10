//! asyncio.events - Event loop API
//! Reference: cpython/Lib/asyncio/events.py
//!
//! CPython __all__:
//!   ('AbstractEventLoopPolicy', 'AbstractEventLoop', 'AbstractServer',
//!    'Handle', 'TimerHandle', 'get_event_loop_policy', 'set_event_loop_policy',
//!    'get_event_loop', 'set_event_loop', 'new_event_loop',
//!    'get_running_loop', '_set_running_loop', '_get_running_loop')

const std = @import("std");
const asyncio = @import("../asyncio.zig");

// Re-export types from asyncio.zig (DRY)
pub const Task = asyncio.Task;
pub const TaskState = asyncio.TaskState;
pub const Future = asyncio.Future;

/// Handle - Wrapper for callback registration
/// CPython: class Handle
pub const Handle = struct {
    callback: *const fn (*anyopaque) void,
    context: *anyopaque,
    cancelled: bool,

    pub fn init(callback: *const fn (*anyopaque) void, context: *anyopaque) Handle {
        return .{
            .callback = callback,
            .context = context,
            .cancelled = false,
        };
    }

    pub fn cancel(self: *Handle) void {
        self.cancelled = true;
    }

    pub fn cancelled_check(self: *Handle) bool {
        return self.cancelled;
    }
};

/// TimerHandle - Handle for scheduled callbacks
/// CPython: class TimerHandle(Handle)
pub const TimerHandle = struct {
    handle: Handle,
    when: i128, // nanoseconds since epoch
    scheduled: bool,

    pub fn init(callback: *const fn (*anyopaque) void, context: *anyopaque, when: i128) TimerHandle {
        return .{
            .handle = Handle.init(callback, context),
            .when = when,
            .scheduled = true,
        };
    }

    pub fn cancel(self: *TimerHandle) void {
        self.handle.cancel();
        self.scheduled = false;
    }

    pub fn cancelled_check(self: *TimerHandle) bool {
        return self.handle.cancelled;
    }

    pub fn when_scheduled(self: *TimerHandle) i128 {
        return self.when;
    }
};

/// Simple event loop implementation
/// CPython: class BaseEventLoop(AbstractEventLoop)
pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    running: bool = false,
    closed: bool = false,
    ready: std.ArrayList(Handle) = .{},
    scheduled: std.ArrayList(TimerHandle) = .{},

    pub fn init(allocator: std.mem.Allocator) EventLoop {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *EventLoop) void {
        self.ready.deinit(self.allocator);
        self.scheduled.deinit(self.allocator);
    }

    pub fn runForever(self: *EventLoop) !void {
        self.running = true;
        defer self.running = false;

        while (self.running and !self.closed) {
            try self.runOnce();
        }
    }

    pub fn runOnce(self: *EventLoop) !void {
        // Process ready callbacks
        while (self.ready.items.len > 0) {
            const handle = self.ready.orderedRemove(0);
            if (!handle.cancelled) {
                handle.callback(handle.context);
            }
        }

        // Process scheduled callbacks
        const now = std.time.nanoTimestamp();
        var i: usize = 0;
        while (i < self.scheduled.items.len) {
            const timer = &self.scheduled.items[i];
            if (timer.when <= now and !timer.handle.cancelled) {
                timer.handle.callback(timer.handle.context);
                _ = self.scheduled.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn stop(self: *EventLoop) void {
        self.running = false;
    }

    pub fn isRunning(self: *const EventLoop) bool {
        return self.running;
    }

    pub fn isClosed(self: *const EventLoop) bool {
        return self.closed;
    }

    pub fn close(self: *EventLoop) void {
        self.closed = true;
    }

    pub fn callSoon(self: *EventLoop, callback: *const fn (*anyopaque) void, context: *anyopaque) !*Handle {
        const handle = try self.allocator.create(Handle);
        handle.* = Handle.init(callback, context);
        try self.ready.append(self.allocator, handle.*);
        return handle;
    }

    pub fn callLater(self: *EventLoop, delay: f64, callback: *const fn (*anyopaque) void, context: *anyopaque) !*TimerHandle {
        const when = std.time.nanoTimestamp() + @as(i128, @intFromFloat(delay * 1_000_000_000));
        const timer = try self.allocator.create(TimerHandle);
        timer.* = TimerHandle.init(callback, context, when);
        try self.scheduled.append(self.allocator, timer.*);
        return timer;
    }

    pub fn time(self: *const EventLoop) f64 {
        _ = self;
        return @as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1_000_000_000.0;
    }
};

/// Abstract event loop policy
/// CPython: class AbstractEventLoopPolicy
pub const AbstractEventLoopPolicy = struct {
    loop: ?*EventLoop = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AbstractEventLoopPolicy {
        return .{ .allocator = allocator };
    }

    pub fn getEventLoop(self: *AbstractEventLoopPolicy) !*EventLoop {
        if (self.loop == null) {
            self.loop = try self.allocator.create(EventLoop);
            self.loop.?.* = EventLoop.init(self.allocator);
        }
        return self.loop.?;
    }

    pub fn setEventLoop(self: *AbstractEventLoopPolicy, loop: ?*EventLoop) void {
        self.loop = loop;
    }

    pub fn newEventLoop(self: *AbstractEventLoopPolicy) !*EventLoop {
        const loop = try self.allocator.create(EventLoop);
        loop.* = EventLoop.init(self.allocator);
        return loop;
    }
};

/// Abstract server
/// CPython: class AbstractServer
pub const AbstractServer = struct {
    sockets: std.ArrayList(std.posix.socket_t) = .{},
    serving: bool = false,

    pub fn close(self: *AbstractServer) void {
        self.serving = false;
    }

    pub fn isServing(self: *const AbstractServer) bool {
        return self.serving;
    }
};

// Global event loop state
var running_loop: ?*EventLoop = null;
var running_loop_mutex: std.Thread.Mutex = .{};

/// Get the running event loop in the current thread
/// CPython: get_running_loop()
pub fn getRunningLoop() ?*EventLoop {
    running_loop_mutex.lock();
    defer running_loop_mutex.unlock();
    return running_loop;
}

/// Internal: Set the running loop
/// CPython: _set_running_loop(loop)
pub fn setRunningLoop(loop: ?*EventLoop) void {
    running_loop_mutex.lock();
    defer running_loop_mutex.unlock();
    running_loop = loop;
}

/// Internal: Get running loop (alias)
/// CPython: _get_running_loop()
pub fn getRunningLoopInternal() ?*EventLoop {
    return getRunningLoop();
}

/// Get the event loop for the current context
/// CPython: get_event_loop()
pub fn getEventLoop(allocator: std.mem.Allocator) !*EventLoop {
    if (running_loop) |loop| return loop;
    const loop = try allocator.create(EventLoop);
    loop.* = EventLoop.init(allocator);
    return loop;
}

/// Create a new event loop
/// CPython: new_event_loop()
pub fn newEventLoop(allocator: std.mem.Allocator) !*EventLoop {
    const loop = try allocator.create(EventLoop);
    loop.* = EventLoop.init(allocator);
    return loop;
}

// Tests
test "Handle creation and cancel" {
    const callback = struct {
        fn cb(_: *anyopaque) void {}
    }.cb;

    var dummy: i64 = 0;
    var handle = Handle.init(callback, @ptrCast(&dummy));

    try std.testing.expect(!handle.cancelled);
    handle.cancel();
    try std.testing.expect(handle.cancelled);
}

test "TimerHandle" {
    const callback = struct {
        fn cb(_: *anyopaque) void {}
    }.cb;

    var dummy: i64 = 0;
    const now = std.time.nanoTimestamp();
    var timer = TimerHandle.init(callback, @ptrCast(&dummy), now);

    try std.testing.expect(timer.scheduled);
    try std.testing.expect(!timer.handle.cancelled);

    timer.cancel();
    try std.testing.expect(!timer.scheduled);
    try std.testing.expect(timer.handle.cancelled);
}

test "EventLoop basic" {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.isRunning());
    try std.testing.expect(!loop.isClosed());
}
