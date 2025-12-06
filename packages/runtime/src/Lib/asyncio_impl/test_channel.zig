const std = @import("std");
const testing = std.testing;
const Channel = @import("channel.zig").Channel;
const Task = @import("task.zig").Task;
const select_mod = @import("channel/select.zig");

test "Channel - unbuffered creation" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).init(allocator);
    defer chan.deinit();

    try testing.expectEqual(@as(usize, 0), chan.capacity);
    try testing.expect(!chan.isClosed());
    try testing.expectEqual(@as(usize, 0), chan.len());
}

test "Channel - buffered creation" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 10);
    defer chan.deinit();

    try testing.expectEqual(@as(usize, 10), chan.capacity);
    try testing.expect(!chan.isClosed());
    try testing.expectEqual(@as(usize, 0), chan.len());
    try testing.expect(chan.isEmpty());
    try testing.expect(!chan.isFull());
}

test "Channel - close" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).init(allocator);
    defer chan.deinit();

    try testing.expect(!chan.isClosed());

    chan.close();

    try testing.expect(chan.isClosed());
}

test "Channel - buffered send and receive" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 5);
    defer chan.deinit();

    const task = try allocator.create(Task);
    defer allocator.destroy(task);
    task.* = Task.init(1, undefined, undefined);
    task.state = .running;

    // Send values
    try chan.send(10, task);
    try chan.send(20, task);
    try chan.send(30, task);

    try testing.expectEqual(@as(usize, 3), chan.len());
    try testing.expect(!chan.isEmpty());
    try testing.expect(!chan.isFull());

    // Receive values
    const v1 = try chan.recv(task);
    const v2 = try chan.recv(task);
    const v3 = try chan.recv(task);

    try testing.expectEqual(@as(i32, 10), v1);
    try testing.expectEqual(@as(i32, 20), v2);
    try testing.expectEqual(@as(i32, 30), v3);
    try testing.expectEqual(@as(usize, 0), chan.len());
}

test "Channel - trySend success" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 3);
    defer chan.deinit();

    const success1 = try chan.trySend(100);
    const success2 = try chan.trySend(200);

    try testing.expect(success1);
    try testing.expect(success2);
    try testing.expectEqual(@as(usize, 2), chan.len());
}

test "Channel - trySend fail when full" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 2);
    defer chan.deinit();

    _ = try chan.trySend(1);
    _ = try chan.trySend(2);

    const success = try chan.trySend(3); // Should fail - buffer full

    try testing.expect(!success);
    try testing.expectEqual(@as(usize, 2), chan.len());
    try testing.expect(chan.isFull());
}

test "Channel - tryRecv success" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 3);
    defer chan.deinit();

    _ = try chan.trySend(42);

    const value = chan.tryRecv();

    try testing.expect(value != null);
    try testing.expectEqual(@as(i32, 42), value.?);
    try testing.expectEqual(@as(usize, 0), chan.len());
}

test "Channel - tryRecv fail when empty" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 3);
    defer chan.deinit();

    const value = chan.tryRecv();

    try testing.expect(value == null);
}

test "Channel - FIFO ordering" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 10);
    defer chan.deinit();

    const task = try allocator.create(Task);
    defer allocator.destroy(task);
    task.* = Task.init(1, undefined, undefined);
    task.state = .running;

    // Send 1, 2, 3, 4, 5
    try chan.send(1, task);
    try chan.send(2, task);
    try chan.send(3, task);
    try chan.send(4, task);
    try chan.send(5, task);

    // Should receive in same order
    try testing.expectEqual(@as(i32, 1), try chan.recv(task));
    try testing.expectEqual(@as(i32, 2), try chan.recv(task));
    try testing.expectEqual(@as(i32, 3), try chan.recv(task));
    try testing.expectEqual(@as(i32, 4), try chan.recv(task));
    try testing.expectEqual(@as(i32, 5), try chan.recv(task));
}

test "Channel - wrap around buffer" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 3);
    defer chan.deinit();

    const task = try allocator.create(Task);
    defer allocator.destroy(task);
    task.* = Task.init(1, undefined, undefined);
    task.state = .running;

    // Fill buffer
    try chan.send(1, task);
    try chan.send(2, task);
    try chan.send(3, task);

    // Empty buffer
    _ = try chan.recv(task);
    _ = try chan.recv(task);
    _ = try chan.recv(task);

    // Fill again (tests wrap-around)
    try chan.send(4, task);
    try chan.send(5, task);
    try chan.send(6, task);

    try testing.expectEqual(@as(i32, 4), try chan.recv(task));
    try testing.expectEqual(@as(i32, 5), try chan.recv(task));
    try testing.expectEqual(@as(i32, 6), try chan.recv(task));
}

test "Channel - send after close errors" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 3);
    defer chan.deinit();

    const task = try allocator.create(Task);
    defer allocator.destroy(task);
    task.* = Task.init(1, undefined, undefined);
    task.state = .running;

    chan.close();

    const result = chan.send(42, task);
    try testing.expectError(error.ChannelClosed, result);
}

