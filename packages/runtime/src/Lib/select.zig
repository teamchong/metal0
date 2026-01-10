//! Python select module - I/O multiplexing
//!
//! Provides access to the select(), poll(), and platform-specific I/O
//! multiplexing mechanisms (epoll on Linux, kqueue on macOS/BSD).

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// File descriptor type (platform-independent)
pub const fd_t = std.posix.fd_t;

// ============================================================================
// Constants
// ============================================================================

/// Pipe constant for subprocess integration
pub const PIPE: i32 = -1;

/// poll() event flags
pub const POLLIN: i16 = 0x0001; // Data available for reading
pub const POLLPRI: i16 = 0x0002; // Urgent data available
pub const POLLOUT: i16 = 0x0004; // Writing possible
pub const POLLERR: i16 = 0x0008; // Error condition
pub const POLLHUP: i16 = 0x0010; // Hung up
pub const POLLNVAL: i16 = 0x0020; // Invalid request (fd not open)

// Platform-specific constants
pub const POLLRDNORM: i16 = if (builtin.os.tag == .linux) 0x0040 else 0x0040;
pub const POLLRDBAND: i16 = if (builtin.os.tag == .linux) 0x0080 else 0x0080;
pub const POLLWRNORM: i16 = if (builtin.os.tag == .linux) 0x0100 else 0x0004;
pub const POLLWRBAND: i16 = if (builtin.os.tag == .linux) 0x0200 else 0x0100;

// ============================================================================
// Errors
// ============================================================================

pub const SelectError = error{
    BadFileDescriptor,
    InvalidTimeout,
    Interrupted,
    OutOfMemory,
    SystemResources,
};

// ============================================================================
// select() - Core I/O multiplexing function
// ============================================================================

/// Python-compatible select() function
///
/// Waits until one or more file descriptors are ready for I/O.
/// Uses poll() internally as fd_set is not available in Zig 0.15.
///
/// Args:
///   allocator: Memory allocator for result arrays
///   rlist: File descriptors to check for readability
///   wlist: File descriptors to check for writability
///   xlist: File descriptors to check for exceptional conditions
///   timeout: Maximum wait time in seconds (null = block indefinitely)
///
/// Returns:
///   Tuple of (readable fds, writable fds, exceptional fds)
pub fn select(
    allocator: Allocator,
    rlist: []const fd_t,
    wlist: []const fd_t,
    xlist: []const fd_t,
    timeout: ?f64,
) SelectError!struct { r: []fd_t, w: []fd_t, x: []fd_t } {
    // Validate timeout
    if (timeout) |t| {
        if (t < 0) return SelectError.InvalidTimeout;
    }

    // Use poll() to implement select() - more portable in Zig 0.15
    const total_fds = rlist.len + wlist.len + xlist.len;
    if (total_fds == 0) {
        // No fds to wait on - just sleep if timeout specified
        if (timeout) |t| {
            if (t > 0) {
                std.Thread.sleep(@as(u64, @intFromFloat(t * 1_000_000_000)));
            }
        }
        return .{
            .r = allocator.alloc(fd_t, 0) catch return SelectError.OutOfMemory,
            .w = allocator.alloc(fd_t, 0) catch return SelectError.OutOfMemory,
            .x = allocator.alloc(fd_t, 0) catch return SelectError.OutOfMemory,
        };
    }

    // Build poll fd array
    var poll_fds = allocator.alloc(std.posix.pollfd, total_fds) catch return SelectError.OutOfMemory;
    defer allocator.free(poll_fds);

    var idx: usize = 0;
    for (rlist) |fd| {
        poll_fds[idx] = .{ .fd = fd, .events = POLLIN, .revents = 0 };
        idx += 1;
    }
    for (wlist) |fd| {
        poll_fds[idx] = .{ .fd = fd, .events = POLLOUT, .revents = 0 };
        idx += 1;
    }
    for (xlist) |fd| {
        poll_fds[idx] = .{ .fd = fd, .events = POLLPRI, .revents = 0 };
        idx += 1;
    }

    // Convert timeout to milliseconds
    const timeout_ms: i32 = if (timeout) |t|
        @intFromFloat(t * 1000)
    else
        -1; // Block indefinitely

    // Call poll()
    _ = std.posix.poll(poll_fds, timeout_ms) catch {
        return SelectError.SystemResources;
    };

    // Build result arrays
    var r_result: std.ArrayList(fd_t) = .empty;
    var w_result: std.ArrayList(fd_t) = .empty;
    var x_result: std.ArrayList(fd_t) = .empty;

    idx = 0;
    for (rlist) |fd| {
        if (poll_fds[idx].revents & POLLIN != 0) {
            r_result.append(allocator, fd) catch return SelectError.OutOfMemory;
        }
        idx += 1;
    }
    for (wlist) |fd| {
        if (poll_fds[idx].revents & POLLOUT != 0) {
            w_result.append(allocator, fd) catch return SelectError.OutOfMemory;
        }
        idx += 1;
    }
    for (xlist) |fd| {
        if (poll_fds[idx].revents & (POLLERR | POLLHUP | POLLNVAL) != 0) {
            x_result.append(allocator, fd) catch return SelectError.OutOfMemory;
        }
        idx += 1;
    }

    return .{
        .r = r_result.toOwnedSlice(allocator) catch return SelectError.OutOfMemory,
        .w = w_result.toOwnedSlice(allocator) catch return SelectError.OutOfMemory,
        .x = x_result.toOwnedSlice(allocator) catch return SelectError.OutOfMemory,
    };
}

