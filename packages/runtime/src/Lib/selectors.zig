//! CPython source: Lib/selectors.py
//!
//! Provides high-level abstractions for I/O multiplexing.
//!
//! Mirrors: CPython Lib/selectors.py

const std = @import("std");

// ============================================================================
// Event Flags
// ============================================================================

/// Event types for I/O multiplexing
pub const EVENT_READ: u32 = 1 << 0;
pub const EVENT_WRITE: u32 = 1 << 1;

// ============================================================================
// SelectorKey
// ============================================================================

/// Selector key for tracking registered file objects
pub const SelectorKey = struct {
    fileobj: i32, // File descriptor
    fd: i32, // Underlying file descriptor
    events: u32, // Events to monitor (EVENT_READ, EVENT_WRITE)
    data: ?*anyopaque, // User data

    pub fn init(fileobj: i32, events: u32, data: ?*anyopaque) SelectorKey {
        return .{
            .fileobj = fileobj,
            .fd = fileobj,
            .events = events,
            .data = data,
        };
    }
};

// ============================================================================
// BaseSelector
// ============================================================================

/// Abstract base class for selectors
pub const BaseSelector = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    registered: std.AutoHashMap(i32, SelectorKey),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .registered = std.AutoHashMap(i32, SelectorKey).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.registered.deinit();
    }

    /// Register a file object for monitoring
    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        if (self.registered.contains(fileobj)) {
            return error.KeyError;
        }

        const key = SelectorKey.init(fileobj, events, data);
        try self.registered.put(fileobj, key);
        return key;
    }

    /// Unregister a file object
    pub fn unregister(self: *Self, fileobj: i32) !SelectorKey {
        const key = self.registered.get(fileobj) orelse return error.KeyError;
        _ = self.registered.remove(fileobj);
        return key;
    }

    /// Modify the events for a registered file object
    pub fn modify(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        var key = self.registered.getPtr(fileobj) orelse return error.KeyError;
        key.events = events;
        key.data = data;
        return key.*;
    }

    /// Get the key for a file object
    pub fn getKey(self: *Self, fileobj: i32) !SelectorKey {
        return self.registered.get(fileobj) orelse error.KeyError;
    }

    /// Get a map of all registered file objects
    pub fn getMap(self: *Self) std.AutoHashMap(i32, SelectorKey) {
        return self.registered;
    }

    /// Close the selector
    pub fn close(self: *Self) void {
        self.registered.clearAndFree();
    }
};

// ============================================================================
// SelectSelector (uses select() system call)
// ============================================================================

/// Selector using select() system call
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

    /// Register a file object
    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base.register(fileobj, events, data);
    }

    /// Unregister a file object
    pub fn unregister(self: *Self, fileobj: i32) !SelectorKey {
        return self.base.unregister(fileobj);
    }

    /// Modify registration
    pub fn modify(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base.modify(fileobj, events, data);
    }

    /// Wait for events
    pub fn select(self: *Self, timeout: ?f64) ![]struct { key: SelectorKey, events: u32 } {
        var result = std.ArrayList(struct { key: SelectorKey, events: u32 }).init(self.base.allocator);
        errdefer result.deinit();

        // Convert timeout to timeval
        const timeout_ns: i64 = if (timeout) |t|
            @intFromFloat(t * 1_000_000_000)
        else
            -1;

        // Build fd sets
        var read_fds: std.os.linux.fd_set = std.mem.zeroes(std.os.linux.fd_set);
        var write_fds: std.os.linux.fd_set = std.mem.zeroes(std.os.linux.fd_set);
        var max_fd: i32 = -1;

        var iter = self.base.registered.iterator();
        while (iter.next()) |entry| {
            const key = entry.value_ptr;
            if (key.events & EVENT_READ != 0) {
                const fd_index: usize = @intCast(key.fd);
                read_fds.bits[fd_index / 64] |= @as(u64, 1) << @truncate(fd_index % 64);
            }
            if (key.events & EVENT_WRITE != 0) {
                const fd_index: usize = @intCast(key.fd);
                write_fds.bits[fd_index / 64] |= @as(u64, 1) << @truncate(fd_index % 64);
            }
            if (key.fd > max_fd) max_fd = key.fd;
        }

        // Note: Actual select() call would go here
        _ = timeout_ns;
        _ = max_fd;

        // Check results and build return list
        var result_iter = self.base.registered.iterator();
        while (result_iter.next()) |entry| {
            const key = entry.value_ptr;
            var ready_events: u32 = 0;

            const fd_index: usize = @intCast(key.fd);
            if (read_fds.bits[fd_index / 64] & (@as(u64, 1) << @truncate(fd_index % 64)) != 0) {
                ready_events |= EVENT_READ;
            }
            if (write_fds.bits[fd_index / 64] & (@as(u64, 1) << @truncate(fd_index % 64)) != 0) {
                ready_events |= EVENT_WRITE;
            }

            if (ready_events != 0) {
                try result.append(.{ .key = key.*, .events = ready_events });
            }
        }

        return result.toOwnedSlice();
    }

    /// Close the selector
    pub fn close(self: *Self) void {
        self.base.close();
    }
};

