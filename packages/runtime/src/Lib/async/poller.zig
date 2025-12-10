/// Async I/O Poller - Event-driven I/O multiplexing
/// Provides cross-platform async I/O using epoll (Linux), kqueue (BSD/macOS)
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Event types for polling
pub const EventType = enum {
    read,
    write,
    read_write,
    error_hup,
};

/// Poll event returned by wait()
pub const PollEvent = struct {
    fd: std.posix.fd_t,
    event_type: EventType,
    user_data: ?*anyopaque,
};

/// Cross-platform poller using epoll/kqueue
pub const Poller = struct {
    allocator: Allocator,
    poll_fd: std.posix.fd_t,
    user_data_map: std.AutoHashMap(std.posix.fd_t, ?*anyopaque),

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const poll_fd = if (builtin.os.tag == .linux)
            try std.posix.epoll_create1(.{ .CLOEXEC = true })
        else if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd)
            try std.posix.kqueue()
        else
            return error.UnsupportedPlatform;

        return .{
            .allocator = allocator,
            .poll_fd = poll_fd,
            .user_data_map = std.AutoHashMap(std.posix.fd_t, ?*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        std.posix.close(self.poll_fd);
        self.user_data_map.deinit();
    }

    /// Register a file descriptor for events
    pub fn register(self: *Self, fd: std.posix.fd_t, event_type: EventType, user_data: ?*anyopaque) !void {
        try self.user_data_map.put(fd, user_data);

        if (builtin.os.tag == .linux) {
            var event: std.os.linux.epoll_event = .{
                .events = switch (event_type) {
                    .read => std.os.linux.EPOLL.IN,
                    .write => std.os.linux.EPOLL.OUT,
                    .read_write => std.os.linux.EPOLL.IN | std.os.linux.EPOLL.OUT,
                    .error_hup => std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.HUP,
                },
                .data = .{ .fd = fd },
            };
            try std.posix.epoll_ctl(self.poll_fd, std.os.linux.EPOLL.CTL_ADD, fd, &event);
        } else {
            // kqueue
            var changelist: [2]std.posix.Kevent = undefined;
            var count: usize = 0;

            if (event_type == .read or event_type == .read_write) {
                changelist[count] = .{
                    .ident = @intCast(fd),
                    .filter = std.posix.system.EVFILT.READ,
                    .flags = std.posix.system.EV.ADD,
                    .fflags = 0,
                    .data = 0,
                    .udata = 0,
                };
                count += 1;
            }
            if (event_type == .write or event_type == .read_write) {
                changelist[count] = .{
                    .ident = @intCast(fd),
                    .filter = std.posix.system.EVFILT.WRITE,
                    .flags = std.posix.system.EV.ADD,
                    .fflags = 0,
                    .data = 0,
                    .udata = 0,
                };
                count += 1;
            }

            _ = std.posix.kevent(self.poll_fd, changelist[0..count], &[_]std.posix.Kevent{}, null) catch {};
        }
    }

    /// Unregister a file descriptor
    pub fn unregister(self: *Self, fd: std.posix.fd_t) void {
        _ = self.user_data_map.remove(fd);

        if (builtin.os.tag == .linux) {
            std.posix.epoll_ctl(self.poll_fd, std.os.linux.EPOLL.CTL_DEL, fd, null) catch {};
        } else {
            var changelist: [2]std.posix.Kevent = .{
                .{
                    .ident = @intCast(fd),
                    .filter = std.posix.system.EVFILT.READ,
                    .flags = std.posix.system.EV.DELETE,
                    .fflags = 0,
                    .data = 0,
                    .udata = 0,
                },
                .{
                    .ident = @intCast(fd),
                    .filter = std.posix.system.EVFILT.WRITE,
                    .flags = std.posix.system.EV.DELETE,
                    .fflags = 0,
                    .data = 0,
                    .udata = 0,
                },
            };
            _ = std.posix.kevent(self.poll_fd, &changelist, &[_]std.posix.Kevent{}, null) catch {};
        }
    }

    /// Wait for events with timeout (milliseconds, null = infinite)
    pub fn wait(self: *Self, events_out: []PollEvent, timeout_ms: ?i32) !usize {
        if (builtin.os.tag == .linux) {
            var epoll_events: [64]std.os.linux.epoll_event = undefined;
            const max_events = @min(events_out.len, epoll_events.len);

            const n = std.posix.epoll_wait(
                self.poll_fd,
                epoll_events[0..max_events],
                timeout_ms orelse -1,
            ) catch |err| {
                if (err == error.Interrupted) return 0;
                return err;
            };

            for (0..@intCast(n)) |i| {
                const ev = epoll_events[i];
                const event_type: EventType = if (ev.events & std.os.linux.EPOLL.IN != 0)
                    .read
                else if (ev.events & std.os.linux.EPOLL.OUT != 0)
                    .write
                else
                    .error_hup;

                events_out[i] = .{
                    .fd = ev.data.fd,
                    .event_type = event_type,
                    .user_data = self.user_data_map.get(ev.data.fd) orelse null,
                };
            }

            return @intCast(n);
        } else {
            // kqueue
            var kevents: [64]std.posix.Kevent = undefined;
            const max_events = @min(events_out.len, kevents.len);

            const timeout: ?std.posix.timespec = if (timeout_ms) |ms|
                .{ .sec = @divFloor(ms, 1000), .nsec = @mod(ms, 1000) * 1_000_000 }
            else
                null;

            const n = std.posix.kevent(
                self.poll_fd,
                &[_]std.posix.Kevent{},
                kevents[0..max_events],
                if (timeout) |*t| t else null,
            ) catch |err| {
                if (err == error.Interrupted) return 0;
                return err;
            };

            for (0..@intCast(n)) |i| {
                const ev = kevents[i];
                const fd: std.posix.fd_t = @intCast(ev.ident);
                const event_type: EventType = if (ev.filter == std.posix.system.EVFILT.READ)
                    .read
                else if (ev.filter == std.posix.system.EVFILT.WRITE)
                    .write
                else
                    .error_hup;

                events_out[i] = .{
                    .fd = fd,
                    .event_type = event_type,
                    .user_data = self.user_data_map.get(fd) orelse null,
                };
            }

            return @intCast(n);
        }
    }

    /// Modify events for an existing registration
    pub fn modify(self: *Self, fd: std.posix.fd_t, event_type: EventType) !void {
        if (builtin.os.tag == .linux) {
            var event: std.os.linux.epoll_event = .{
                .events = switch (event_type) {
                    .read => std.os.linux.EPOLL.IN,
                    .write => std.os.linux.EPOLL.OUT,
                    .read_write => std.os.linux.EPOLL.IN | std.os.linux.EPOLL.OUT,
                    .error_hup => std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.HUP,
                },
                .data = .{ .fd = fd },
            };
            try std.posix.epoll_ctl(self.poll_fd, std.os.linux.EPOLL.CTL_MOD, fd, &event);
        } else {
            // For kqueue, delete and re-add
            self.unregister(fd);
            const user_data = self.user_data_map.get(fd) orelse null;
            try self.register(fd, event_type, user_data);
        }
    }
};
