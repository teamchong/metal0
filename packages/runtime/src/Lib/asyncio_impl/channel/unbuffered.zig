const std = @import("std");
const Task = @import("../task.zig").Task;
const TaskState = @import("../task.zig").TaskState;

/// Send on unbuffered channel (rendezvous)
pub fn send(chan: anytype, value: anytype, current_task: *Task) !void {
    if (chan.closed.load(.acquire)) {
        return error.ChannelClosed;
    }

    // Try fast path: check if receiver waiting
    {
        chan.mutex.lock();
        defer chan.mutex.unlock();

        if (chan.recv_queue.dequeue(chan.allocator)) |receiver| {
            // Direct handoff to waiting receiver
            if (receiver.value_ptr) |ptr| {
                ptr.* = value;
            }
            receiver.task.state = .runnable;
            return;
        }
    }

    // Slow path: block until receiver arrives
    var value_holder = value;
    const max_spins: usize = 1000;
    var spin_count: usize = 0;

    while (true) {
        // Check if closed
        if (chan.closed.load(.acquire)) {
            return error.ChannelClosed;
        }

        // Try again to find receiver
        {
            chan.mutex.lock();
            defer chan.mutex.unlock();

            if (chan.recv_queue.dequeue(chan.allocator)) |receiver| {
                if (receiver.value_ptr) |ptr| {
                    ptr.* = value_holder;
                }
                receiver.task.state = .runnable;
                return;
            }
        }

        // No receiver yet - decide whether to spin or yield
        if (spin_count < max_spins) {
            spin_count += 1;
            std.atomic.spinLoopHint();
            continue;
        }

        // Add to send queue and yield
        {
            chan.mutex.lock();
            defer chan.mutex.unlock();

            try chan.send_queue.enqueue(chan.allocator, current_task, &value_holder);
        }

        current_task.state = .waiting;
        current_task.recordYield();

        // Yield to scheduler
        std.Thread.sleep(1000); // 1 microsecond

        // Check if we were woken up
        if (current_task.state == .runnable) {
            current_task.state = .running;
            return;
        }

        // Remove from queue if still there
        // (We might have timed out or been interrupted)
        // For simplicity, we'll just continue the loop
        spin_count = 0;
    }
}

/// Receive from unbuffered channel (rendezvous)
pub fn recv(chan: anytype, current_task: *Task) !@TypeOf(chan.buffer.?[0]) {
    const T = @TypeOf(chan.buffer.?[0]);

    // Try fast path: check if sender waiting
    {
        chan.mutex.lock();
        defer chan.mutex.unlock();

        if (chan.send_queue.dequeue(chan.allocator)) |sender| {
            // Get value from waiting sender
            const value = sender.value_ptr.?.*;
            sender.task.state = .runnable;
            return value;
        }

        // Check if closed with no senders
        if (chan.closed.load(.acquire)) {
            return error.ChannelClosed;
        }
    }

    // Slow path: block until sender arrives
    var value_holder: T = undefined;
    const max_spins: usize = 1000;
    var spin_count: usize = 0;

    while (true) {
        // Try again to find sender
        {
            chan.mutex.lock();
            defer chan.mutex.unlock();

            if (chan.send_queue.dequeue(chan.allocator)) |sender| {
                const value = sender.value_ptr.?.*;
                sender.task.state = .runnable;
                return value;
            }

            // Check if closed
            if (chan.closed.load(.acquire)) {
                return error.ChannelClosed;
            }
        }

        // No sender yet - decide whether to spin or yield
        if (spin_count < max_spins) {
            spin_count += 1;
            std.atomic.spinLoopHint();
            continue;
        }

        // Add to recv queue and yield
        {
            chan.mutex.lock();
            defer chan.mutex.unlock();

            try chan.recv_queue.enqueue(chan.allocator, current_task, &value_holder);
        }

        current_task.state = .waiting;
        current_task.recordYield();

        // Yield to scheduler
        std.Thread.sleep(1000); // 1 microsecond

        // Check if we were woken up with value
        if (current_task.state == .runnable) {
            current_task.state = .running;
            return value_holder;
        }

        spin_count = 0;
    }
}