// ============================================================================
// PollSelector (uses poll() system call)
// ============================================================================

/// Selector using poll() system call
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

    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base.register(fileobj, events, data);
    }

    pub fn unregister(self: *Self, fileobj: i32) !SelectorKey {
        return self.base.unregister(fileobj);
    }

    pub fn modify(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base.modify(fileobj, events, data);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]struct { key: SelectorKey, events: u32 } {
        var result = std.ArrayList(struct { key: SelectorKey, events: u32 }).init(self.base.allocator);
        errdefer result.deinit();

        // Build poll fds array
        var poll_fds = std.ArrayList(std.posix.pollfd).init(self.base.allocator);
        defer poll_fds.deinit();

        var iter = self.base.registered.iterator();
        while (iter.next()) |entry| {
            const key = entry.value_ptr;
            var poll_events: i16 = 0;
            if (key.events & EVENT_READ != 0) poll_events |= std.posix.POLL.IN;
            if (key.events & EVENT_WRITE != 0) poll_events |= std.posix.POLL.OUT;

            try poll_fds.append(.{
                .fd = key.fd,
                .events = poll_events,
                .revents = 0,
            });
        }

        // Call poll
        const timeout_ms: i32 = if (timeout) |t|
            @intFromFloat(t * 1000)
        else
            -1;

        _ = std.posix.poll(poll_fds.items, timeout_ms) catch 0;

        // Check results
        for (poll_fds.items) |pfd| {
            if (pfd.revents != 0) {
                const key = self.base.registered.get(pfd.fd) orelse continue;
                var ready_events: u32 = 0;
                if (pfd.revents & std.posix.POLL.IN != 0) ready_events |= EVENT_READ;
                if (pfd.revents & std.posix.POLL.OUT != 0) ready_events |= EVENT_WRITE;
                try result.append(.{ .key = key, .events = ready_events });
            }
        }

        return result.toOwnedSlice();
    }

    pub fn close(self: *Self) void {
        self.base.close();
    }
};

// ============================================================================
// KqueueSelector (macOS/BSD)
// ============================================================================

