const std = @import("std");
const Future = @import("../future.zig").Future;
const Poll = @import("../future.zig").Poll;
const Waker = @import("../future.zig").Waker;
const Context = @import("../future.zig").Context;
const Task = @import("../task.zig").Task;
const poll_mod = @import("poll.zig");

/// Map future value to new type
pub fn map(
    comptime T: type,
    comptime U: type,
    future: *Future(T),
    func: *const fn (T) U,
    allocator: std.mem.Allocator,
) !*Future(U) {
    const mapped = try Future(U).init(allocator);

    // Create task to poll original future and map result
    const MapContext = struct {
        source: *Future(T),
        dest: *Future(U),
        mapper: *const fn (T) U,

        fn poll_and_map(self: *@This(), task: *Task) void {
            const result = poll_mod.pollOnce(T, self.source, task);
            if (result.isReady()) {
                const mapped_value = self.mapper(result.unwrap());
                self.dest.resolve(mapped_value);
            }
        }
    };

    const ctx = try allocator.create(MapContext);
    ctx.* = MapContext{
        .source = future,
        .dest = mapped,
        .mapper = func,
    };

    // For now, eagerly poll once
    // In a real implementation, this would be scheduled
    if (future.isReady()) {
        const value = future.tryGet().?;
        mapped.resolve(func(value));
    }

    return mapped;
}

/// Chain futures (then combinator)
pub fn then(
    comptime T: type,
    comptime U: type,
    future: *Future(T),
    func: *const fn (T) anyerror!*Future(U),
    allocator: std.mem.Allocator,
) !*Future(U) {
    const chained = try Future(U).init(allocator);

    // Similar to map, but func returns a future
    if (future.isReady()) {
        const value = future.tryGet().?;
        const next_future = try func(value);

        // Chain the result
        if (next_future.isReady()) {
            const final_value = next_future.tryGet().?;
            chained.resolve(final_value);
        }
    }

    return chained;
}

/// Join two futures (wait for both)
pub fn join(
    comptime A: type,
    comptime B: type,
    f1: *Future(A),
    f2: *Future(B),
    allocator: std.mem.Allocator,
    current_task: *Task,
) !struct { A, B } {
    _ = allocator;

    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    var result1: ?A = null;
    var result2: ?B = null;

    // Poll both futures until ready
    while (result1 == null or result2 == null) {
        if (result1 == null) {
            const poll1 = f1.poll(&ctx);
            if (poll1.isReady()) {
                result1 = poll1.unwrap();
            }
        }

        if (result2 == null) {
            const poll2 = f2.poll(&ctx);
            if (poll2.isReady()) {
                result2 = poll2.unwrap();
            }
        }

        // Yield if both still pending
        if (result1 == null or result2 == null) {
            poll_mod.yieldNow(current_task);
        }
    }

    return .{ result1.?, result2.? };
}

/// Join all futures in array
pub fn joinAll(
    comptime T: type,
    futures: []*Future(T),
    allocator: std.mem.Allocator,
    current_task: *Task,
) ![]T {
    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    var results = try allocator.alloc(T, futures.len);
    var completed = try allocator.alloc(bool, futures.len);
    defer allocator.free(completed);

    // Initialize completed flags
    for (completed) |*c| {
        c.* = false;
    }

    var all_complete = false;

    while (!all_complete) {
        all_complete = true;

        for (futures, 0..) |future, i| {
            if (!completed[i]) {
                const poll_result = future.poll(&ctx);
                if (poll_result.isReady()) {
                    results[i] = poll_result.unwrap();
                    completed[i] = true;
                } else {
                    all_complete = false;
                }
            }
        }

        if (!all_complete) {
            poll_mod.yieldNow(current_task);
        }
    }

    return results;
}

/// Race futures (return first to complete)
pub fn race(
    comptime T: type,
    futures: []*Future(T),
    allocator: std.mem.Allocator,
    current_task: *Task,
) !T {
    _ = allocator;

    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    while (true) {
        // Poll all futures, return first ready
        for (futures) |future| {
            const poll_result = future.poll(&ctx);
            if (poll_result.isReady()) {
                return poll_result.unwrap();
            }
        }

        // All pending, yield
        poll_mod.yieldNow(current_task);
    }
}

