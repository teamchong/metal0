//! Selector using poll() system call.

const std = @import("std");
const types = @import("types.zig");
const base = @import("base_selector.zig");

pub const SelectorKey = types.SelectorKey;
pub const EventResult = types.EventResult;
pub const EVENT_READ = types.EVENT_READ;
pub const EVENT_WRITE = types.EVENT_WRITE;
pub const BaseSelector = base.BaseSelector;

// ============================================================================
// PollSelector
// ============================================================================

/// Selector using poll() system call
pub const PollSelector = struct {
    const Self = @This();

    base_sel: BaseSelector,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base_sel = BaseSelector.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base_sel.deinit();
    }

    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base_sel.register(fileobj, events, data);
    }

    pub fn unregister(self: *Self, fileobj: i32) !SelectorKey {
        return self.base_sel.unregister(fileobj);
    }

    pub fn modify(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base_sel.modify(fileobj, events, data);
    }

    pub fn select(self: *Self, timeout: ?f64) ![]EventResult {
        var result: std.ArrayList(EventResult) = .{};
        errdefer result.deinit(self.base_sel.allocator);

        // Build poll fds array
        var poll_fds: std.ArrayList(std.posix.pollfd) = .{};
        defer poll_fds.deinit(self.base_sel.allocator);

        var iter = self.base_sel.registered.iterator();
        while (iter.next()) |entry| {
            const key = entry.value_ptr;
            var poll_events: i16 = 0;
            if (key.events & EVENT_READ != 0) poll_events |= std.posix.POLL.IN;
            if (key.events & EVENT_WRITE != 0) poll_events |= std.posix.POLL.OUT;

            try poll_fds.append(self.base_sel.allocator, .{
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
                const key = self.base_sel.registered.get(pfd.fd) orelse continue;
                var ready_events: u32 = 0;
                if (pfd.revents & std.posix.POLL.IN != 0) ready_events |= EVENT_READ;
                if (pfd.revents & std.posix.POLL.OUT != 0) ready_events |= EVENT_WRITE;
                try result.append(self.base_sel.allocator, .{ .key = key, .events = ready_events });
            }
        }

        return result.toOwnedSlice(self.base_sel.allocator);
    }

    pub fn close(self: *Self) void {
        self.base_sel.close();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "PollSelector init" {
    const allocator = std.testing.allocator;
    var sel = PollSelector.init(allocator);
    defer sel.deinit();

    _ = try sel.register(5, EVENT_READ, null);
    try std.testing.expectEqual(@as(usize, 1), sel.base_sel.registered.count());
}