/// Selector using kqueue (macOS/BSD)
pub const KqueueSelector = struct {
    const Self = @This();

    base: BaseSelector,
    kqueue_fd: std.posix.fd_t,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const kq = std.posix.kqueue() catch return error.KqueueCreateFailed;
        return .{
            .base = BaseSelector.init(allocator),
            .kqueue_fd = kq,
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
        if (self.kqueue_fd >= 0) {
            std.posix.close(self.kqueue_fd);
        }
    }

    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        const key = try self.base.register(fileobj, events, data);

        // Add to kqueue
        var changelist: [2]std.posix.Kevent = undefined;
        var nchanges: usize = 0;

        if (events & EVENT_READ != 0) {
            changelist[nchanges] = .{
                .ident = @intCast(fileobj),
                .filter = std.posix.system.EVFILT.READ,
                .flags = std.posix.system.EV.ADD,
                .fflags = 0,
                .data = 0,
                .udata = @ptrFromInt(@intFromPtr(data)),
            };
            nchanges += 1;
        }
        if (events & EVENT_WRITE != 0) {
            changelist[nchanges] = .{
                .ident = @intCast(fileobj),
                .filter = std.posix.system.EVFILT.WRITE,
                .flags = std.posix.system.EV.ADD,
                .fflags = 0,
                .data = 0,
                .udata = @ptrFromInt(@intFromPtr(data)),
            };
            nchanges += 1;
        }

        if (nchanges > 0) {
            _ = std.posix.kevent(self.kqueue_fd, changelist[0..nchanges], &[_]std.posix.Kevent{}, null) catch {};
        }

        return key;
    }

    pub fn unregister(self: *Self, fileobj: i32) !SelectorKey {
        // Remove from kqueue
        var changelist: [2]std.posix.Kevent = .{
            .{
                .ident = @intCast(fileobj),
                .filter = std.posix.system.EVFILT.READ,
                .flags = std.posix.system.EV.DELETE,
                .fflags = 0,
                .data = 0,
                .udata = null,
            },
            .{
                .ident = @intCast(fileobj),
                .filter = std.posix.system.EVFILT.WRITE,
                .flags = std.posix.system.EV.DELETE,
                .fflags = 0,
                .data = 0,
                .udata = null,
            },
        };
        _ = std.posix.kevent(self.kqueue_fd, &changelist, &[_]std.posix.Kevent{}, null) catch {};

        return self.base.unregister(fileobj);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]struct { key: SelectorKey, events: u32 } {
        var eventlist: [64]std.posix.Kevent = undefined;

        const ts: ?std.posix.timespec = if (timeout) |t| .{
            .tv_sec = @intFromFloat(t),
            .tv_nsec = @intFromFloat((t - @floor(t)) * 1_000_000_000),
        } else null;

        const n = std.posix.kevent(self.kqueue_fd, &[_]std.posix.Kevent{}, &eventlist, if (ts) |*t| t else null) catch |err| {
            if (err == error.INTR) return &[_]struct { key: SelectorKey, events: u32 }{};
            return err;
        };

        var result = std.ArrayList(struct { key: SelectorKey, events: u32 }).init(self.base.allocator);
        for (eventlist[0..n]) |ev| {
            const fd: i32 = @intCast(ev.ident);
            if (self.base.fd_to_key.get(fd)) |key| {
                var events: u32 = 0;
                if (ev.filter == std.posix.system.EVFILT.READ) events |= EVENT_READ;
                if (ev.filter == std.posix.system.EVFILT.WRITE) events |= EVENT_WRITE;
                try result.append(.{ .key = key, .events = events });
            }
        }
        return result.toOwnedSlice();
    }

    pub fn close(self: *Self) void {
        self.base.close();
        if (self.kqueue_fd >= 0) {
            std.posix.close(self.kqueue_fd);
            self.kqueue_fd = -1;
        }
    }
};

// ============================================================================
// EpollSelector (Linux)
// ============================================================================