test "Channel - trySend after close errors" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 3);
    defer chan.deinit();

    chan.close();

    const result = chan.trySend(42);
    try testing.expectError(error.ChannelClosed, result);
}

test "Channel - queue lengths" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).init(allocator);
    defer chan.deinit();

    try testing.expectEqual(@as(usize, 0), chan.sendQueueLen());
    try testing.expectEqual(@as(usize, 0), chan.recvQueueLen());
}

test "Channel - capacity and cap()" {
    const allocator = testing.allocator;

    const chan1 = try Channel(i32).init(allocator);
    defer chan1.deinit();

    const chan2 = try Channel(i32).initBuffered(allocator, 100);
    defer chan2.deinit();

    try testing.expectEqual(@as(usize, 0), chan1.cap());
    try testing.expectEqual(@as(usize, 100), chan2.cap());
}

test "Channel - make helpers" {
    const allocator = testing.allocator;

    const chan1 = try @import("channel.zig").make(i32, allocator);
    defer chan1.deinit();

    const chan2 = try @import("channel.zig").makeBuffered(i32, allocator, 50);
    defer chan2.deinit();

    try testing.expectEqual(@as(usize, 0), chan1.cap());
    try testing.expectEqual(@as(usize, 50), chan2.cap());
}

test "Channel - different types" {
    const allocator = testing.allocator;

    const task = try allocator.create(Task);
    defer allocator.destroy(task);
    task.* = Task.init(1, undefined, undefined);
    task.state = .running;

    // i64 channel
    const chan_i64 = try Channel(i64).initBuffered(allocator, 5);
    defer chan_i64.deinit();

    try chan_i64.send(999999999, task);
    try testing.expectEqual(@as(i64, 999999999), try chan_i64.recv(task));

    // bool channel
    const chan_bool = try Channel(bool).initBuffered(allocator, 5);
    defer chan_bool.deinit();

    try chan_bool.send(true, task);
    try chan_bool.send(false, task);
    try testing.expectEqual(true, try chan_bool.recv(task));
    try testing.expectEqual(false, try chan_bool.recv(task));

    // f64 channel
    const chan_f64 = try Channel(f64).initBuffered(allocator, 5);
    defer chan_f64.deinit();

    try chan_f64.send(3.14159, task);
    const pi = try chan_f64.recv(task);
    try testing.expectApproxEqAbs(@as(f64, 3.14159), pi, 0.00001);
}

test "Select - sendCase helper" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).init(allocator);
    defer chan.deinit();

    var value: i32 = 42;
    const case = select_mod.sendCase(i32, chan, &value);

    try testing.expect(case == .send);
}

test "Select - recvCase helper" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).init(allocator);
    defer chan.deinit();

    var result: i32 = 0;
    const case = select_mod.recvCase(i32, chan, &result);

    try testing.expect(case == .recv);
}

test "Select - defaultCase helper" {
    const case = select_mod.defaultCase();
    try testing.expect(case == .default);
}

test "Select - creation with cases" {
    const allocator = testing.allocator;

    const chan1 = try Channel(i32).init(allocator);
    defer chan1.deinit();

    const chan2 = try Channel(i32).init(allocator);
    defer chan2.deinit();

    var result1: i32 = 0;
    var result2: i32 = 0;

    var cases = [_]select_mod.Select.Case{
        select_mod.recvCase(i32, chan1, &result1),
        select_mod.recvCase(i32, chan2, &result2),
        select_mod.defaultCase(),
    };

    const sel = select_mod.Select.init(allocator, &cases);
    try testing.expectEqual(@as(usize, 3), sel.cases.len);
}

test "Channel - stress test buffered" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 1000);
    defer chan.deinit();

    const task = try allocator.create(Task);
    defer allocator.destroy(task);
    task.* = Task.init(1, undefined, undefined);
    task.state = .running;

    // Send 1000 values
    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        try chan.send(i, task);
    }

    try testing.expectEqual(@as(usize, 1000), chan.len());
    try testing.expect(chan.isFull());

    // Receive all
    i = 0;
    while (i < 1000) : (i += 1) {
        const value = try chan.recv(task);
        try testing.expectEqual(i, value);
    }

    try testing.expect(chan.isEmpty());
}

test "Channel - interleaved send/recv" {
    const allocator = testing.allocator;

    const chan = try Channel(i32).initBuffered(allocator, 5);
    defer chan.deinit();

    const task = try allocator.create(Task);
    defer allocator.destroy(task);
    task.* = Task.init(1, undefined, undefined);
    task.state = .running;

    // Interleave sends and receives
    try chan.send(1, task);
    try testing.expectEqual(@as(i32, 1), try chan.recv(task));

    try chan.send(2, task);
    try chan.send(3, task);
    try testing.expectEqual(@as(i32, 2), try chan.recv(task));

    try chan.send(4, task);
    try testing.expectEqual(@as(i32, 3), try chan.recv(task));
    try testing.expectEqual(@as(i32, 4), try chan.recv(task));

    try testing.expect(chan.isEmpty());
}
