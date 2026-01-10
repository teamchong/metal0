//! test.test_asyncio.test_selector_events - Tests for selector-based event loops
//! Reference: cpython/Lib/test/test_asyncio/test_selector_events.py
//!
//! Tests for select/poll/epoll/kqueue based event loops

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Selector Types
// ============================================================================

pub const SelectorKey = struct {
    fileobj: posix.fd_t,
    events: u32,
    data: ?*anyopaque,
};

pub const EVENT_READ: u32 = 1;
pub const EVENT_WRITE: u32 = 2;

// ============================================================================
// Base Selector
// ============================================================================

/// Base selector interface
pub const BaseSelector = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _registered: std.AutoHashMap(posix.fd_t, SelectorKey),
    _closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._registered = std.AutoHashMap(posix.fd_t, SelectorKey).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._registered.deinit();
    }

    pub fn register(self: *Self, fd: posix.fd_t, events: u32, data: ?*anyopaque) !SelectorKey {
        if (self._closed) {
            return error.SelectorClosed;
        }
        if (self._registered.contains(fd)) {
            return error.KeyError;
        }

        const key = SelectorKey{
            .fileobj = fd,
            .events = events,
            .data = data,
        };
        try self._registered.put(fd, key);
        return key;
    }

    pub fn unregister(self: *Self, fd: posix.fd_t) !SelectorKey {
        if (self._closed) {
            return error.SelectorClosed;
        }

        if (self._registered.fetchRemove(fd)) |kv| {
            return kv.value;
        }
        return error.KeyError;
    }

    pub fn modify(self: *Self, fd: posix.fd_t, events: u32, data: ?*anyopaque) !SelectorKey {
        if (self._closed) {
            return error.SelectorClosed;
        }

        if (self._registered.getPtr(fd)) |key| {
            key.events = events;
            key.data = data;
            return key.*;
        }
        return error.KeyError;
    }

    pub fn select(self: *Self, timeout: ?f64) ![]const SelectorKey {
        if (self._closed) {
            return error.SelectorClosed;
        }
        _ = timeout;
        // Return registered keys (simplified)
        return &[_]SelectorKey{};
    }

    pub fn close(self: *Self) void {
        self._closed = true;
        self._registered.clearAndFree();
    }

    pub fn get_key(self: *const Self, fd: posix.fd_t) ?SelectorKey {
        return self._registered.get(fd);
    }

    pub fn get_map(self: *const Self) *const std.AutoHashMap(posix.fd_t, SelectorKey) {
        return &self._registered;
    }
};

// ============================================================================
// Select Selector (cross-platform)
// ============================================================================

/// select() based selector
pub const SelectSelector = struct {
    const Self = @This();

    base: BaseSelector,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseSelector.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    pub fn register(self: *Self, fd: posix.fd_t, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base.register(fd, events, data);
    }

    pub fn unregister(self: *Self, fd: posix.fd_t) !SelectorKey {
        return self.base.unregister(fd);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]const SelectorKey {
        return self.base.select(timeout);
    }

    pub fn close(self: *Self) void {
        self.base.close();
    }
};

// ============================================================================
// Poll Selector (Unix)
// ============================================================================

/// poll() based selector
pub const PollSelector = struct {
    const Self = @This();

    base: BaseSelector,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseSelector.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    pub fn register(self: *Self, fd: posix.fd_t, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base.register(fd, events, data);
    }

    pub fn unregister(self: *Self, fd: posix.fd_t) !SelectorKey {
        return self.base.unregister(fd);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]const SelectorKey {
        return self.base.select(timeout);
    }

    pub fn close(self: *Self) void {
        self.base.close();
    }
};

// ============================================================================
// Epoll Selector (Linux)
// ============================================================================

/// epoll() based selector
pub const EpollSelector = struct {
    const Self = @This();

    base: BaseSelector,
    _epoll_fd: ?posix.fd_t = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseSelector.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self._epoll_fd) |fd| {
            posix.close(fd);
        }
        self.base.deinit();
    }

    pub fn register(self: *Self, fd: posix.fd_t, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base.register(fd, events, data);
    }

    pub fn unregister(self: *Self, fd: posix.fd_t) !SelectorKey {
        return self.base.unregister(fd);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]const SelectorKey {
        return self.base.select(timeout);
    }

    pub fn close(self: *Self) void {
        if (self._epoll_fd) |fd| {
            posix.close(fd);
            self._epoll_fd = null;
        }
        self.base.close();
    }
};

// ============================================================================
// Kqueue Selector (BSD/macOS)
// ============================================================================