/// Try send on unbuffered channel (non-blocking)
pub fn trySend(chan: anytype, value: anytype) !bool {
    if (chan.closed.load(.acquire)) {
        return error.ChannelClosed;
    }

    chan.mutex.lock();
    defer chan.mutex.unlock();

    // Check if receiver waiting
    if (chan.recv_queue.dequeue(chan.allocator)) |receiver| {
        if (receiver.value_ptr) |ptr| {
            ptr.* = value;
        }
        receiver.task.state = .runnable;
        return true;
    }

    return false;
}

/// Try receive from unbuffered channel (non-blocking)
pub fn tryRecv(chan: anytype) ?@TypeOf(chan.buffer.?[0]) {
    chan.mutex.lock();
    defer chan.mutex.unlock();

    // Check if sender waiting
    if (chan.send_queue.dequeue(chan.allocator)) |sender| {
        const value = sender.value_ptr.?.*;
        sender.task.state = .runnable;
        return value;
    }

    return null;
}

/// Send with timeout
pub fn sendTimeout(chan: anytype, value: anytype, current_task: *Task, timeout_ns: u64) !void {
    const start_time = std.time.nanoTimestamp();

    if (chan.closed.load(.acquire)) {
        return error.ChannelClosed;
    }

    // Try fast path first
    {
        chan.mutex.lock();
        defer chan.mutex.unlock();

        if (chan.recv_queue.dequeue(chan.allocator)) |receiver| {
            if (receiver.value_ptr) |ptr| {
                ptr.* = value;
            }
            receiver.task.state = .runnable;
            return;
        }
    }

    // Slow path with timeout
    var value_holder = value;
    const max_spins: usize = 1000;
    var spin_count: usize = 0;

    while (true) {
        // Check timeout
        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now - start_time));
        if (elapsed >= timeout_ns) {
            return error.Timeout;
        }

        if (chan.closed.load(.acquire)) {
            return error.ChannelClosed;
        }

        {
            chan.mutex.lock();
            defer chan.mutex.unlock();

            if (chan.recv_queue.dequeue(chan.allocator)) |receiver| {
                if (receiver.value_ptr) |ptr| {
                    ptr.* = value_holder;
                }
                receiver.task.state = .runnable;
                return;
            }
        }

        if (spin_count < max_spins) {
            spin_count += 1;
            std.atomic.spinLoopHint();
            continue;
        }

        {
            chan.mutex.lock();
            defer chan.mutex.unlock();
            try chan.send_queue.enqueue(chan.allocator, current_task, &value_holder);
        }

        current_task.state = .waiting;
        current_task.recordYield();
        std.Thread.sleep(1000);

        if (current_task.state == .runnable) {
            current_task.state = .running;
            return;
        }

        spin_count = 0;
    }
}

/// Receive with timeout
pub fn recvTimeout(
    chan: anytype,
    current_task: *Task,
    timeout_ns: u64,
) !@TypeOf(chan.buffer.?[0]) {
    const T = @TypeOf(chan.buffer.?[0]);
    const start_time = std.time.nanoTimestamp();

    // Try fast path
    {
        chan.mutex.lock();
        defer chan.mutex.unlock();

        if (chan.send_queue.dequeue(chan.allocator)) |sender| {
            const value = sender.value_ptr.?.*;
            sender.task.state = .runnable;
            return value;
        }

        if (chan.closed.load(.acquire)) {
            return error.ChannelClosed;
        }
    }

    // Slow path with timeout
    var value_holder: T = undefined;
    const max_spins: usize = 1000;
    var spin_count: usize = 0;

    while (true) {
        // Check timeout
        const now = std.time.nanoTimestamp();
        const elapsed = @as(u64, @intCast(now - start_time));
        if (elapsed >= timeout_ns) {
            return error.Timeout;
        }

        {
            chan.mutex.lock();
            defer chan.mutex.unlock();

            if (chan.send_queue.dequeue(chan.allocator)) |sender| {
                const value = sender.value_ptr.?.*;
                sender.task.state = .runnable;
                return value;
            }

            if (chan.closed.load(.acquire)) {
                return error.ChannelClosed;
            }
        }

        if (spin_count < max_spins) {
            spin_count += 1;
            std.atomic.spinLoopHint();
            continue;
        }

        {
            chan.mutex.lock();
            defer chan.mutex.unlock();
            try chan.recv_queue.enqueue(chan.allocator, current_task, &value_holder);
        }

        current_task.state = .waiting;
        current_task.recordYield();
        std.Thread.sleep(1000);

        if (current_task.state == .runnable) {
            current_task.state = .running;
            return value_holder;
        }

        spin_count = 0;
    }
}
