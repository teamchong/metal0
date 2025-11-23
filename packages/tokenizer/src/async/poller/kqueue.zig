const std = @import("std");
const common = @import("common.zig");
const Task = @import("../task.zig").Task;

/// macOS/BSD kqueue-based I/O poller (edge-triggered)
pub const KqueuePoller = struct {
    /// kqueue file descriptor
    kq_fd: i32,

    /// Event buffer for kevent
    events: []std.posix.system.Kevent,

    /// Ready events to return
    ready_events: std.ArrayList(common.Event),

    /// Allocator
    allocator: std.mem.Allocator,

    /// Statistics
    stats: common.PollerStats,

    /// Maximum events per wait
    const MAX_EVENTS = 1024;

    /// Initialize kqueue poller
    pub fn init(allocator: std.mem.Allocator) !KqueuePoller {
        // Create kqueue instance
        const kq_fd = try std.posix.kqueue();
        errdefer std.posix.close(kq_fd);

        // Allocate event buffer
        const events = try allocator.alloc(std.posix.system.Kevent, MAX_EVENTS);
        errdefer allocator.free(events);

        return KqueuePoller{
            .kq_fd = kq_fd,
            .events = events,
            .ready_events = std.ArrayList(common.Event){},
            .allocator = allocator,
            .stats = std.mem.zeroes(common.PollerStats),
        };
    }

    /// Clean up poller resources
    pub fn deinit(self: *KqueuePoller) void {
        std.posix.close(self.kq_fd);
        self.allocator.free(self.events);
        self.ready_events.deinit(self.allocator);
    }

    /// Register file descriptor for I/O events
    pub fn register(self: *KqueuePoller, fd: std.posix.fd_t, events: u32, task: *Task) !void {
        var changes: [2]std.posix.system.Kevent = undefined;
        var nchanges: usize = 0;

        // Register for read events
        if (events & common.READABLE != 0) {
            changes[nchanges] = std.posix.system.Kevent{
                .ident = @intCast(fd),
                .filter = std.posix.system.EVFILT_READ,
                .flags = std.posix.system.EV_ADD | std.posix.system.EV_CLEAR, // Edge-triggered
                .fflags = 0,
                .data = 0,
                .udata = @intFromPtr(task),
            };
            nchanges += 1;
        }

        // Register for write events
        if (events & common.WRITABLE != 0) {
            changes[nchanges] = std.posix.system.Kevent{
                .ident = @intCast(fd),
                .filter = std.posix.system.EVFILT_WRITE,
                .flags = std.posix.system.EV_ADD | std.posix.system.EV_CLEAR, // Edge-triggered
                .fflags = 0,
                .data = 0,
                .udata = @intFromPtr(task),
            };
            nchanges += 1;
        }

        // Apply changes
        if (nchanges > 0) {
            _ = try std.posix.kevent(
                self.kq_fd,
                changes[0..nchanges],
                &[_]std.posix.system.Kevent{}, // No immediate events
                null, // No timeout
            );
        }

        // Update task state
        task.io_fd = fd;
        task.io_events = events;

        self.stats.total_registered += 1;
    }

    /// Unregister file descriptor
    pub fn unregister(self: *KqueuePoller, fd: std.posix.fd_t) !void {
        // Delete both read and write filters (if they exist)
        var changes: [2]std.posix.system.Kevent = undefined;

        changes[0] = std.posix.system.Kevent{
            .ident = @intCast(fd),
            .filter = std.posix.system.EVFILT_READ,
            .flags = std.posix.system.EV_DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        };

        changes[1] = std.posix.system.Kevent{
            .ident = @intCast(fd),
            .filter = std.posix.system.EVFILT_WRITE,
            .flags = std.posix.system.EV_DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        };

        // Try to delete (ignore errors if filter doesn't exist)
        _ = std.posix.kevent(
            self.kq_fd,
            &changes,
            &[_]std.posix.system.Kevent{},
            null,
        ) catch {};

        self.stats.total_unregistered += 1;
    }

    /// Modify registration (change event mask)
    pub fn modify(self: *KqueuePoller, fd: std.posix.fd_t, events: u32) !void {
        // kqueue modify = unregister + register
        // This is a simplified implementation that requires re-registering
        // In practice, the runtime would track fd -> task mapping
        try self.unregister(fd);

        // NOTE: To complete this, caller would need to call register() again with task
        // This is a known limitation of the current API design
        _ = events;
    }

    /// Wait for I/O events (blocking with timeout)
    pub fn wait(self: *KqueuePoller, timeout_ms: i32) ![]common.Event {
        // Clear previous results
        self.ready_events.clearRetainingCapacity();

        // Convert timeout to timespec
        const timeout: ?*const std.posix.timespec = if (timeout_ms < 0)
            null // Infinite timeout
        else blk: {
            const ts = std.posix.timespec{
                .tv_sec = @divTrunc(timeout_ms, 1000),
                .tv_nsec = @rem(timeout_ms, 1000) * 1_000_000,
            };
            break :blk &ts;
        };

        // Wait for events
        const n = try std.posix.kevent(
            self.kq_fd,
            &[_]std.posix.system.Kevent{}, // No changes
            self.events,
            timeout,
        );

        self.stats.total_waits += 1;

        // Timeout or no events
        if (n == 0) {
            self.stats.total_timeouts += 1;
            return &[_]common.Event{};
        }

        // Convert kqueue events to common events
        for (self.events[0..n]) |ev| {
            const task: *Task = @ptrFromInt(ev.udata);

            var event_mask: u32 = 0;

            // Map kqueue events to common events
            if (ev.filter == std.posix.system.EVFILT_READ) {
                event_mask |= common.READABLE;
            }
            if (ev.filter == std.posix.system.EVFILT_WRITE) {
                event_mask |= common.WRITABLE;
            }
            if (ev.flags & std.posix.system.EV_ERROR != 0) {
                event_mask |= common.ERROR;
            }
            if (ev.flags & std.posix.system.EV_EOF != 0) {
                event_mask |= common.HANGUP;
            }

            try self.ready_events.append(self.allocator, .{
                .fd = @intCast(ev.ident),
                .events = event_mask,
                .task = task,
            });

            self.stats.total_events += 1;
        }

        return self.ready_events.items;
    }

    /// Get poller statistics
    pub fn getStats(self: *KqueuePoller) common.PollerStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *KqueuePoller) void {
        self.stats = std.mem.zeroes(common.PollerStats);
    }
};

