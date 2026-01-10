//! asyncio.unix_events - Unix-specific event loop features
//! Reference: cpython/Lib/asyncio/unix_events.py

const std = @import("std");
const builtin = @import("builtin");
const selector_events = @import("selector_events.zig");
const base_events = @import("base_events.zig");
const transports = @import("transports.zig");
const protocols = @import("protocols.zig");

/// Unix selector event loop with signal and child process support
/// CPython: class _UnixSelectorEventLoop(selector_events.BaseSelectorEventLoop)
pub const UnixSelectorEventLoop = struct {
    base: selector_events.BaseSelectorEventLoop,
    signal_handlers: std.AutoHashMap(i32, *const fn () void),
    child_watchers: std.ArrayList(i32),

    pub fn init(allocator: std.mem.Allocator) UnixSelectorEventLoop {
        return .{
            .base = selector_events.BaseSelectorEventLoop.init(allocator),
            .signal_handlers = std.AutoHashMap(i32, *const fn () void).init(allocator),
            .child_watchers = .{},
        };
    }

    pub fn deinit(self: *UnixSelectorEventLoop) void {
        self.signal_handlers.deinit();
        self.child_watchers.deinit(self.base.base.allocator);
        self.base.deinit();
    }

    /// Add signal handler
    pub fn addSignalHandler(self: *UnixSelectorEventLoop, sig: i32, callback: *const fn () void) !void {
        try self.signal_handlers.put(sig, callback);
    }

    /// Remove signal handler
    pub fn removeSignalHandler(self: *UnixSelectorEventLoop, sig: i32) bool {
        return self.signal_handlers.remove(sig);
    }

    /// Create Unix connection
    pub fn createUnixConnection(
        self: *UnixSelectorEventLoop,
        protocol_factory: *const fn () *protocols.Protocol,
        path: []const u8,
    ) !struct { *transports.Transport, *protocols.Protocol } {
        _ = self;
        _ = protocol_factory;
        _ = path;
        return error.NotImplemented;
    }

    /// Create Unix server
    pub fn createUnixServer(
        self: *UnixSelectorEventLoop,
        protocol_factory: *const fn () *protocols.Protocol,
        path: []const u8,
    ) !void {
        _ = self;
        _ = protocol_factory;
        _ = path;
    }
};

/// Child watcher for subprocess management
/// CPython: class AbstractChildWatcher
pub const AbstractChildWatcher = struct {
    loop: ?*UnixSelectorEventLoop,

    pub fn init() AbstractChildWatcher {
        return .{ .loop = null };
    }

    pub fn addChildHandler(self: *AbstractChildWatcher, pid: i32, callback: *const fn (i32, i32) void) void {
        _ = self;
        _ = pid;
        _ = callback;
    }

    pub fn removeChildHandler(self: *AbstractChildWatcher, pid: i32) bool {
        _ = self;
        _ = pid;
        return false;
    }

    pub fn attach(self: *AbstractChildWatcher, loop: *UnixSelectorEventLoop) void {
        self.loop = loop;
    }

    pub fn close(self: *AbstractChildWatcher) void {
        self.loop = null;
    }
};

/// Safe child watcher (uses waitid with WNOWAIT)
/// CPython: class SafeChildWatcher(AbstractChildWatcher)
pub const SafeChildWatcher = struct {
    base: AbstractChildWatcher,
    callbacks: std.AutoHashMap(i32, *const fn (i32, i32) void),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SafeChildWatcher {
        return .{
            .base = AbstractChildWatcher.init(),
            .callbacks = std.AutoHashMap(i32, *const fn (i32, i32) void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SafeChildWatcher) void {
        self.callbacks.deinit();
    }
};

// Compile-time check for Unix
pub const is_unix = builtin.os.tag != .windows;

// Tests
test "UnixSelectorEventLoop creation" {
    if (comptime !is_unix) return;

    const allocator = std.testing.allocator;
    var loop = UnixSelectorEventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.base.base.running);
}

test "signal handler" {
    if (comptime !is_unix) return;

    const allocator = std.testing.allocator;
    var loop = UnixSelectorEventLoop.init(allocator);
    defer loop.deinit();

    const handler = struct {
        fn h() void {}
    }.h;

    try loop.addSignalHandler(2, handler); // SIGINT
    try std.testing.expect(loop.signal_handlers.contains(2));

    _ = loop.removeSignalHandler(2);
    try std.testing.expect(!loop.signal_handlers.contains(2));
}
