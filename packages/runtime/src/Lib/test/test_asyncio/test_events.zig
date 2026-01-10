//! test.test_asyncio.test_events - Tests for asyncio event loop
//! Reference: cpython/Lib/test/test_asyncio/test_events.py
//!
//! Tests for event loop creation, running, and lifecycle

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");

// ============================================================================
// Event Loop Policy
// ============================================================================

/// Abstract event loop policy
pub const AbstractEventLoopPolicy = struct {
    const Self = @This();

    vtable: *const VTable,

    pub const VTable = struct {
        get_event_loop: *const fn (*Self) ?*AbstractEventLoop,
        set_event_loop: *const fn (*Self, ?*AbstractEventLoop) void,
        new_event_loop: *const fn (*Self) *AbstractEventLoop,
    };

    pub fn get_event_loop(self: *Self) ?*AbstractEventLoop {
        return self.vtable.get_event_loop(self);
    }

    pub fn set_event_loop(self: *Self, loop: ?*AbstractEventLoop) void {
        self.vtable.set_event_loop(self, loop);
    }

    pub fn new_event_loop(self: *Self) *AbstractEventLoop {
        return self.vtable.new_event_loop(self);
    }
};

/// Abstract event loop interface
pub const AbstractEventLoop = struct {
    const Self = @This();

    vtable: *const VTable,
    _running: bool = false,
    _closed: bool = false,

    pub const VTable = struct {
        run_forever: *const fn (*Self) void,
        run_until_complete: *const fn (*Self, anytype) anytype,
        stop: *const fn (*Self) void,
        close: *const fn (*Self) void,
        is_running: *const fn (*Self) bool,
        is_closed: *const fn (*Self) bool,
        call_soon: *const fn (*Self, anytype) void,
        call_later: *const fn (*Self, f64, anytype) void,
        call_at: *const fn (*Self, f64, anytype) void,
        time: *const fn (*Self) f64,
    };

    pub fn is_running(self: *Self) bool {
        return self._running;
    }

    pub fn is_closed(self: *Self) bool {
        return self._closed;
    }
};

// ============================================================================
// Handle for Callbacks
// ============================================================================

/// A handle for a scheduled callback
pub const Handle = struct {
    const Self = @This();

    _callback: *const fn () void,
    _cancelled: bool = false,
    _loop: *EventLoop,

    pub fn cancel(self: *Self) void {
        self._cancelled = true;
    }

    pub fn cancelled(self: *const Self) bool {
        return self._cancelled;
    }
};

/// A handle for a timed callback
pub const TimerHandle = struct {
    const Self = @This();

    _callback: *const fn () void,
    _when: f64,
    _cancelled: bool = false,
    _loop: *EventLoop,

    pub fn cancel(self: *Self) void {
        self._cancelled = true;
    }

    pub fn cancelled(self: *const Self) bool {
        return self._cancelled;
    }

    pub fn when(self: *const Self) f64 {
        return self._when;
    }
};

// ============================================================================
// Event Loop Implementation
// ============================================================================

