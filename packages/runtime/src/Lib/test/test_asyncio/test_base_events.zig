//! test.test_asyncio.test_base_events - Tests for base event loop
//! Reference: cpython/Lib/test/test_asyncio/test_base_events.py
//!
//! Tests for BaseEventLoop implementation details

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// BaseEventLoop Tests - Timing
// ============================================================================

/// Test time tracking in event loop
pub const TimeTracker = struct {
    const Self = @This();

    start_time: i64,
    _time_offset: f64 = 0,

    pub fn init() Self {
        return .{
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn time(self: *const Self) f64 {
        const elapsed_ms = std.time.milliTimestamp() - self.start_time;
        return @as(f64, @floatFromInt(elapsed_ms)) / 1000.0 + self._time_offset;
    }

    pub fn advance(self: *Self, seconds: f64) void {
        self._time_offset += seconds;
    }
};

// ============================================================================
// BaseEventLoop Tests - Callbacks
// ============================================================================

/// Callback tracker for testing
pub const CallbackTracker = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    calls: std.ArrayList(CallRecord),

    pub const CallRecord = struct {
        name: []const u8,
        time: f64,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .calls = std.ArrayList(CallRecord).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.calls.deinit();
    }

    pub fn record(self: *Self, name: []const u8, time_val: f64) !void {
        try self.calls.append(.{
            .name = name,
            .time = time_val,
        });
    }

    pub fn count(self: *const Self) usize {
        return self.calls.items.len;
    }

    pub fn clear(self: *Self) void {
        self.calls.clearRetainingCapacity();
    }
};

// ============================================================================
// BaseEventLoop Tests - Exception Handling
// ============================================================================

/// Exception handler for testing
pub const ExceptionHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    exceptions: std.ArrayList(ExceptionRecord),
    default_handler_called: bool = false,

    pub const ExceptionRecord = struct {
        message: []const u8,
        context: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .exceptions = std.ArrayList(ExceptionRecord).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.exceptions.deinit();
    }

    pub fn handle(self: *Self, message: []const u8, context: ?[]const u8) !void {
        try self.exceptions.append(.{
            .message = message,
            .context = context,
        });
    }

    pub fn call_default(self: *Self) void {
        self.default_handler_called = true;
    }
};

// ============================================================================
// BaseEventLoop Tests - Debug Mode
// ============================================================================

/// Debug mode helper
pub const DebugHelper = struct {
    const Self = @This();

    _slow_callback_duration: f64 = 0.1,
    _debug: bool = false,
    slow_callbacks: std.ArrayList(SlowCallback),
    allocator: std.mem.Allocator,

    pub const SlowCallback = struct {
        name: []const u8,
        duration: f64,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .slow_callbacks = std.ArrayList(SlowCallback).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.slow_callbacks.deinit();
    }

    pub fn set_debug(self: *Self, enabled: bool) void {
        self._debug = enabled;
    }

    pub fn get_debug(self: *const Self) bool {
        return self._debug;
    }

    pub fn set_slow_callback_duration(self: *Self, duration: f64) void {
        self._slow_callback_duration = duration;
    }

    pub fn record_slow_callback(self: *Self, name: []const u8, duration: f64) !void {
        if (self._debug and duration > self._slow_callback_duration) {
            try self.slow_callbacks.append(.{
                .name = name,
                .duration = duration,
            });
        }
    }
};

// ============================================================================
// BaseEventLoop Tests - Socket Operations
// ============================================================================

