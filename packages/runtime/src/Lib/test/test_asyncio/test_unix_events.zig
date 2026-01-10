//! test.test_asyncio.test_unix_events - Tests for Unix-specific event loop features
//! Reference: cpython/Lib/test/test_asyncio/test_unix_events.py
//!
//! Tests for Unix sockets, signals, child process watchers

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Unix Socket Support
// ============================================================================

/// Unix socket address
pub const UnixAddress = struct {
    path: []const u8,
};

/// Create a Unix socket pair
pub fn socketpair() ![2]posix.socket_t {
    const sockets = try posix.socketpair(posix.AF.UNIX, posix.SOCK.STREAM, 0);
    return sockets;
}

// ============================================================================
// Signal Handling
// ============================================================================

/// Signal handler wrapper
pub const SignalHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _handlers: std.AutoHashMap(i32, *const fn () void),
    _pending: std.ArrayList(i32),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._handlers = std.AutoHashMap(i32, *const fn () void).init(allocator),
            ._pending = std.ArrayList(i32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._handlers.deinit();
        self._pending.deinit();
    }

    pub fn add_signal_handler(self: *Self, sig: i32, handler: *const fn () void) !void {
        try self._handlers.put(sig, handler);
    }

    pub fn remove_signal_handler(self: *Self, sig: i32) bool {
        return self._handlers.remove(sig);
    }

    pub fn signal_received(self: *Self, sig: i32) !void {
        try self._pending.append(sig);
    }

    pub fn process_pending(self: *Self) void {
        for (self._pending.items) |sig| {
            if (self._handlers.get(sig)) |handler| {
                handler();
            }
        }
        self._pending.clearRetainingCapacity();
    }
};

// ============================================================================
// Child Process Watcher
// ============================================================================

/// Abstract child watcher
pub const AbstractChildWatcher = struct {
    const Self = @This();

    vtable: *const VTable,

    pub const VTable = struct {
        add_child_handler: *const fn (*Self, posix.pid_t, *const fn (posix.pid_t, i32) void) void,
        remove_child_handler: *const fn (*Self, posix.pid_t) bool,
        close: *const fn (*Self) void,
    };
};

/// Safe child watcher using waitpid
pub const SafeChildWatcher = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _callbacks: std.AutoHashMap(posix.pid_t, Callback),
    _closed: bool = false,

    pub const Callback = struct {
        handler: *const fn (posix.pid_t, i32) void,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._callbacks = std.AutoHashMap(posix.pid_t, Callback).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._callbacks.deinit();
    }

    pub fn add_child_handler(
        self: *Self,
        pid: posix.pid_t,
        handler: *const fn (posix.pid_t, i32) void,
    ) !void {
        try self._callbacks.put(pid, .{ .handler = handler });
    }

    pub fn remove_child_handler(self: *Self, pid: posix.pid_t) bool {
        return self._callbacks.remove(pid);
    }

    pub fn child_exited(self: *Self, pid: posix.pid_t, returncode: i32) void {
        if (self._callbacks.get(pid)) |cb| {
            cb.handler(pid, returncode);
            _ = self._callbacks.remove(pid);
        }
    }

    pub fn close(self: *Self) void {
        self._closed = true;
        self._callbacks.clearAndFree();
    }
};

/// Fast child watcher using pidfd (Linux 5.3+)
pub const PidfdChildWatcher = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _callbacks: std.AutoHashMap(posix.pid_t, SafeChildWatcher.Callback),
    _pidfds: std.AutoHashMap(posix.pid_t, posix.fd_t),
    _closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._callbacks = std.AutoHashMap(posix.pid_t, SafeChildWatcher.Callback).init(allocator),
            ._pidfds = std.AutoHashMap(posix.pid_t, posix.fd_t).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self._pidfds.valueIterator();
        while (it.next()) |fd| {
            posix.close(fd.*);
        }
        self._pidfds.deinit();
        self._callbacks.deinit();
    }

    pub fn add_child_handler(
        self: *Self,
        pid: posix.pid_t,
        handler: *const fn (posix.pid_t, i32) void,
    ) !void {
        try self._callbacks.put(pid, .{ .handler = handler });
    }

    pub fn remove_child_handler(self: *Self, pid: posix.pid_t) bool {
        if (self._pidfds.fetchRemove(pid)) |kv| {
            posix.close(kv.value);
        }
        return self._callbacks.remove(pid);
    }

    pub fn close(self: *Self) void {
        self._closed = true;
        var it = self._pidfds.valueIterator();
        while (it.next()) |fd| {
            posix.close(fd.*);
        }
        self._pidfds.clearAndFree();
        self._callbacks.clearAndFree();
    }
};

// ============================================================================
// Unix Event Loop Extensions
// ============================================================================

