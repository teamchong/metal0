//! Recurring event that reschedules itself.

const std = @import("std");
const types = @import("types.zig");
const scheduler = @import("scheduler.zig");

pub const Event = types.Event;
pub const Scheduler = scheduler.Scheduler;

/// Recurring event that reschedules itself
pub const RecurringEvent = struct {
    const Self = @This();

    scheduler: *Scheduler,
    interval: i64,
    priority: i32,
    action: Event.Action,
    argument: ?*anyopaque,
    kwargs: ?*anyopaque,
    active: bool,
    current_event: ?Event,

    pub fn init(
        scheduler: *Scheduler,
        interval: i64,
        priority: i32,
        action: Event.Action,
        argument: ?*anyopaque,
        kwargs: ?*anyopaque,
    ) Self {
        return .{
            .scheduler = scheduler,
            .interval = interval,
            .priority = priority,
            .action = action,
            .argument = argument,
            .kwargs = kwargs,
            .active = false,
            .current_event = null,
        };
    }

    /// Start the recurring event
    pub fn start(self: *Self) !void {
        self.active = true;
        try self.scheduleNext();
    }

    /// Stop the recurring event
    pub fn stop(self: *Self) void {
        self.active = false;
        if (self.current_event) |event| {
            _ = self.scheduler.cancel(event);
            self.current_event = null;
        }
    }

    /// Schedule the next occurrence
    fn scheduleNext(self: *Self) !void {
        if (!self.active) return;

        // Create wrapper that reschedules
        self.current_event = try self.scheduler.enter(
            self.interval,
            self.priority,
            wrapperAction,
            self,
            null,
        );
    }

    fn wrapperAction(arg: ?*anyopaque, _: ?*anyopaque) void {
        if (arg) |ptr| {
            const self: *Self = @ptrCast(@alignCast(ptr));

            // Run the actual action
            self.action(self.argument, self.kwargs);

            // Reschedule
            self.scheduleNext() catch {};
        }
    }
};
