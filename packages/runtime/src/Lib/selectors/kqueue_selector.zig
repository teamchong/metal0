//! Selector using kqueue (macOS/BSD).

const std = @import("std");
const types = @import("types.zig");
const base = @import("base_selector.zig");

pub const SelectorKey = types.SelectorKey;
pub const EventResult = types.EventResult;
pub const EVENT_READ = types.EVENT_READ;
pub const EVENT_WRITE = types.EVENT_WRITE;
pub const BaseSelector = base.BaseSelector;

// ============================================================================
// KqueueSelector
// ============================================================================

/// Selector using kqueue (macOS/BSD)
pub const KqueueSelector = struct {
    const Self = @This();

    base_sel: BaseSelector,
    kqueue_fd: std.posix.fd_t,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const kq = std.posix.kqueue() catch return error.KqueueCreateFailed;
        return .{
            .base_sel = BaseSelector.init(allocator),
            .kqueue_fd = kq,
        };
    }

    pub fn deinit(self: *Self) void {
        self.base_sel.deinit();
        if (self.kqueue_fd >= 0) {
            std.posix.close(self.kqueue_fd);
        }
    }

    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        const key = try self.base_sel.register(fileobj, events, data);

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

        return self.base_sel.unregister(fileobj);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]EventResult {
        var eventlist: [64]std.posix.Kevent = undefined;

        const ts: ?std.posix.timespec = if (timeout) |t| .{
            .tv_sec = @intFromFloat(t),
            .tv_nsec = @intFromFloat((t - @floor(t)) * 1_000_000_000),
        } else null;

        const n = std.posix.kevent(self.kqueue_fd, &[_]std.posix.Kevent{}, &eventlist, if (ts) |*t| t else null) catch |err| {
            if (err == error.INTR) return &[_]EventResult{};
            return err;
        };

        var result: std.ArrayList(EventResult) = .{};
        for (eventlist[0..n]) |ev| {
            const fd: i32 = @intCast(ev.ident);
            if (self.base_sel.registered.get(fd)) |key| {
                var events: u32 = 0;
                if (ev.filter == std.posix.system.EVFILT.READ) events |= EVENT_READ;
                if (ev.filter == std.posix.system.EVFILT.WRITE) events |= EVENT_WRITE;
                try result.append(self.base_sel.allocator, .{ .key = key, .events = events });
            }
        }
        return result.toOwnedSlice(self.base_sel.allocator);
    }

    pub fn close(self: *Self) void {
        self.base_sel.close();
        if (self.kqueue_fd >= 0) {
            std.posix.close(self.kqueue_fd);
            self.kqueue_fd = -1;
        }
    }
};
