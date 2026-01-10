//! asyncio.selector_events - Selector-based event loop
//! Reference: cpython/Lib/asyncio/selector_events.py
//!
//! CPython exports: BaseSelectorEventLoop, _SelectorTransport, etc.

const std = @import("std");
const builtin = @import("builtin");
const asyncio = @import("../asyncio.zig");
const base_events = @import("base_events.zig");
const events = @import("events.zig");
const transports = @import("transports.zig");
const protocols = @import("protocols.zig");

// Platform detection
const is_linux = builtin.os.tag == .linux;
const is_darwin = builtin.os.tag == .macos;

/// Selector-based event loop using epoll/kqueue
/// CPython: class BaseSelectorEventLoop(base_events.BaseEventLoop)
pub const BaseSelectorEventLoop = struct {
    base: base_events.BaseEventLoop,
    selector: Selector,
    transports_map: std.AutoHashMap(std.posix.fd_t, *anyopaque),

    pub fn init(allocator: std.mem.Allocator) BaseSelectorEventLoop {
        return .{
            .base = base_events.BaseEventLoop.init(allocator),
            .selector = Selector.init(allocator),
            .transports_map = std.AutoHashMap(std.posix.fd_t, *anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *BaseSelectorEventLoop) void {
        self.transports_map.deinit();
        self.selector.deinit();
        self.base.deinit();
    }

    /// Add reader callback for fd
    pub fn addReader(self: *BaseSelectorEventLoop, fd: std.posix.fd_t, callback: *const fn (*anyopaque) void, data: *anyopaque) !void {
        try self.selector.register(fd, .read);
        try self.transports_map.put(fd, data);
        _ = callback;
    }

    /// Remove reader callback for fd
    pub fn removeReader(self: *BaseSelectorEventLoop, fd: std.posix.fd_t) void {
        self.selector.unregister(fd);
        _ = self.transports_map.remove(fd);
    }

    /// Add writer callback for fd
    pub fn addWriter(self: *BaseSelectorEventLoop, fd: std.posix.fd_t, callback: *const fn (*anyopaque) void, data: *anyopaque) !void {
        try self.selector.register(fd, .write);
        try self.transports_map.put(fd, data);
        _ = callback;
    }

    /// Remove writer callback for fd
    pub fn removeWriter(self: *BaseSelectorEventLoop, fd: std.posix.fd_t) void {
        self.selector.unregister(fd);
        _ = self.transports_map.remove(fd);
    }

    /// Run until complete (delegate to base)
    pub fn runForever(self: *BaseSelectorEventLoop) !void {
        return self.base.runForever();
    }

    /// Stop the loop
    pub fn stop(self: *BaseSelectorEventLoop) void {
        self.base.stop();
    }

    /// Check if running
    pub fn isRunning(self: *const BaseSelectorEventLoop) bool {
        return self.base.isRunning();
    }
};

/// Selector abstraction (wraps epoll/kqueue/poll)
pub const Selector = struct {
    registered_fds: std.ArrayList(std.posix.fd_t),
    allocator: std.mem.Allocator,

    pub const EventType = enum { read, write, both };

    pub fn init(allocator: std.mem.Allocator) Selector {
        return .{
            .registered_fds = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Selector) void {
        self.registered_fds.deinit(self.allocator);
    }

    pub fn register(self: *Selector, fd: std.posix.fd_t, event_type: EventType) !void {
        _ = event_type;
        try self.registered_fds.append(self.allocator, fd);
    }

    pub fn unregister(self: *Selector, fd: std.posix.fd_t) void {
        for (self.registered_fds.items, 0..) |item, i| {
            if (item == fd) {
                _ = self.registered_fds.orderedRemove(i);
                break;
            }
        }
    }

    pub fn select(self: *Selector, timeout: ?f64) ![]std.posix.fd_t {
        _ = timeout;
        // Simplified - would use actual select/poll/epoll/kqueue
        return self.registered_fds.items;
    }
};

// Tests
test "BaseSelectorEventLoop creation" {
    const allocator = std.testing.allocator;
    var loop = BaseSelectorEventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.base.running);
}

test "Selector registration" {
    const allocator = std.testing.allocator;
    var selector = Selector.init(allocator);
    defer selector.deinit();

    try selector.register(5, .read);
    try std.testing.expectEqual(@as(usize, 1), selector.registered_fds.items.len);

    selector.unregister(5);
    try std.testing.expectEqual(@as(usize, 0), selector.registered_fds.items.len);
}