/// A basic event loop for testing
pub const EventLoop = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _running: bool = false,
    _closed: bool = false,
    _stopping: bool = false,
    _ready: std.ArrayList(Handle),
    _scheduled: std.ArrayList(TimerHandle),
    _time: f64 = 0,
    _debug: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._ready = std.ArrayList(Handle).init(allocator),
            ._scheduled = std.ArrayList(TimerHandle).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._ready.deinit();
        self._scheduled.deinit();
    }

    pub fn is_running(self: *const Self) bool {
        return self._running;
    }

    pub fn is_closed(self: *const Self) bool {
        return self._closed;
    }

    pub fn time(self: *const Self) f64 {
        return self._time;
    }

    pub fn get_debug(self: *const Self) bool {
        return self._debug;
    }

    pub fn set_debug(self: *Self, enabled: bool) void {
        self._debug = enabled;
    }

    /// Schedule a callback to be called soon
    pub fn call_soon(self: *Self, callback: *const fn () void) !*Handle {
        const handle = Handle{
            ._callback = callback,
            ._loop = self,
        };
        try self._ready.append(handle);
        return &self._ready.items[self._ready.items.len - 1];
    }

    /// Schedule a callback after delay seconds
    pub fn call_later(self: *Self, delay: f64, callback: *const fn () void) !*TimerHandle {
        return self.call_at(self._time + delay, callback);
    }

    /// Schedule a callback at absolute time
    pub fn call_at(self: *Self, when_time: f64, callback: *const fn () void) !*TimerHandle {
        const handle = TimerHandle{
            ._callback = callback,
            ._when = when_time,
            ._loop = self,
        };
        try self._scheduled.append(handle);
        return &self._scheduled.items[self._scheduled.items.len - 1];
    }

    /// Run one iteration of the event loop
    pub fn run_once(self: *Self) void {
        // Run ready callbacks
        const ready = self._ready.items;
        self._ready.clearRetainingCapacity();

        for (ready) |handle| {
            if (!handle._cancelled) {
                handle._callback();
            }
        }

        // Check scheduled callbacks
        var i: usize = 0;
        while (i < self._scheduled.items.len) {
            const handle = self._scheduled.items[i];
            if (handle._when <= self._time) {
                if (!handle._cancelled) {
                    handle._callback();
                }
                _ = self._scheduled.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Run the event loop until stop() is called
    pub fn run_forever(self: *Self) void {
        if (self._running) {
            @panic("This event loop is already running");
        }
        if (self._closed) {
            @panic("Event loop is closed");
        }

        self._running = true;
        defer self._running = false;

        while (!self._stopping) {
            self.run_once();
            if (self._ready.items.len == 0 and self._scheduled.items.len == 0) {
                break;
            }
        }

        self._stopping = false;
    }

    /// Stop the event loop
    pub fn stop(self: *Self) void {
        self._stopping = true;
    }

    /// Close the event loop
    pub fn close(self: *Self) void {
        if (self._running) {
            @panic("Cannot close a running event loop");
        }
        if (self._closed) {
            return;
        }
        self._closed = true;
    }

    /// Create a future
    pub fn create_future(self: *Self) Future {
        return Future.init(self);
    }
};

// ============================================================================
// Future Implementation
// ============================================================================

pub const FutureState = enum {
    pending,
    cancelled,
    finished,
};

/// A Future represents an eventual result
pub const Future = struct {
    const Self = @This();

    _loop: *EventLoop,
    _state: FutureState = .pending,
    _result: ?*anyopaque = null,
    _exception: ?anyerror = null,
    _callbacks: std.ArrayList(*const fn (*Self) void),

    pub fn init(loop: *EventLoop) Self {
        return .{
            ._loop = loop,
            ._callbacks = std.ArrayList(*const fn (*Self) void).init(loop.allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._callbacks.deinit();
    }

    pub fn done(self: *const Self) bool {
        return self._state != .pending;
    }

    pub fn cancelled(self: *const Self) bool {
        return self._state == .cancelled;
    }

    pub fn result(self: *const Self) !?*anyopaque {
        if (self._state == .cancelled) {
            return error.CancelledError;
        }
        if (self._state == .pending) {
            return error.InvalidStateError;
        }
        if (self._exception) |exc| {
            return exc;
        }
        return self._result;
    }

    pub fn exception(self: *const Self) ?anyerror {
        if (self._state == .cancelled) {
            return error.CancelledError;
        }
        return self._exception;
    }

    pub fn set_result(self: *Self, res: ?*anyopaque) !void {
        if (self.done()) {
            return error.InvalidStateError;
        }
        self._result = res;
        self._state = .finished;
        self.schedule_callbacks();
    }

    pub fn set_exception(self: *Self, exc: anyerror) !void {
        if (self.done()) {
            return error.InvalidStateError;
        }
        self._exception = exc;
        self._state = .finished;
        self.schedule_callbacks();
    }

    pub fn cancel(self: *Self) bool {
        if (self.done()) {
            return false;
        }
        self._state = .cancelled;
        self.schedule_callbacks();
        return true;
    }

    pub fn add_done_callback(self: *Self, callback: *const fn (*Self) void) !void {
        if (self.done()) {
            callback(self);
        } else {
            try self._callbacks.append(callback);
        }
    }

    fn schedule_callbacks(self: *Self) void {
        for (self._callbacks.items) |callback| {
            callback(self);
        }
        self._callbacks.clearRetainingCapacity();
    }

    pub fn get_loop(self: *const Self) *EventLoop {
        return self._loop;
    }
};

// ============================================================================
// Global State
// ============================================================================

var _running_loop: ?*EventLoop = null;
var _event_loop_policy: ?*AbstractEventLoopPolicy = null;

pub fn get_running_loop() ?*EventLoop {
    return _running_loop;
}

pub fn get_event_loop() ?*EventLoop {
    if (_running_loop) |loop| {
        return loop;
    }
    return null;
}

pub fn set_event_loop(loop: ?*EventLoop) void {
    _ = loop;
    // Not implemented for tests
}

pub fn new_event_loop(allocator: std.mem.Allocator) EventLoop {
    return EventLoop.init(allocator);
}

// ============================================================================
// Test Cases
// ============================================================================

fn testEventLoopCreate() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.is_running());
    try std.testing.expect(!loop.is_closed());
}

fn testEventLoopClose() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    loop.close();
    try std.testing.expect(loop.is_closed());
}

fn testEventLoopCallSoon() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    var called = false;
    const callback = struct {
        fn cb() void {
            // Note: Can't capture in Zig, just verify it was called
        }
    }.cb;

    _ = try loop.call_soon(callback);
    try std.testing.expectEqual(@as(usize, 1), loop._ready.items.len);
    _ = called;
}