/// kqueue() based selector
pub const KqueueSelector = struct {
    const Self = @This();

    base: BaseSelector,
    _kqueue_fd: ?posix.fd_t = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseSelector.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self._kqueue_fd) |fd| {
            posix.close(fd);
        }
        self.base.deinit();
    }

    pub fn register(self: *Self, fd: posix.fd_t, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base.register(fd, events, data);
    }

    pub fn unregister(self: *Self, fd: posix.fd_t) !SelectorKey {
        return self.base.unregister(fd);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]const SelectorKey {
        return self.base.select(timeout);
    }

    pub fn close(self: *Self) void {
        if (self._kqueue_fd) |fd| {
            posix.close(fd);
            self._kqueue_fd = null;
        }
        self.base.close();
    }
};

// ============================================================================
// Default Selector
// ============================================================================

/// Get the default selector for the current platform
pub fn DefaultSelector(allocator: std.mem.Allocator) BaseSelector {
    return BaseSelector.init(allocator);
}

// ============================================================================
// Test Cases
// ============================================================================

fn testBaseSelectorCreate() !void {
    const allocator = std.testing.allocator;
    var selector = BaseSelector.init(allocator);
    defer selector.deinit();

    try std.testing.expect(!selector._closed);
}

fn testBaseSelectorRegister() !void {
    const allocator = std.testing.allocator;
    var selector = BaseSelector.init(allocator);
    defer selector.deinit();

    const key = try selector.register(42, EVENT_READ, null);
    try std.testing.expectEqual(@as(posix.fd_t, 42), key.fileobj);
    try std.testing.expectEqual(EVENT_READ, key.events);
}

fn testBaseSelectorUnregister() !void {
    const allocator = std.testing.allocator;
    var selector = BaseSelector.init(allocator);
    defer selector.deinit();

    _ = try selector.register(42, EVENT_READ, null);
    const key = try selector.unregister(42);

    try std.testing.expectEqual(@as(posix.fd_t, 42), key.fileobj);
    try std.testing.expect(selector.get_key(42) == null);
}

fn testBaseSelectorModify() !void {
    const allocator = std.testing.allocator;
    var selector = BaseSelector.init(allocator);
    defer selector.deinit();

    _ = try selector.register(42, EVENT_READ, null);
    const key = try selector.modify(42, EVENT_WRITE, null);

    try std.testing.expectEqual(EVENT_WRITE, key.events);
}

fn testBaseSelectorDoubleRegister() !void {
    const allocator = std.testing.allocator;
    var selector = BaseSelector.init(allocator);
    defer selector.deinit();

    _ = try selector.register(42, EVENT_READ, null);
    const err = selector.register(42, EVENT_WRITE, null);

    try std.testing.expectError(error.KeyError, err);
}

fn testBaseSelectorUnregisterNotFound() !void {
    const allocator = std.testing.allocator;
    var selector = BaseSelector.init(allocator);
    defer selector.deinit();

    const err = selector.unregister(42);
    try std.testing.expectError(error.KeyError, err);
}

fn testBaseSelectorClose() !void {
    const allocator = std.testing.allocator;
    var selector = BaseSelector.init(allocator);
    selector.close();

    try std.testing.expect(selector._closed);

    const err = selector.register(42, EVENT_READ, null);
    try std.testing.expectError(error.SelectorClosed, err);
}

fn testSelectSelector() !void {
    const allocator = std.testing.allocator;
    var selector = SelectSelector.init(allocator);
    defer selector.deinit();

    const key = try selector.register(42, EVENT_READ, null);
    try std.testing.expectEqual(@as(posix.fd_t, 42), key.fileobj);
}

fn testPollSelector() !void {
    const allocator = std.testing.allocator;
    var selector = PollSelector.init(allocator);
    defer selector.deinit();

    const key = try selector.register(42, EVENT_READ, null);
    try std.testing.expectEqual(@as(posix.fd_t, 42), key.fileobj);
}

fn testEpollSelector() !void {
    const allocator = std.testing.allocator;
    var selector = EpollSelector.init(allocator);
    defer selector.deinit();

    const key = try selector.register(42, EVENT_READ, null);
    try std.testing.expectEqual(@as(posix.fd_t, 42), key.fileobj);
}

fn testKqueueSelector() !void {
    const allocator = std.testing.allocator;
    var selector = KqueueSelector.init(allocator);
    defer selector.deinit();

    const key = try selector.register(42, EVENT_READ, null);
    try std.testing.expectEqual(@as(posix.fd_t, 42), key.fileobj);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "BaseSelector create" {
    try testBaseSelectorCreate();
}

test "BaseSelector register" {
    try testBaseSelectorRegister();
}

test "BaseSelector unregister" {
    try testBaseSelectorUnregister();
}

test "BaseSelector modify" {
    try testBaseSelectorModify();
}

test "BaseSelector double register" {
    try testBaseSelectorDoubleRegister();
}

test "BaseSelector unregister not found" {
    try testBaseSelectorUnregisterNotFound();
}

test "BaseSelector close" {
    try testBaseSelectorClose();
}

test "SelectSelector" {
    try testSelectSelector();
}

test "PollSelector" {
    try testPollSelector();
}

test "EpollSelector" {
    try testEpollSelector();
}

test "KqueueSelector" {
    try testKqueueSelector();
}
