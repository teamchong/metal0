//! Tests for event scheduler module.

const std = @import("std");
const types = @import("types.zig");
const scheduler = @import("scheduler.zig");
const simple_scheduler = @import("simple_scheduler.zig");
const recurring_event = @import("recurring_event.zig");

const Event = types.Event;
const Scheduler = scheduler.Scheduler;
const SimpleScheduler = simple_scheduler.SimpleScheduler;
const RecurringEvent = recurring_event.RecurringEvent;

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