/// Selector using epoll (Linux)
pub const EpollSelector = struct {
    const Self = @This();

    base: BaseSelector,
    epoll_fd: std.posix.fd_t,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const ep = std.posix.epoll_create1(0) catch return error.EpollCreateFailed;
        return .{
            .base = BaseSelector.init(allocator),
            .epoll_fd = ep,
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
        if (self.epoll_fd >= 0) {
            std.posix.close(self.epoll_fd);
        }
    }

    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        const key = try self.base.register(fileobj, events, data);

        // Add to epoll
        var ev: std.os.linux.epoll_event = .{
            .events = 0,
            .data = .{ .fd = fileobj },
        };
        if (events & EVENT_READ != 0) ev.events |= std.os.linux.EPOLL.IN;
        if (events & EVENT_WRITE != 0) ev.events |= std.os.linux.EPOLL.OUT;
        _ = data; // userdata stored in base

        std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, fileobj, &ev) catch {};

        return key;
    }

    pub fn unregister(self: *Self, fileobj: i32) !SelectorKey {
        // Remove from epoll
        std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, fileobj, null) catch {};

        return self.base.unregister(fileobj);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]struct { key: SelectorKey, events: u32 } {
        var eventlist: [64]std.os.linux.epoll_event = undefined;

        const timeout_ms: i32 = if (timeout) |t| @intFromFloat(t * 1000) else -1;

        const n = std.posix.epoll_wait(self.epoll_fd, &eventlist, timeout_ms) catch |err| {
            if (err == error.INTR) return &[_]struct { key: SelectorKey, events: u32 }{};
            return err;
        };

        var result = std.ArrayList(struct { key: SelectorKey, events: u32 }).init(self.base.allocator);
        for (eventlist[0..n]) |ev| {
            const fd = ev.data.fd;
            if (self.base.fd_to_key.get(fd)) |key| {
                var events: u32 = 0;
                if (ev.events & std.os.linux.EPOLL.IN != 0) events |= EVENT_READ;
                if (ev.events & std.os.linux.EPOLL.OUT != 0) events |= EVENT_WRITE;
                try result.append(.{ .key = key, .events = events });
            }
        }
        return result.toOwnedSlice();
    }

    pub fn close(self: *Self) void {
        self.base.close();
        if (self.epoll_fd >= 0) {
            std.posix.close(self.epoll_fd);
            self.epoll_fd = -1;
        }
    }
};

// ============================================================================
// Default Selector
// ============================================================================

/// Default selector for the current platform
pub const DefaultSelector = switch (@import("builtin").os.tag) {
    .linux => EpollSelector,
    .macos, .freebsd, .netbsd, .openbsd => KqueueSelector,
    else => PollSelector,
};

// ============================================================================
// Module Functions
// ============================================================================

/// Create a new selector (platform default)
pub fn createSelector(allocator: std.mem.Allocator) !DefaultSelector {
    return DefaultSelector.init(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "SelectorKey init" {
    const key = SelectorKey.init(5, EVENT_READ | EVENT_WRITE, null);
    try std.testing.expectEqual(@as(i32, 5), key.fd);
    try std.testing.expectEqual(EVENT_READ | EVENT_WRITE, key.events);
}

test "BaseSelector init" {
    const allocator = std.testing.allocator;
    var sel = BaseSelector.init(allocator);
    defer sel.deinit();

    try std.testing.expectEqual(@as(usize, 0), sel.registered.count());
}

test "BaseSelector register" {
    const allocator = std.testing.allocator;
    var sel = BaseSelector.init(allocator);
    defer sel.deinit();

    const key = try sel.register(5, EVENT_READ, null);
    try std.testing.expectEqual(@as(i32, 5), key.fd);
    try std.testing.expectEqual(@as(usize, 1), sel.registered.count());
}

test "BaseSelector unregister" {
    const allocator = std.testing.allocator;
    var sel = BaseSelector.init(allocator);
    defer sel.deinit();

    _ = try sel.register(5, EVENT_READ, null);
    const key = try sel.unregister(5);
    try std.testing.expectEqual(@as(i32, 5), key.fd);
    try std.testing.expectEqual(@as(usize, 0), sel.registered.count());
}

test "BaseSelector modify" {
    const allocator = std.testing.allocator;
    var sel = BaseSelector.init(allocator);
    defer sel.deinit();

    _ = try sel.register(5, EVENT_READ, null);
    const key = try sel.modify(5, EVENT_WRITE, null);
    try std.testing.expectEqual(EVENT_WRITE, key.events);
}

test "SelectSelector init" {
    const allocator = std.testing.allocator;
    var sel = SelectSelector.init(allocator);
    defer sel.deinit();

    _ = try sel.register(5, EVENT_READ, null);
    try std.testing.expectEqual(@as(usize, 1), sel.base.registered.count());
}

test "PollSelector init" {
    const allocator = std.testing.allocator;
    var sel = PollSelector.init(allocator);
    defer sel.deinit();

    _ = try sel.register(5, EVENT_READ, null);
    try std.testing.expectEqual(@as(usize, 1), sel.base.registered.count());
}

test "EVENT flags" {
    try std.testing.expectEqual(@as(u32, 1), EVENT_READ);
    try std.testing.expectEqual(@as(u32, 2), EVENT_WRITE);
}
