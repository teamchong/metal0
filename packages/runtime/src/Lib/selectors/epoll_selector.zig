//! Selector using epoll (Linux).

const std = @import("std");
const types = @import("types.zig");
const base = @import("base_selector.zig");

pub const SelectorKey = types.SelectorKey;
pub const EventResult = types.EventResult;
pub const EVENT_READ = types.EVENT_READ;
pub const EVENT_WRITE = types.EVENT_WRITE;
pub const BaseSelector = base.BaseSelector;

// ============================================================================
// EpollSelector
// ============================================================================

/// Selector using epoll (Linux)
pub const EpollSelector = struct {
    const Self = @This();

    base_sel: BaseSelector,
    epoll_fd: std.posix.fd_t,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const ep = std.posix.epoll_create1(0) catch return error.EpollCreateFailed;
        return .{
            .base_sel = BaseSelector.init(allocator),
            .epoll_fd = ep,
        };
    }

    pub fn deinit(self: *Self) void {
        self.base_sel.deinit();
        if (self.epoll_fd >= 0) {
            std.posix.close(self.epoll_fd);
        }
    }

    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        const key = try self.base_sel.register(fileobj, events, data);

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

        return self.base_sel.unregister(fileobj);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]EventResult {
        var eventlist: [64]std.os.linux.epoll_event = undefined;

        const timeout_ms: i32 = if (timeout) |t| @intFromFloat(t * 1000) else -1;

        const n = std.posix.epoll_wait(self.epoll_fd, &eventlist, timeout_ms) catch |err| {
            if (err == error.INTR) return &[_]EventResult{};
            return err;
        };

        var result: std.ArrayList(EventResult) = .{};
        for (eventlist[0..n]) |ev| {
            const fd = ev.data.fd;
            if (self.base_sel.registered.get(fd)) |key| {
                var events: u32 = 0;
                if (ev.events & std.os.linux.EPOLL.IN != 0) events |= EVENT_READ;
                if (ev.events & std.os.linux.EPOLL.OUT != 0) events |= EVENT_WRITE;
                try result.append(self.base_sel.allocator, .{ .key = key, .events = events });
            }
        }
        return result.toOwnedSlice(self.base_sel.allocator);
    }

    pub fn close(self: *Self) void {
        self.base_sel.close();
        if (self.epoll_fd >= 0) {
            std.posix.close(self.epoll_fd);
            self.epoll_fd = -1;
        }
    }
};
