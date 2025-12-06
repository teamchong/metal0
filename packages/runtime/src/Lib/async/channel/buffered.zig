const std = @import("std");
const Task = @import("../task.zig").Task;
const TaskState = @import("../task.zig").TaskState;

/// Send on buffered channel
pub fn send(chan: anytype, value: anytype, current_task: *Task) !void {
    if (chan.closed.load(.acquire)) {
        return error.ChannelClosed;
    }

    // Try fast path: buffer has space
    {
        chan.mutex.lock();
        defer chan.mutex.unlock();

        // Check if receiver waiting (direct handoff is faster)
        if (chan.recv_queue.dequeue(chan.allocator)) |receiver| {
            if (receiver.value_ptr) |ptr| {
                ptr.* = value;
            }
            receiver.task.state = .runnable;
            return;
        }

        // Try to add to buffer
        if (chan.size < chan.capacity) {
            chan.buffer.?[chan.tail] = value;
            chan.tail = (chan.tail + 1) % chan.capacity;
            chan.size += 1;
            return;
        }
    }

    // Slow path: buffer full, block until space available
    var value_holder = value;
    const max_spins: usize = 1000;
    var spin_count: usize = 0;

    while (true) {
        if (chan.closed.load(.acquire)) {
            return error.ChannelClosed;
        }

        // Try again
        {
            chan.mutex.lock();
            defer chan.mutex.unlock();

            // Check receiver first
            if (chan.recv_queue.dequeue(chan.allocator)) |receiver| {
                if (receiver.value_ptr) |ptr| {
                    ptr.* = value_holder;
                }
                receiver.task.state = .runnable;
                return;
            }

            // Check buffer space
            if (chan.size < chan.capacity) {
                chan.buffer.?[chan.tail] = value_holder;
                chan.tail = (chan.tail + 1) % chan.capacity;
                chan.size += 1;
                return;
            }
        }

        // Buffer still full - decide whether to spin or yield
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

            // Try to send our value now
            {
                chan.mutex.lock();
                defer chan.mutex.unlock();

                if (chan.size < chan.capacity) {
                    chan.buffer.?[chan.tail] = value_holder;
                    chan.tail = (chan.tail + 1) % chan.capacity;
                    chan.size += 1;
                    return;
                }
            }
        }

        spin_count = 0;
    }
}

/// Receive from buffered channel
pub fn recv(chan: anytype, current_task: *Task) !@TypeOf(chan.buffer.?[0]) {
    const T = @TypeOf(chan.buffer.?[0]);

    // Try fast path: buffer has data
    {
        chan.mutex.lock();
        defer chan.mutex.unlock();

        if (chan.size > 0) {
            const value = chan.buffer.?[chan.head];
            chan.head = (chan.head + 1) % chan.capacity;
            chan.size -= 1;

            // Wake waiting sender if any
            if (chan.send_queue.dequeue(chan.allocator)) |sender| {
                sender.task.state = .runnable;
            }

            return value;
        }

        // Check if sender waiting (direct handoff)
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

    // Slow path: buffer empty, block until data available
    var value_holder: T = undefined;
    const max_spins: usize = 1000;
    var spin_count: usize = 0;

    while (true) {
        // Try again
        {
            chan.mutex.lock();
            defer chan.mutex.unlock();

            // Check buffer
            if (chan.size > 0) {
                const value = chan.buffer.?[chan.head];
                chan.head = (chan.head + 1) % chan.capacity;
                chan.size -= 1;

                if (chan.send_queue.dequeue(chan.allocator)) |sender| {
                    sender.task.state = .runnable;
                }

                return value;
            }

            // Check sender
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

        // Buffer still empty - decide whether to spin or yield
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

        // Check if we were woken up
        if (current_task.state == .runnable) {
            current_task.state = .running;

            // Check if we got a value
            {
                chan.mutex.lock();
                defer chan.mutex.unlock();

                if (chan.size > 0) {
                    const value = chan.buffer.?[chan.head];
                    chan.head = (chan.head + 1) % chan.capacity;
                    chan.size -= 1;
                    return value;
                }
            }

            // Might have received via direct handoff
            return value_holder;
        }

        spin_count = 0;
    }
}

/// Try send on buffered channel (non-blocking)
pub fn trySend(chan: anytype, value: anytype) !bool {
    if (chan.closed.load(.acquire)) {
        return error.ChannelClosed;
    }

    chan.mutex.lock();
    defer chan.mutex.unlock();

    // Check receiver first
    if (chan.recv_queue.dequeue(chan.allocator)) |receiver| {
        if (receiver.value_ptr) |ptr| {
            ptr.* = value;
        }
        receiver.task.state = .runnable;
        return true;
    }

    // Check buffer space
    if (chan.size < chan.capacity) {
        chan.buffer.?[chan.tail] = value;
        chan.tail = (chan.tail + 1) % chan.capacity;
        chan.size += 1;
        return true;
    }

    return false;
}

/// Try receive from buffered channel (non-blocking)
pub fn tryRecv(chan: anytype) ?@TypeOf(chan.buffer.?[0]) {
    chan.mutex.lock();
    defer chan.mutex.unlock();

    // Check buffer first
    if (chan.size > 0) {
        const value = chan.buffer.?[chan.head];
        chan.head = (chan.head + 1) % chan.capacity;
        chan.size -= 1;

        // Wake waiting sender
        if (chan.send_queue.dequeue(chan.allocator)) |sender| {
            sender.task.state = .runnable;
        }

        return value;
    }

    // Check sender
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

    // Try fast path
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

        if (chan.size < chan.capacity) {
            chan.buffer.?[chan.tail] = value;
            chan.tail = (chan.tail + 1) % chan.capacity;
            chan.size += 1;
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

            if (chan.size < chan.capacity) {
                chan.buffer.?[chan.tail] = value_holder;
                chan.tail = (chan.tail + 1) % chan.capacity;
                chan.size += 1;
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

            {
                chan.mutex.lock();
                defer chan.mutex.unlock();

                if (chan.size < chan.capacity) {
                    chan.buffer.?[chan.tail] = value_holder;
                    chan.tail = (chan.tail + 1) % chan.capacity;
                    chan.size += 1;
                    return;
                }
            }
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

        if (chan.size > 0) {
            const value = chan.buffer.?[chan.head];
            chan.head = (chan.head + 1) % chan.capacity;
            chan.size -= 1;

            if (chan.send_queue.dequeue(chan.allocator)) |sender| {
                sender.task.state = .runnable;
            }

            return value;
        }

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

            if (chan.size > 0) {
                const value = chan.buffer.?[chan.head];
                chan.head = (chan.head + 1) % chan.capacity;
                chan.size -= 1;

                if (chan.send_queue.dequeue(chan.allocator)) |sender| {
                    sender.task.state = .runnable;
                }

                return value;
            }

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

            {
                chan.mutex.lock();
                defer chan.mutex.unlock();

                if (chan.size > 0) {
                    const value = chan.buffer.?[chan.head];
                    chan.head = (chan.head + 1) % chan.capacity;
                    chan.size -= 1;
                    return value;
                }
            }

            return value_holder;
        }

        spin_count = 0;
    }
}
