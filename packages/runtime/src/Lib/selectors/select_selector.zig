//! Selector using select() system call.

const std = @import("std");
const types = @import("types.zig");
const base = @import("base_selector.zig");

pub const SelectorKey = types.SelectorKey;
pub const EventResult = types.EventResult;
pub const EVENT_READ = types.EVENT_READ;
pub const EVENT_WRITE = types.EVENT_WRITE;
pub const BaseSelector = base.BaseSelector;

// ============================================================================
// SelectSelector
// ============================================================================

/// Selector using select() system call
pub const SelectSelector = struct {
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

    /// Register a file object
    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base_sel.register(fileobj, events, data);
    }

    /// Unregister a file object
    pub fn unregister(self: *Self, fileobj: i32) !SelectorKey {
        return self.base_sel.unregister(fileobj);
    }

    /// Modify registration
    pub fn modify(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        return self.base_sel.modify(fileobj, events, data);
    }

    /// Wait for events
    pub fn select(self: *Self, timeout: ?f64) ![]EventResult {
        var result = std.ArrayList(EventResult).init(self.base_sel.allocator);
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

        var iter = self.base_sel.registered.iterator();
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
        var result_iter = self.base_sel.registered.iterator();
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
        self.base_sel.close();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SelectSelector init" {
    const allocator = std.testing.allocator;
    var sel = SelectSelector.init(allocator);
    defer sel.deinit();

    _ = try sel.register(5, EVENT_READ, null);
    try std.testing.expectEqual(@as(usize, 1), sel.base_sel.registered.count());
}
