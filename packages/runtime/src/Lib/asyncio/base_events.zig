//! asyncio.base_events - Base event loop implementation
//! Reference: cpython/Lib/asyncio/base_events.py
//!
//! CPython exports: BaseEventLoop (large class with ~2100 LOC)

const std = @import("std");
const asyncio = @import("../asyncio.zig");
const events = @import("events.zig");
const futures = @import("futures.zig");
const constants = @import("constants.zig");

/// Base event loop implementation
/// CPython: class BaseEventLoop(events.AbstractEventLoop)
pub const BaseEventLoop = struct {
    allocator: std.mem.Allocator,
    running: bool = false,
    closed: bool = false,
    stopping: bool = false,
    debug: bool = false,
    ready: std.ArrayList(events.Handle) = .{},
    scheduled: std.ArrayList(events.TimerHandle) = .{},
    current_handle: ?*events.Handle = null,
    thread_id: ?std.Thread.Id = null,
    clock_resolution: f64 = 0.001, // 1ms
    slow_callback_duration: f64 = 0.1, // 100ms

    pub fn init(allocator: std.mem.Allocator) BaseEventLoop {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BaseEventLoop) void {
        self.ready.deinit(self.allocator);
        self.scheduled.deinit(self.allocator);
    }

    /// Get current event loop time
    pub fn time(self: *const BaseEventLoop) f64 {
        _ = self;
        return @as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1_000_000_000.0;
    }

    /// Run forever
    pub fn runForever(self: *BaseEventLoop) !void {
        if (self.running) return error.AlreadyRunning;
        if (self.closed) return error.LoopClosed;

        self.running = true;
        self.thread_id = std.Thread.getCurrentId();
        defer {
            self.running = false;
            self.thread_id = null;
        }

        while (!self.stopping) {
            try self.runOnce(null);
        }
    }

    /// Run until complete
    pub fn runUntilComplete(self: *BaseEventLoop, comptime T: type, future: *futures.Future(T)) !T {
        if (self.running) return error.AlreadyRunning;

        self.running = true;
        defer self.running = false;

        while (!future.isReady()) {
            try self.runOnce(null);
        }

        return future.tryGet() orelse error.FutureError;
    }

    /// Run one iteration of the event loop
    pub fn runOnce(self: *BaseEventLoop, timeout: ?f64) !void {
        _ = timeout;

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

        // Small sleep to prevent busy-waiting
        std.Thread.sleep(1_000); // 1µs
    }

    /// Stop the event loop
    pub fn stop(self: *BaseEventLoop) void {
        self.stopping = true;
    }

    /// Close the event loop
    pub fn close(self: *BaseEventLoop) void {
        if (self.running) return;
        self.closed = true;
    }

    pub fn isRunning(self: *const BaseEventLoop) bool {
        return self.running;
    }

    pub fn isClosed(self: *const BaseEventLoop) bool {
        return self.closed;
    }

    /// Schedule callback soon
    pub fn callSoon(self: *BaseEventLoop, callback: *const fn (*anyopaque) void, context: *anyopaque) !void {
        const handle = events.Handle.init(callback, context);
        try self.ready.append(self.allocator, handle);
    }

    /// Schedule callback after delay
    pub fn callLater(self: *BaseEventLoop, delay: f64, callback: *const fn (*anyopaque) void, context: *anyopaque) !void {
        const when = std.time.nanoTimestamp() + @as(i128, @intFromFloat(delay * 1_000_000_000));
        const timer = events.TimerHandle.init(callback, context, when);
        try self.scheduled.append(self.allocator, timer);
    }

    /// Schedule callback at absolute time
    pub fn callAt(self: *BaseEventLoop, when: f64, callback: *const fn (*anyopaque) void, context: *anyopaque) !void {
        const when_ns = @as(i128, @intFromFloat(when * 1_000_000_000));
        const timer = events.TimerHandle.init(callback, context, when_ns);
        try self.scheduled.append(self.allocator, timer);
    }
};

// Tests
test "BaseEventLoop creation" {
    const allocator = std.testing.allocator;
    var loop = BaseEventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.running);
    try std.testing.expect(!loop.closed);

    const t = loop.time();
    try std.testing.expect(t > 0);
}

test "BaseEventLoop callSoon" {
    const allocator = std.testing.allocator;
    var loop = BaseEventLoop.init(allocator);
    defer loop.deinit();

    const callback = struct {
        fn cb(_: *anyopaque) void {}
    }.cb;

    var dummy: i64 = 0;
    try loop.callSoon(callback, @ptrCast(&dummy));
    try std.testing.expectEqual(@as(usize, 1), loop.ready.items.len);
}
