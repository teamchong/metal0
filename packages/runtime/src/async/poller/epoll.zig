const std = @import("std");
const linux = std.os.linux;
const common = @import("common.zig");
const Task = @import("../task.zig").Task;

/// Linux epoll-based I/O poller (edge-triggered)
pub const EpollPoller = struct {
    /// epoll file descriptor
    epoll_fd: i32,

    /// Event buffer for epoll_wait
    events: []linux.epoll_event,

    /// Ready events to return
    ready_events: std.ArrayList(common.Event),

    /// Allocator
    allocator: std.mem.Allocator,

    /// Statistics
    stats: common.PollerStats,

    /// Maximum events per wait
    const MAX_EVENTS = 1024;

    /// Initialize epoll poller
    pub fn init(allocator: std.mem.Allocator) !EpollPoller {
        // Create epoll instance (EPOLL_CLOEXEC = close on exec)
        const epoll_fd = try std.posix.epoll_create1(linux.EPOLL.CLOEXEC);
        errdefer std.posix.close(epoll_fd);

        // Allocate event buffer
        const events = try allocator.alloc(linux.epoll_event, MAX_EVENTS);
        errdefer allocator.free(events);

        return EpollPoller{
            .epoll_fd = epoll_fd,
            .events = events,
            .ready_events = std.ArrayList(common.Event){},
            .allocator = allocator,
            .stats = std.mem.zeroes(common.PollerStats),
        };
    }

    /// Clean up poller resources
    pub fn deinit(self: *EpollPoller) void {
        std.posix.close(self.epoll_fd);
        self.allocator.free(self.events);
        self.ready_events.deinit(self.allocator);
    }

    /// Register file descriptor for I/O events
    pub fn register(self: *EpollPoller, fd: std.posix.fd_t, events: u32, task: *Task) !void {
        var ev: linux.epoll_event = undefined;

        // Edge-triggered mode (more efficient, Go-style)
        ev.events = linux.EPOLL.ET;

        // Add requested events
        if (events & common.READABLE != 0) {
            ev.events |= linux.EPOLL.IN;
        }
        if (events & common.WRITABLE != 0) {
            ev.events |= linux.EPOLL.OUT;
        }

        // Store task pointer in user data
        ev.data.ptr = @intFromPtr(task);

        // Add to epoll
        try std.posix.epoll_ctl(
            self.epoll_fd,
            linux.EPOLL.CTL_ADD,
            fd,
            &ev,
        );

        // Update task state
        task.io_fd = fd;
        task.io_events = events;

        self.stats.total_registered += 1;
    }

    /// Unregister file descriptor
    pub fn unregister(self: *EpollPoller, fd: std.posix.fd_t) !void {
        // epoll_ctl with CTL_DEL ignores the event argument
        try std.posix.epoll_ctl(
            self.epoll_fd,
            linux.EPOLL.CTL_DEL,
            fd,
            null,
        );

        self.stats.total_unregistered += 1;
    }

    /// Modify registration (change event mask)
    pub fn modify(self: *EpollPoller, fd: std.posix.fd_t, events: u32) !void {
        var ev: linux.epoll_event = undefined;
        ev.events = linux.EPOLL.ET;

        if (events & common.READABLE != 0) {
            ev.events |= linux.EPOLL.IN;
        }
        if (events & common.WRITABLE != 0) {
            ev.events |= linux.EPOLL.OUT;
        }

        try std.posix.epoll_ctl(
            self.epoll_fd,
            linux.EPOLL.CTL_MOD,
            fd,
            &ev,
        );
    }

    /// Wait for I/O events (blocking with timeout)
    pub fn wait(self: *EpollPoller, timeout_ms: i32) ![]common.Event {
        // Clear previous results
        self.ready_events.clearRetainingCapacity();

        // Wait for events
        const n = std.posix.epoll_wait(
            self.epoll_fd,
            self.events,
            timeout_ms,
        );

        self.stats.total_waits += 1;

        // Timeout or no events
        if (n == 0) {
            self.stats.total_timeouts += 1;
            return &[_]common.Event{};
        }

        // Convert epoll events to common events
        for (self.events[0..n]) |ev| {
            const task: *Task = @ptrFromInt(ev.data.ptr);

            var event_mask: u32 = 0;

            // Map epoll events to common events
            if (ev.events & linux.EPOLL.IN != 0) event_mask |= common.READABLE;
            if (ev.events & linux.EPOLL.OUT != 0) event_mask |= common.WRITABLE;
            if (ev.events & linux.EPOLL.ERR != 0) event_mask |= common.ERROR;
            if (ev.events & linux.EPOLL.HUP != 0) event_mask |= common.HANGUP;

            try self.ready_events.append(self.allocator, .{
                .fd = task.io_fd,
                .events = event_mask,
                .task = task,
            });

            self.stats.total_events += 1;
        }

        return self.ready_events.items;
    }

    /// Get poller statistics
    pub fn getStats(self: *EpollPoller) common.PollerStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *EpollPoller) void {
        self.stats = std.mem.zeroes(common.PollerStats);
    }
};

