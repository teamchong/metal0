//! Python 'sched' module - Event scheduler
//!
//! Provides a general purpose event scheduler.
//!
//! Mirrors: CPython Lib/sched.py

const std = @import("std");

// ============================================================================
// Event
// ============================================================================

/// A scheduled event
pub const Event = struct {
    const Self = @This();

    /// Time at which to run
    time: i64,
    /// Priority (lower = higher priority)
    priority: i32,
    /// Sequence number for stable sorting
    sequence: usize,
    /// The action to run
    action: Action,
    /// Arguments for the action (opaque)
    argument: ?*anyopaque,
    /// Keyword arguments (opaque)
    kwargs: ?*anyopaque,

    /// Action function type
    pub const Action = *const fn (?*anyopaque, ?*anyopaque) void;

    /// Compare events for priority queue ordering
    pub fn lessThan(_: void, a: Self, b: Self) std.math.Order {
        // First compare by time
        if (a.time < b.time) return .lt;
        if (a.time > b.time) return .gt;

        // Then by priority
        if (a.priority < b.priority) return .lt;
        if (a.priority > b.priority) return .gt;

        // Finally by sequence number (FIFO for equal time/priority)
        if (a.sequence < b.sequence) return .lt;
        if (a.sequence > b.sequence) return .gt;

        return .eq;
    }

    /// Check if this event should run before another
    pub fn isBefore(self: Self, other: Self) bool {
        return lessThan({}, self, other) == .lt;
    }
};

// ============================================================================
// Scheduler
// ============================================================================

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

        var result = std.ArrayList(Event).init(self.allocator);

        // Copy queue contents
        var temp_queue = EventQueue.init(self.allocator, {});
        defer temp_queue.deinit();

        while (self.queue.removeOrNull()) |e| {
            try result.append(e);
            try temp_queue.add(e);
        }

        // Restore queue
        while (temp_queue.removeOrNull()) |e| {
            self.queue.add(e) catch {};
        }

        return result.toOwnedSlice();
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

// ============================================================================
// Helper Types for Common Use Cases
// ============================================================================

/// Context for a scheduled callback
pub fn CallbackContext(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,
        callback: *const fn (*T) void,

        pub fn run(arg: ?*anyopaque, _: ?*anyopaque) void {
            if (arg) |ptr| {
                const ctx: *Self = @ptrCast(@alignCast(ptr));
                ctx.callback(&ctx.data);
            }
        }
    };
}

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

// ============================================================================
// Recurring Event Support
// ============================================================================

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

// ============================================================================
// Tests
// ============================================================================

test "Event ordering" {
    const e1 = Event{
        .time = 100,
        .priority = 1,
        .sequence = 0,
        .action = undefined,
        .argument = null,
        .kwargs = null,
    };
    const e2 = Event{
        .time = 200,
        .priority = 1,
        .sequence = 1,
        .action = undefined,
        .argument = null,
        .kwargs = null,
    };

    try std.testing.expect(e1.isBefore(e2));
    try std.testing.expect(!e2.isBefore(e1));
}

test "Event priority ordering" {
    const e1 = Event{
        .time = 100,
        .priority = 1,
        .sequence = 0,
        .action = undefined,
        .argument = null,
        .kwargs = null,
    };
    const e2 = Event{
        .time = 100,
        .priority = 2,
        .sequence = 1,
        .action = undefined,
        .argument = null,
        .kwargs = null,
    };

    // Same time, lower priority number should come first
    try std.testing.expect(e1.isBefore(e2));
}

test "Scheduler init and deinit" {
    const allocator = std.testing.allocator;
    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    try std.testing.expect(sched.empty());
}

fn testAction(_: ?*anyopaque, _: ?*anyopaque) void {}

test "Scheduler enter" {
    const allocator = std.testing.allocator;
    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    _ = try sched.enter(1000, 1, testAction, null, null);
    try std.testing.expect(!sched.empty());
    try std.testing.expectEqual(@as(usize, 1), sched.count());
}

test "Scheduler enterabs" {
    const allocator = std.testing.allocator;
    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    const future_time = std.time.milliTimestamp() + 10000;
    _ = try sched.enterabs(future_time, 1, testAction, null, null);
    try std.testing.expectEqual(@as(usize, 1), sched.count());
}

test "Scheduler cancel" {
    const allocator = std.testing.allocator;
    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    const event = try sched.enter(1000, 1, testAction, null, null);
    try std.testing.expect(!sched.empty());

    const cancelled = sched.cancel(event);
    try std.testing.expect(cancelled);
    try std.testing.expect(sched.empty());
}

test "Scheduler getQueue" {
    const allocator = std.testing.allocator;
    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    _ = try sched.enter(1000, 1, testAction, null, null);
    _ = try sched.enter(2000, 2, testAction, null, null);

    const queue = try sched.getQueue();
    defer allocator.free(queue);

    try std.testing.expectEqual(@as(usize, 2), queue.len);
}

test "Scheduler timeUntilNext" {
    const allocator = std.testing.allocator;
    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    // Empty queue
    try std.testing.expect(sched.timeUntilNext() == null);

    // With event
    _ = try sched.enter(1000, 1, testAction, null, null);
    const time_until = sched.timeUntilNext();
    try std.testing.expect(time_until != null);
    try std.testing.expect(time_until.? > 0);
}

test "SimpleScheduler" {
    const allocator = std.testing.allocator;
    var sched = SimpleScheduler.init(allocator);
    defer sched.deinit();

    const id = try sched.schedule(1000, "test_event");
    try std.testing.expectEqual(@as(usize, 0), id);
    try std.testing.expectEqual(@as(usize, 1), sched.events.items.len);
}

test "RecurringEvent init" {
    const allocator = std.testing.allocator;
    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    var recurring = RecurringEvent.init(&sched, 1000, 1, testAction, null, null);
    try std.testing.expect(!recurring.active);
}
