const std = @import("std");
const runtime = @import("runtime.zig");
const Task = @import("task.zig").Task;
const TaskState = @import("task.zig").TaskState;

/// Poll result (Tokio-style)
pub fn Poll(comptime T: type) type {
    return union(enum) {
        pending: void,
        ready: T,

        pub fn isReady(self: @This()) bool {
            return switch (self) {
                .ready => true,
                .pending => false,
            };
        }

        pub fn isPending(self: @This()) bool {
            return switch (self) {
                .ready => false,
                .pending => true,
            };
        }

        pub fn unwrap(self: @This()) T {
            return switch (self) {
                .ready => |value| value,
                .pending => @panic("Poll.unwrap() called on pending future"),
            };
        }
    };
}

/// Waker for waking blocked tasks
pub const Waker = struct {
    task: *Task,
    vtable: *const VTable,

    pub const VTable = struct {
        wake: *const fn (*Task) void,
        wake_by_ref: *const fn (*Task) void,
        drop: *const fn (*Task) void,
    };

    /// Default vtable using runtime scheduler
    const default_vtable = VTable{
        .wake = wakeTask,
        .wake_by_ref = wakeTaskByRef,
        .drop = dropWaker,
    };

    pub fn init(task: *Task) Waker {
        return Waker{
            .task = task,
            .vtable = &default_vtable,
        };
    }

    /// Wake the task (ownership transfer)
    pub fn wake(self: Waker) void {
        self.vtable.wake(self.task);
    }

    /// Wake the task (by reference)
    pub fn wakeByRef(self: *const Waker) void {
        self.vtable.wake_by_ref(self.task);
    }

    /// Drop the waker
    pub fn drop(self: Waker) void {
        self.vtable.drop(self.task);
    }

    // Default implementations
    fn wakeTask(task: *Task) void {
        task.state = .runnable;
        // Task will be picked up by scheduler on next poll
    }

    fn wakeTaskByRef(task: *Task) void {
        task.state = .runnable;
    }

    fn dropWaker(_: *Task) void {
        // No-op for basic waker
    }
};

/// Context passed to Future.poll()
pub const Context = struct {
    waker: *const Waker,

    pub fn init(waker: *const Waker) Context {
        return Context{ .waker = waker };
    }

    pub fn wake(self: *const Context) void {
        self.waker.wakeByRef();
    }
};

/// Future trait (Tokio-style)
pub fn Future(comptime T: type) type {
    return struct {
        state: State,
        value: ?T,
        error_value: ?anyerror,
        wakers: std.ArrayList(*const Waker),
        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex,

        const Self = @This();

        pub const State = enum {
            pending,
            ready,
            error_state,
            completed,
        };

        pub fn init(allocator: std.mem.Allocator) !*Self {
            const future = try allocator.create(Self);
            future.* = Self{
                .state = .pending,
                .value = null,
                .error_value = null,
                .wakers = std.ArrayList(*const Waker){},
                .allocator = allocator,
                .mutex = std.Thread.Mutex{},
            };
            return future;
        }

        pub fn deinit(self: *Self) void {
            self.wakers.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        /// Poll the future
        pub fn poll(self: *Self, ctx: *const Context) Poll(T) {
            self.mutex.lock();
            defer self.mutex.unlock();

            switch (self.state) {
                .pending => {
                    // Register waker
                    self.wakers.append(self.allocator, ctx.waker) catch {
                        // If append fails, continue without registering
                    };
                    return .{ .pending = {} };
                },
                .ready => {
                    return .{ .ready = self.value.? };
                },
                .error_state => {
                    // For now, panic on error
                    // TODO: Support error propagation
                    @panic("Future encountered error");
                },
                .completed => {
                    return .{ .ready = self.value.? };
                },
            }
        }

        /// Resolve future with value
        pub fn resolve(self: *Self, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state != .pending) {
                return; // Already resolved
            }

            self.value = value;
            self.state = .ready;

            // Wake all waiters
            for (self.wakers.items) |waker| {
                waker.wakeByRef();
            }
            self.wakers.clearRetainingCapacity();
        }

        /// Reject future with error
        pub fn reject(self: *Self, err: anyerror) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state != .pending) {
                return; // Already resolved
            }

            self.error_value = err;
            self.state = .error_state;

            // Wake all waiters
            for (self.wakers.items) |waker| {
                waker.wakeByRef();
            }
            self.wakers.clearRetainingCapacity();
        }

        /// Await future (blocks current task)
        pub fn await_future(self: *Self, current_task: *Task) !T {
            const poll_mod = @import("future/poll.zig");
            return poll_mod.awaitFuture(T, self, current_task);
        }

        /// Check if ready without blocking
        pub fn isReady(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.state == .ready or self.state == .completed;
        }

        /// Try to get value without blocking (returns null if pending)
        pub fn tryGet(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            return switch (self.state) {
                .ready, .completed => self.value,
                .pending, .error_state => null,
            };
        }

        /// Map future value to new type
        pub fn map(self: *Self, comptime U: type, func: *const fn (T) U) !*Future(U) {
            const combinator = @import("future/combinator.zig");
            return combinator.map(T, U, self, func, self.allocator);
        }

        /// Chain futures (then combinator)
        pub fn then(self: *Self, comptime U: type, func: *const fn (T) anyerror!*Future(U)) !*Future(U) {
            const combinator = @import("future/combinator.zig");
            return combinator.then(T, U, self, func, self.allocator);
        }
    };
}

/// Create a resolved future
pub fn resolved(comptime T: type, allocator: std.mem.Allocator, value: T) !*Future(T) {
    const future = try Future(T).init(allocator);
    future.resolve(value);
    return future;
}

/// Create a rejected future
pub fn rejected(comptime T: type, allocator: std.mem.Allocator, err: anyerror) !*Future(T) {
    const future = try Future(T).init(allocator);
    future.reject(err);
    return future;
}

/// Join two futures (wait for both)
pub fn join(
    comptime A: type,
    comptime B: type,
    allocator: std.mem.Allocator,
    f1: *Future(A),
    f2: *Future(B),
    current_task: *Task,
) !struct { A, B } {
    const combinator = @import("future/combinator.zig");
    return combinator.join(A, B, f1, f2, allocator, current_task);
}

/// Join all futures in array
pub fn joinAll(
    comptime T: type,
    allocator: std.mem.Allocator,
    futures: []*Future(T),
    current_task: *Task,
) ![]T {
    const combinator = @import("future/combinator.zig");
    return combinator.joinAll(T, futures, allocator, current_task);
}

/// Race futures (return first to complete)
pub fn race(
    comptime T: type,
    allocator: std.mem.Allocator,
    futures: []*Future(T),
    current_task: *Task,
) !T {
    const combinator = @import("future/combinator.zig");
    return combinator.race(T, futures, allocator, current_task);
}

/// Select first future to complete
pub fn select(
    comptime T: type,
    allocator: std.mem.Allocator,
    futures: []*Future(T),
    current_task: *Task,
) !struct { usize, T } {
    const combinator = @import("future/combinator.zig");
    return combinator.select(T, futures, allocator, current_task);
}
