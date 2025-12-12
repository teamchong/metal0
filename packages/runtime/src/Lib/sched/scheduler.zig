//! Core event scheduler implementation.

const std = @import("std");
const types = @import("types.zig");

pub const Event = types.Event;

/// Event scheduler
pub const Scheduler = struct {
    const Self = @This();
    const EventQueue = std.PriorityQueue(Event, void, Event.lessThan);

    allocator: std.mem.Allocator,
    queue: EventQueue,
    lock: std.Thread.Mutex,
    sequence: usize,

    /// Time function type
    timefunc: *const fn () i64,
    /// Delay function type
    delayfunc: *const fn (i64) void,

    pub fn init(allocator: std.mem.Allocator) Self {
        return initWithFuncs(allocator, defaultTimefunc, defaultDelayfunc);
    }

    pub fn initWithFuncs(
        allocator: std.mem.Allocator,
        timefunc: *const fn () i64,
        delayfunc: *const fn (i64) void,
    ) Self {
        return .{
            .allocator = allocator,
            .queue = EventQueue.init(allocator, {}),
            .lock = .{},
            .sequence = 0,
            .timefunc = timefunc,
            .delayfunc = delayfunc,
        };
    }

    pub fn deinit(self: *Self) void {
        self.queue.deinit();
    }

    /// Default time function (milliseconds since epoch)
    fn defaultTimefunc() i64 {
        return std.time.milliTimestamp();
    }

    /// Default delay function (sleep for given milliseconds)
    fn defaultDelayfunc(delay: i64) void {
        if (delay > 0) {
            std.time.sleep(@intCast(delay * std.time.ns_per_ms));
        }
    }

    /// Schedule an event at an absolute time
    pub fn enterabs(
        self: *Self,
        time: i64,
        priority: i32,
        action: Event.Action,
        argument: ?*anyopaque,
        kwargs: ?*anyopaque,
    ) !Event {
        self.lock.lock();
        defer self.lock.unlock();

        const event = Event{
            .time = time,
            .priority = priority,
            .sequence = self.sequence,
            .action = action,
            .argument = argument,
            .kwargs = kwargs,
        };
        self.sequence += 1;

        try self.queue.add(event);
        return event;
    }

    /// Schedule an event after a delay
    pub fn enter(
        self: *Self,
        delay: i64,
        priority: i32,
        action: Event.Action,
        argument: ?*anyopaque,
        kwargs: ?*anyopaque,
    ) !Event {
        const time = self.timefunc() + delay;
        return self.enterabs(time, priority, action, argument, kwargs);
    }

    /// Cancel a scheduled event
    pub fn cancel(self: *Self, event: Event) bool {
        self.lock.lock();
        defer self.lock.unlock();

        // Find and remove the event
        var new_queue = EventQueue.init(self.allocator, {});
        var found = false;

        while (self.queue.removeOrNull()) |e| {
            if (e.time == event.time and
                e.priority == event.priority and
                e.sequence == event.sequence)
            {
                found = true;
            } else {
                new_queue.add(e) catch {};
            }
        }

        self.queue.deinit();
        self.queue = new_queue;
        return found;
    }

    /// Check if queue is empty
    pub fn empty(self: *Self) bool {
        self.lock.lock();
        defer self.lock.unlock();
        return self.queue.count() == 0;
    }

    /// Get the queue contents (snapshot)
    pub fn getQueue(self: *Self) ![]Event {
        self.lock.lock();
        defer self.lock.unlock();

        var result: std.ArrayList(Event) = .{};

        // Copy queue contents
        var temp_queue = EventQueue.init(self.allocator, {});
        defer temp_queue.deinit();

        while (self.queue.removeOrNull()) |e| {
            try result.append(self.allocator, e);
            try temp_queue.add(e);
        }

        // Restore queue
        while (temp_queue.removeOrNull()) |e| {
            self.queue.add(e) catch {};
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Run scheduled events
    pub fn run(self: *Self, blocking: bool) !void {
        while (true) {
            self.lock.lock();

            if (self.queue.count() == 0) {
                self.lock.unlock();
                break;
            }

            const event = self.queue.peek().?;
            const now = self.timefunc();

            if (event.time > now) {
                self.lock.unlock();

                if (blocking) {
                    self.delayfunc(event.time - now);
                } else {
                    break;
                }
            } else {
                _ = self.queue.remove();
                self.lock.unlock();

                // Execute the action
                event.action(event.argument, event.kwargs);
            }
        }
    }

    /// Run one event if ready
    pub fn runOne(self: *Self) !bool {
        self.lock.lock();

        if (self.queue.count() == 0) {
            self.lock.unlock();
            return false;
        }

        const event = self.queue.peek().?;
        const now = self.timefunc();

        if (event.time > now) {
            self.lock.unlock();
            return false;
        }

        _ = self.queue.remove();
        self.lock.unlock();

        // Execute the action
        event.action(event.argument, event.kwargs);
        return true;
    }

    /// Get count of pending events
    pub fn count(self: *Self) usize {
        self.lock.lock();
        defer self.lock.unlock();
        return self.queue.count();
    }

    /// Get time until next event (or null if empty)
    pub fn timeUntilNext(self: *Self) ?i64 {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.queue.peek()) |event| {
            const now = self.timefunc();
            const diff = event.time - now;
            return if (diff > 0) diff else 0;
        }
        return null;
    }
};