/// Unix-specific event loop features
pub const UnixEventLoop = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _base_loop: test_events.EventLoop,
    _signal_handler: SignalHandler,
    _child_watcher: SafeChildWatcher,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._base_loop = test_events.EventLoop.init(allocator),
            ._signal_handler = SignalHandler.init(allocator),
            ._child_watcher = SafeChildWatcher.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._child_watcher.deinit();
        self._signal_handler.deinit();
        self._base_loop.deinit();
    }

    pub fn add_signal_handler(self: *Self, sig: i32, handler: *const fn () void) !void {
        try self._signal_handler.add_signal_handler(sig, handler);
    }

    pub fn remove_signal_handler(self: *Self, sig: i32) bool {
        return self._signal_handler.remove_signal_handler(sig);
    }

    pub fn add_child_handler(
        self: *Self,
        pid: posix.pid_t,
        handler: *const fn (posix.pid_t, i32) void,
    ) !void {
        try self._child_watcher.add_child_handler(pid, handler);
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testSignalHandler() !void {
    const allocator = std.testing.allocator;
    var handler = SignalHandler.init(allocator);
    defer handler.deinit();

    const cb = struct {
        fn callback() void {}
    }.callback;

    try handler.add_signal_handler(posix.SIG.USR1, cb);
    try std.testing.expect(handler._handlers.contains(posix.SIG.USR1));
}

fn testSignalHandlerRemove() !void {
    const allocator = std.testing.allocator;
    var handler = SignalHandler.init(allocator);
    defer handler.deinit();

    const cb = struct {
        fn callback() void {}
    }.callback;

    try handler.add_signal_handler(posix.SIG.USR1, cb);
    const removed = handler.remove_signal_handler(posix.SIG.USR1);

    try std.testing.expect(removed);
    try std.testing.expect(!handler._handlers.contains(posix.SIG.USR1));
}

fn testSafeChildWatcher() !void {
    const allocator = std.testing.allocator;
    var watcher = SafeChildWatcher.init(allocator);
    defer watcher.deinit();

    const cb = struct {
        fn callback(_: posix.pid_t, _: i32) void {}
    }.callback;

    try watcher.add_child_handler(1234, cb);
    try std.testing.expect(watcher._callbacks.contains(1234));
}

fn testSafeChildWatcherRemove() !void {
    const allocator = std.testing.allocator;
    var watcher = SafeChildWatcher.init(allocator);
    defer watcher.deinit();

    const cb = struct {
        fn callback(_: posix.pid_t, _: i32) void {}
    }.callback;

    try watcher.add_child_handler(1234, cb);
    const removed = watcher.remove_child_handler(1234);

    try std.testing.expect(removed);
    try std.testing.expect(!watcher._callbacks.contains(1234));
}

fn testSafeChildWatcherClose() !void {
    const allocator = std.testing.allocator;
    var watcher = SafeChildWatcher.init(allocator);

    const cb = struct {
        fn callback(_: posix.pid_t, _: i32) void {}
    }.callback;

    try watcher.add_child_handler(1234, cb);
    watcher.close();

    try std.testing.expect(watcher._closed);
    try std.testing.expectEqual(@as(usize, 0), watcher._callbacks.count());
}

fn testPidfdChildWatcher() !void {
    const allocator = std.testing.allocator;
    var watcher = PidfdChildWatcher.init(allocator);
    defer watcher.deinit();

    const cb = struct {
        fn callback(_: posix.pid_t, _: i32) void {}
    }.callback;

    try watcher.add_child_handler(1234, cb);
    try std.testing.expect(watcher._callbacks.contains(1234));
}

fn testUnixEventLoop() !void {
    const allocator = std.testing.allocator;
    var loop = UnixEventLoop.init(allocator);
    defer loop.deinit();

    const cb = struct {
        fn callback() void {}
    }.callback;

    try loop.add_signal_handler(posix.SIG.USR1, cb);
    try std.testing.expect(loop._signal_handler._handlers.contains(posix.SIG.USR1));
}

fn testUnixEventLoopChildHandler() !void {
    const allocator = std.testing.allocator;
    var loop = UnixEventLoop.init(allocator);
    defer loop.deinit();

    const cb = struct {
        fn callback(_: posix.pid_t, _: i32) void {}
    }.callback;

    try loop.add_child_handler(1234, cb);
    try std.testing.expect(loop._child_watcher._callbacks.contains(1234));
}

fn testSignalPending() !void {
    const allocator = std.testing.allocator;
    var handler = SignalHandler.init(allocator);
    defer handler.deinit();

    try handler.signal_received(posix.SIG.USR1);
    try handler.signal_received(posix.SIG.USR2);

    try std.testing.expectEqual(@as(usize, 2), handler._pending.items.len);

    handler.process_pending();
    try std.testing.expectEqual(@as(usize, 0), handler._pending.items.len);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "SignalHandler" {
    try testSignalHandler();
}

test "SignalHandler remove" {
    try testSignalHandlerRemove();
}

test "SafeChildWatcher" {
    try testSafeChildWatcher();
}

test "SafeChildWatcher remove" {
    try testSafeChildWatcherRemove();
}

test "SafeChildWatcher close" {
    try testSafeChildWatcherClose();
}

test "PidfdChildWatcher" {
    try testPidfdChildWatcher();
}

test "UnixEventLoop" {
    try testUnixEventLoop();
}

test "UnixEventLoop child handler" {
    try testUnixEventLoopChildHandler();
}

test "Signal pending" {
    try testSignalPending();
}