// Tests (only run on Linux)
const testing = std.testing;

test "EpollPoller init/deinit" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try EpollPoller.init(allocator);
    defer poller.deinit();

    try testing.expect(poller.epoll_fd >= 0);
    try testing.expectEqual(@as(usize, EpollPoller.MAX_EVENTS), poller.events.len);
}

test "EpollPoller register/unregister" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try EpollPoller.init(allocator);
    defer poller.deinit();

    // Create a pipe for testing
    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    // Create dummy task
    var task = Task.init(1, testTaskFunc, @ptrCast(&poller));

    // Register for read events
    try poller.register(fds[0], common.READABLE, &task);
    try testing.expectEqual(@as(u64, 1), poller.stats.total_registered);

    // Unregister
    try poller.unregister(fds[0]);
    try testing.expectEqual(@as(u64, 1), poller.stats.total_unregistered);
}

test "EpollPoller wait timeout" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try EpollPoller.init(allocator);
    defer poller.deinit();

    // Wait with 1ms timeout (should return immediately with no events)
    const events = try poller.wait(1);
    try testing.expectEqual(@as(usize, 0), events.len);
    try testing.expectEqual(@as(u64, 1), poller.stats.total_waits);
    try testing.expectEqual(@as(u64, 1), poller.stats.total_timeouts);
}

test "EpollPoller detect write ready" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try EpollPoller.init(allocator);
    defer poller.deinit();

    // Create a pipe
    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    // Create dummy task
    var task = Task.init(1, testTaskFunc, @ptrCast(&poller));

    // Register for write events (pipe write end is always writable)
    try poller.register(fds[1], common.WRITABLE, &task);

    // Wait should return immediately with write event
    const events = try poller.wait(10);
    try testing.expect(events.len > 0);
    try testing.expect(events[0].events & common.WRITABLE != 0);
    try testing.expectEqual(fds[1], events[0].fd);
    try testing.expectEqual(&task, events[0].task);
}

test "EpollPoller detect read ready" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try EpollPoller.init(allocator);
    defer poller.deinit();

    // Create a pipe
    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    // Create dummy task
    var task = Task.init(1, testTaskFunc, @ptrCast(&poller));

    // Register for read events
    try poller.register(fds[0], common.READABLE, &task);

    // Write data to pipe
    const msg = "test";
    _ = try std.posix.write(fds[1], msg);

    // Wait should return with read event
    const events = try poller.wait(10);
    try testing.expect(events.len > 0);
    try testing.expect(events[0].events & common.READABLE != 0);
    try testing.expectEqual(fds[0], events[0].fd);
}

test "EpollPoller modify registration" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try EpollPoller.init(allocator);
    defer poller.deinit();

    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var task = Task.init(1, testTaskFunc, @ptrCast(&poller));

    // Register for read only
    try poller.register(fds[0], common.READABLE, &task);

    // Modify to read + write
    try poller.modify(fds[0], common.READABLE | common.WRITABLE);

    // Should work without error
}

test "EpollPoller statistics" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try EpollPoller.init(allocator);
    defer poller.deinit();

    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var task = Task.init(1, testTaskFunc, @ptrCast(&poller));

    try poller.register(fds[1], common.WRITABLE, &task);
    _ = try poller.wait(1);

    const stats = poller.getStats();
    try testing.expectEqual(@as(u64, 1), stats.total_registered);
    try testing.expectEqual(@as(u64, 1), stats.total_waits);

    poller.resetStats();
    const reset_stats = poller.getStats();
    try testing.expectEqual(@as(u64, 0), reset_stats.total_registered);
}

// Dummy task function for testing
fn testTaskFunc(_: *anyopaque) anyerror!void {}