// Tests (only run on macOS/BSD)
const testing = std.testing;

test "KqueuePoller init/deinit" {
    const builtin = @import("builtin");
    const is_bsd = switch (builtin.target.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };
    if (!is_bsd) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try KqueuePoller.init(allocator);
    defer poller.deinit();

    try testing.expect(poller.kq_fd >= 0);
    try testing.expectEqual(@as(usize, KqueuePoller.MAX_EVENTS), poller.events.len);
}

test "KqueuePoller register/unregister" {
    const builtin = @import("builtin");
    const is_bsd = switch (builtin.target.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };
    if (!is_bsd) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try KqueuePoller.init(allocator);
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

test "KqueuePoller wait timeout" {
    const is_bsd = switch (@import("builtin").target.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };
    if (!is_bsd) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try KqueuePoller.init(allocator);
    defer poller.deinit();

    // Wait with 1ms timeout (should return immediately with no events)
    const events = try poller.wait(1);
    try testing.expectEqual(@as(usize, 0), events.len);
    try testing.expectEqual(@as(u64, 1), poller.stats.total_waits);
    try testing.expectEqual(@as(u64, 1), poller.stats.total_timeouts);
}

test "KqueuePoller detect write ready" {
    const is_bsd = switch (@import("builtin").target.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };
    if (!is_bsd) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try KqueuePoller.init(allocator);
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

test "KqueuePoller detect read ready" {
    const is_bsd = switch (@import("builtin").target.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };
    if (!is_bsd) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try KqueuePoller.init(allocator);
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

test "KqueuePoller statistics" {
    const is_bsd = switch (@import("builtin").target.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };
    if (!is_bsd) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try KqueuePoller.init(allocator);
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

test "KqueuePoller multiple events" {
    const is_bsd = switch (@import("builtin").target.os.tag) {
        .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };
    if (!is_bsd) return error.SkipZigTest;

    const allocator = testing.allocator;
    var poller = try KqueuePoller.init(allocator);
    defer poller.deinit();

    // Create two pipes
    var fds1: [2]std.posix.fd_t = undefined;
    var fds2: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds1);
    defer std.posix.close(fds1[0]);
    defer std.posix.close(fds1[1]);
    try std.posix.pipe(&fds2);
    defer std.posix.close(fds2[0]);
    defer std.posix.close(fds2[1]);

    var task1 = Task.init(1, testTaskFunc, @ptrCast(&poller));
    var task2 = Task.init(2, testTaskFunc, @ptrCast(&poller));

    // Register both for write (both should be ready)
    try poller.register(fds1[1], common.WRITABLE, &task1);
    try poller.register(fds2[1], common.WRITABLE, &task2);

    // Should get both events
    const events = try poller.wait(10);
    try testing.expect(events.len == 2);
}

// Dummy task function for testing
fn testTaskFunc(_: *anyopaque) anyerror!void {}