/// Select first future to complete (returns index and value)
pub fn select(
    comptime T: type,
    futures: []*Future(T),
    allocator: std.mem.Allocator,
    current_task: *Task,
) !struct { usize, T } {
    _ = allocator;

    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    while (true) {
        // Poll all futures, return first ready with index
        for (futures, 0..) |future, i| {
            const poll_result = future.poll(&ctx);
            if (poll_result.isReady()) {
                return .{ i, poll_result.unwrap() };
            }
        }

        // All pending, yield
        poll_mod.yieldNow(current_task);
    }
}

/// Join 3 futures
pub fn join3(
    comptime A: type,
    comptime B: type,
    comptime C: type,
    f1: *Future(A),
    f2: *Future(B),
    f3: *Future(C),
    allocator: std.mem.Allocator,
    current_task: *Task,
) !struct { A, B, C } {
    _ = allocator;

    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    var result1: ?A = null;
    var result2: ?B = null;
    var result3: ?C = null;

    while (result1 == null or result2 == null or result3 == null) {
        if (result1 == null) {
            const poll1 = f1.poll(&ctx);
            if (poll1.isReady()) {
                result1 = poll1.unwrap();
            }
        }

        if (result2 == null) {
            const poll2 = f2.poll(&ctx);
            if (poll2.isReady()) {
                result2 = poll2.unwrap();
            }
        }

        if (result3 == null) {
            const poll3 = f3.poll(&ctx);
            if (poll3.isReady()) {
                result3 = poll3.unwrap();
            }
        }

        if (result1 == null or result2 == null or result3 == null) {
            poll_mod.yieldNow(current_task);
        }
    }

    return .{ result1.?, result2.?, result3.? };
}

/// Join 4 futures
pub fn join4(
    comptime A: type,
    comptime B: type,
    comptime C: type,
    comptime D: type,
    f1: *Future(A),
    f2: *Future(B),
    f3: *Future(C),
    f4: *Future(D),
    allocator: std.mem.Allocator,
    current_task: *Task,
) !struct { A, B, C, D } {
    _ = allocator;

    var waker = Waker.init(current_task);
    const ctx = Context.init(&waker);

    var result1: ?A = null;
    var result2: ?B = null;
    var result3: ?C = null;
    var result4: ?D = null;

    while (result1 == null or result2 == null or result3 == null or result4 == null) {
        if (result1 == null) {
            const poll1 = f1.poll(&ctx);
            if (poll1.isReady()) result1 = poll1.unwrap();
        }
        if (result2 == null) {
            const poll2 = f2.poll(&ctx);
            if (poll2.isReady()) result2 = poll2.unwrap();
        }
        if (result3 == null) {
            const poll3 = f3.poll(&ctx);
            if (poll3.isReady()) result3 = poll3.unwrap();
        }
        if (result4 == null) {
            const poll4 = f4.poll(&ctx);
            if (poll4.isReady()) result4 = poll4.unwrap();
        }

        if (result1 == null or result2 == null or result3 == null or result4 == null) {
            poll_mod.yieldNow(current_task);
        }
    }

    return .{ result1.?, result2.?, result3.?, result4.? };
}

/// FlatMap (map + flatten)
pub fn flatMap(
    comptime T: type,
    comptime U: type,
    future: *Future(T),
    func: *const fn (T) anyerror!*Future(U),
    allocator: std.mem.Allocator,
) !*Future(U) {
    return then(T, U, future, func, allocator);
}

/// Zip two futures (same as join but returns tuple)
pub fn zip(
    comptime A: type,
    comptime B: type,
    f1: *Future(A),
    f2: *Future(B),
    allocator: std.mem.Allocator,
    current_task: *Task,
) !struct { A, B } {
    return join(A, B, f1, f2, allocator, current_task);
}

/// AndThen (sequence futures)
pub fn andThen(
    comptime T: type,
    comptime U: type,
    future: *Future(T),
    func: *const fn (T) anyerror!*Future(U),
    allocator: std.mem.Allocator,
) !*Future(U) {
    return then(T, U, future, func, allocator);
}