fn testHandleCancel() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    const callback = struct {
        fn cb() void {}
    }.cb;

    const handle = try loop.call_soon(callback);
    try std.testing.expect(!handle.cancelled());
    handle.cancel();
    try std.testing.expect(handle.cancelled());
}

fn testTimerHandle() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    const callback = struct {
        fn cb() void {}
    }.cb;

    const handle = try loop.call_later(1.0, callback);
    try std.testing.expectEqual(@as(f64, 1.0), handle.when());
    try std.testing.expect(!handle.cancelled());
}

fn testFutureBasic() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    var fut = loop.create_future();
    defer fut.deinit();

    try std.testing.expect(!fut.done());
    try std.testing.expect(!fut.cancelled());

    try fut.set_result(null);
    try std.testing.expect(fut.done());
}

fn testFutureCancel() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    var fut = loop.create_future();
    defer fut.deinit();

    try std.testing.expect(fut.cancel());
    try std.testing.expect(fut.cancelled());
    try std.testing.expect(fut.done());
}

fn testFutureSetResultTwice() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    var fut = loop.create_future();
    defer fut.deinit();

    try fut.set_result(null);
    const err = fut.set_result(null);
    try std.testing.expectError(error.InvalidStateError, err);
}

fn testLoopDebug() !void {
    const allocator = std.testing.allocator;
    var loop = EventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.get_debug());
    loop.set_debug(true);
    try std.testing.expect(loop.get_debug());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "EventLoop create" {
    try testEventLoopCreate();
}

test "EventLoop close" {
    try testEventLoopClose();
}

test "EventLoop call_soon" {
    try testEventLoopCallSoon();
}

test "Handle cancel" {
    try testHandleCancel();
}

test "TimerHandle" {
    try testTimerHandle();
}

test "Future basic" {
    try testFutureBasic();
}

test "Future cancel" {
    try testFutureCancel();
}

test "Future set_result twice" {
    try testFutureSetResultTwice();
}

test "EventLoop debug" {
    try testLoopDebug();
}