/// Mock socket for testing
pub const MockSocket = struct {
    const Self = @This();

    family: i32 = posix.AF.INET,
    sock_type: i32 = posix.SOCK.STREAM,
    proto: i32 = 0,
    _blocking: bool = true,
    _bound: bool = false,
    _listening: bool = false,
    _connected: bool = false,
    _closed: bool = false,
    _recv_buffer: std.ArrayList(u8),
    _send_buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._recv_buffer = std.ArrayList(u8).init(allocator),
            ._send_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._recv_buffer.deinit();
        self._send_buffer.deinit();
    }

    pub fn setblocking(self: *Self, blocking: bool) void {
        self._blocking = blocking;
    }

    pub fn bind(self: *Self, _: []const u8, _: u16) !void {
        self._bound = true;
    }

    pub fn listen(self: *Self, _: i32) !void {
        if (!self._bound) {
            return error.NotBound;
        }
        self._listening = true;
    }

    pub fn connect(self: *Self, _: []const u8, _: u16) !void {
        self._connected = true;
    }

    pub fn send(self: *Self, data: []const u8) !usize {
        if (!self._connected) {
            return error.NotConnected;
        }
        try self._send_buffer.appendSlice(data);
        return data.len;
    }

    pub fn recv(self: *Self, buf: []u8) !usize {
        const to_read = @min(buf.len, self._recv_buffer.items.len);
        @memcpy(buf[0..to_read], self._recv_buffer.items[0..to_read]);
        return to_read;
    }

    pub fn close(self: *Self) void {
        self._closed = true;
    }

    /// Feed data for testing recv
    pub fn feed_recv_data(self: *Self, data: []const u8) !void {
        try self._recv_buffer.appendSlice(data);
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testTimeTracker() !void {
    var tracker = TimeTracker.init();
    const t1 = tracker.time();

    tracker.advance(1.0);
    const t2 = tracker.time();

    try std.testing.expect(t2 >= t1 + 1.0);
}

fn testCallbackTracker() !void {
    const allocator = std.testing.allocator;
    var tracker = CallbackTracker.init(allocator);
    defer tracker.deinit();

    try tracker.record("callback1", 0.0);
    try tracker.record("callback2", 1.0);

    try std.testing.expectEqual(@as(usize, 2), tracker.count());

    tracker.clear();
    try std.testing.expectEqual(@as(usize, 0), tracker.count());
}

fn testExceptionHandler() !void {
    const allocator = std.testing.allocator;
    var handler = ExceptionHandler.init(allocator);
    defer handler.deinit();

    try handler.handle("test error", "context");
    try std.testing.expectEqual(@as(usize, 1), handler.exceptions.items.len);

    handler.call_default();
    try std.testing.expect(handler.default_handler_called);
}

fn testDebugHelper() !void {
    const allocator = std.testing.allocator;
    var helper = DebugHelper.init(allocator);
    defer helper.deinit();

    try std.testing.expect(!helper.get_debug());
    helper.set_debug(true);
    try std.testing.expect(helper.get_debug());

    try helper.record_slow_callback("slow_cb", 0.2);
    try std.testing.expectEqual(@as(usize, 1), helper.slow_callbacks.items.len);
}

fn testMockSocket() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try std.testing.expect(!sock._bound);
    try sock.bind("0.0.0.0", 8080);
    try std.testing.expect(sock._bound);

    try sock.listen(5);
    try std.testing.expect(sock._listening);
}

fn testMockSocketConnect() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try std.testing.expect(!sock._connected);
    try sock.connect("127.0.0.1", 8080);
    try std.testing.expect(sock._connected);
}

fn testMockSocketSendRecv() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try sock.connect("127.0.0.1", 8080);

    const sent = try sock.send("hello");
    try std.testing.expectEqual(@as(usize, 5), sent);

    try sock.feed_recv_data("world");
    var buf: [10]u8 = undefined;
    const received = try sock.recv(&buf);
    try std.testing.expectEqual(@as(usize, 5), received);
}

fn testMockSocketBlocking() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try std.testing.expect(sock._blocking);
    sock.setblocking(false);
    try std.testing.expect(!sock._blocking);
}

fn testMockSocketClose() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try std.testing.expect(!sock._closed);
    sock.close();
    try std.testing.expect(sock._closed);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "TimeTracker" {
    try testTimeTracker();
}

test "CallbackTracker" {
    try testCallbackTracker();
}

test "ExceptionHandler" {
    try testExceptionHandler();
}

test "DebugHelper" {
    try testDebugHelper();
}

test "MockSocket basic" {
    try testMockSocket();
}

test "MockSocket connect" {
    try testMockSocketConnect();
}

test "MockSocket send/recv" {
    try testMockSocketSendRecv();
}

test "MockSocket blocking" {
    try testMockSocketBlocking();
}

test "MockSocket close" {
    try testMockSocketClose();
}