// ============================================================================
// poll() - Event-based I/O multiplexing
// ============================================================================

/// pollfd structure for poll()
pub const pollfd = extern struct {
    fd: fd_t,
    events: i16,
    revents: i16,
};

/// Result from Poll.poll()
pub const PollResult = struct {
    fd: fd_t,
    events: i16,
};

/// poll() object - manages a set of file descriptors for polling
pub const Poll = struct {
    fds: std.ArrayList(std.posix.pollfd) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Poll {
        return .{
            .fds = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Poll) void {
        self.fds.deinit(self.allocator);
    }

    /// Register a file descriptor with the poll object
    pub fn register(self: *Poll, fd: fd_t, eventmask: i16) !void {
        // Check if fd already registered
        for (self.fds.items) |*pfd| {
            if (pfd.fd == fd) {
                pfd.events = eventmask;
                return;
            }
        }
        // Add new entry
        try self.fds.append(self.allocator, .{
            .fd = fd,
            .events = eventmask,
            .revents = 0,
        });
    }

    /// Modify events for a registered file descriptor
    pub fn modify(self: *Poll, fd: fd_t, eventmask: i16) !void {
        for (self.fds.items) |*pfd| {
            if (pfd.fd == fd) {
                pfd.events = eventmask;
                return;
            }
        }
        return error.FileDescriptorNotFound;
    }

    /// Unregister a file descriptor
    pub fn unregister(self: *Poll, fd: fd_t) !void {
        for (self.fds.items, 0..) |pfd, i| {
            if (pfd.fd == fd) {
                _ = self.fds.orderedRemove(i);
                return;
            }
        }
        return error.FileDescriptorNotFound;
    }

    /// Poll for events
    ///
    /// Args:
    ///   timeout_ms: Timeout in milliseconds (null = block indefinitely, 0 = return immediately)
    ///
    /// Returns:
    ///   List of (fd, revents) tuples for fds with events
    pub fn poll(self: *Poll, timeout_ms: ?i32) ![]PollResult {
        const timeout: i32 = timeout_ms orelse -1;

        // Reset revents
        for (self.fds.items) |*pfd| {
            pfd.revents = 0;
        }

        // Call poll()
        _ = std.posix.poll(self.fds.items, timeout) catch {
            return error.SystemResources;
        };

        // Collect results
        var results: std.ArrayList(PollResult) = .empty;
        for (self.fds.items) |pfd| {
            if (pfd.revents != 0) {
                try results.append(self.allocator, .{ .fd = pfd.fd, .events = pfd.revents });
            }
        }

        return results.toOwnedSlice(self.allocator);
    }
};

/// Create a new poll object (Python: select.poll())
pub fn pollCreate(allocator: Allocator) Poll {
    return Poll.init(allocator);
}

// ============================================================================
// Platform-specific: epoll (Linux)
// ============================================================================

pub const Epoll = struct {
    epfd: fd_t,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Epoll {
        if (builtin.os.tag != .linux) {
            return error.NotSupported;
        }
        const epfd = try std.posix.epoll_create1(0);
        return .{ .epfd = epfd, .allocator = allocator };
    }

    pub fn deinit(self: *Epoll) void {
        std.posix.close(self.epfd);
    }

    pub fn register(self: *Epoll, fd: fd_t, eventmask: u32) !void {
        var event = std.os.linux.epoll_event{
            .events = eventmask,
            .data = .{ .fd = fd },
        };
        try std.posix.epoll_ctl(self.epfd, .ADD, fd, &event);
    }

    pub fn modify(self: *Epoll, fd: fd_t, eventmask: u32) !void {
        var event = std.os.linux.epoll_event{
            .events = eventmask,
            .data = .{ .fd = fd },
        };
        try std.posix.epoll_ctl(self.epfd, .MOD, fd, &event);
    }

    pub fn unregister(self: *Epoll, fd: fd_t) !void {
        try std.posix.epoll_ctl(self.epfd, .DEL, fd, null);
    }

    pub fn poll(self: *Epoll, timeout_ms: i32, max_events: usize) ![]std.os.linux.epoll_event {
        var events: [64]std.os.linux.epoll_event = undefined;
        const count = @min(max_events, events.len);
        const result = std.posix.epoll_wait(self.epfd, events[0..count], timeout_ms);
        return self.allocator.dupe(std.os.linux.epoll_event, events[0..@intCast(result)]);
    }
};

// Epoll constants (Linux-specific)
pub const EPOLLIN: u32 = 0x001;
pub const EPOLLOUT: u32 = 0x004;
pub const EPOLLERR: u32 = 0x008;
pub const EPOLLHUP: u32 = 0x010;
pub const EPOLLET: u32 = 0x80000000; // Edge-triggered
pub const EPOLLONESHOT: u32 = 0x40000000;

// ============================================================================
// Platform-specific: kqueue (macOS/BSD)
// ============================================================================

pub const Kqueue = struct {
    kqfd: fd_t,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Kqueue {
        if (builtin.os.tag != .macos and builtin.os.tag != .freebsd) {
            return error.NotSupported;
        }
        const kqfd = try std.posix.kqueue();
        return .{ .kqfd = kqfd, .allocator = allocator };
    }

    pub fn deinit(self: *Kqueue) void {
        std.posix.close(self.kqfd);
    }

    pub fn control(self: *Kqueue, changelist: []const std.posix.Kevent) !void {
        _ = try std.posix.kevent(self.kqfd, changelist, &.{}, null);
    }

    pub fn poll(self: *Kqueue, max_events: usize, timeout: ?std.posix.timespec) ![]std.posix.Kevent {
        var events: [64]std.posix.Kevent = undefined;
        const count = @min(max_events, events.len);
        const result = try std.posix.kevent(self.kqfd, &.{}, events[0..count], timeout);
        return self.allocator.dupe(std.posix.Kevent, events[0..result]);
    }
};

// Kqueue filter constants
pub const KQ_FILTER_READ: i16 = -1;
pub const KQ_FILTER_WRITE: i16 = -2;
pub const KQ_FILTER_AIO: i16 = -3;
pub const KQ_FILTER_VNODE: i16 = -4;
pub const KQ_FILTER_PROC: i16 = -5;
pub const KQ_FILTER_SIGNAL: i16 = -6;
pub const KQ_FILTER_TIMER: i16 = -7;

// Kqueue event flags
pub const KQ_EV_ADD: u16 = 0x0001;
pub const KQ_EV_DELETE: u16 = 0x0002;
pub const KQ_EV_ENABLE: u16 = 0x0004;
pub const KQ_EV_DISABLE: u16 = 0x0008;
pub const KQ_EV_ONESHOT: u16 = 0x0010;
pub const KQ_EV_CLEAR: u16 = 0x0020;
pub const KQ_EV_EOF: u16 = 0x8000;
pub const KQ_EV_ERROR: u16 = 0x4000;

// ============================================================================
// Convenience: Default selector for current platform
// ============================================================================

/// Get the default selector type for the current platform
pub fn getDefaultSelector() type {
    return switch (builtin.os.tag) {
        .linux => Epoll,
        .macos, .freebsd, .netbsd, .openbsd => Kqueue,
        else => Poll,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "select with timeout" {
    const allocator = std.testing.allocator;

    // Test with empty lists and zero timeout (immediate return)
    const result = try select(allocator, &.{}, &.{}, &.{}, 0.0);
    defer allocator.free(result.r);
    defer allocator.free(result.w);
    defer allocator.free(result.x);

    try std.testing.expectEqual(@as(usize, 0), result.r.len);
    try std.testing.expectEqual(@as(usize, 0), result.w.len);
    try std.testing.expectEqual(@as(usize, 0), result.x.len);
}

test "poll object" {
    const allocator = std.testing.allocator;

    var p = Poll.init(allocator);
    defer p.deinit();

    // Register stdout (fd 1) for write events
    try p.register(1, POLLOUT);

    // Poll with zero timeout
    const events = try p.poll(0);
    defer allocator.free(events);

    // stdout should be writable
    try std.testing.expect(events.len > 0);
}

test "poll constants" {
    try std.testing.expectEqual(@as(i16, 0x0001), POLLIN);
    try std.testing.expectEqual(@as(i16, 0x0004), POLLOUT);
    try std.testing.expectEqual(@as(i16, 0x0008), POLLERR);
    try std.testing.expectEqual(@as(i16, 0x0010), POLLHUP);
    try std.testing.expectEqual(@as(i16, 0x0020), POLLNVAL);
}
