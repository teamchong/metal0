//! Simple scheduler for tracking named events.

const std = @import("std");
const scheduler = @import("scheduler.zig");

pub const Scheduler = scheduler.Scheduler;

/// Simple scheduler that just tracks times
pub const SimpleScheduler = struct {
    const Self = @This();

    scheduler: Scheduler,
    events: std.ArrayList(SimpleEvent),

    pub const SimpleEvent = struct {
        id: usize,
        time: i64,
        name: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .scheduler = Scheduler.init(allocator),
            .events = std.ArrayList(SimpleEvent).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.scheduler.deinit();
        self.events.deinit();
    }

    /// Schedule a named event
    pub fn schedule(self: *Self, delay: i64, name: []const u8) !usize {
        const id = self.events.items.len;
        const time = self.scheduler.timefunc() + delay;

        try self.events.append(.{
            .id = id,
            .time = time,
            .name = name,
        });

        _ = try self.scheduler.enter(delay, 0, noopAction, null, null);
        return id;
    }

    fn noopAction(_: ?*anyopaque, _: ?*anyopaque) void {}
};
