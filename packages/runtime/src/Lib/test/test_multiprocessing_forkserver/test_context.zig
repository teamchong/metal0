//! test.test_multiprocessing_forkserver.test_context - Multiprocessing context tests (forkserver mode)
const std = @import("std");

/// Start methods for process creation
pub const StartMethod = enum {
    spawn,
    fork,
    forkserver,

    pub fn available() []const StartMethod {
        return &[_]StartMethod{ .spawn, .fork, .forkserver };
    }

    pub fn default() StartMethod {
        return .forkserver;
    }
};

/// Context for multiprocessing - determines how processes are started
pub const Context = struct {
    method: StartMethod,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, method: StartMethod) Context {
        return .{
            .method = method,
            .allocator = allocator,
        };
    }

    pub fn Process(self: *Context) type {
        _ = self;
        return ProcessType;
    }

    pub fn Queue(self: *Context, comptime T: type) type {
        _ = self;
        return QueueType(T);
    }

    pub fn Lock(self: *Context) type {
        _ = self;
        return LockType;
    }

    pub fn Event(self: *Context) type {
        _ = self;
        return EventType;
    }

    pub fn Semaphore(self: *Context) type {
        _ = self;
        return SemaphoreType;
    }

    pub fn Barrier(self: *Context) type {
        _ = self;
        return BarrierType;
    }

    pub fn Value(self: *Context, comptime T: type) type {
        _ = self;
        return ValueType(T);
    }

    pub fn Array(self: *Context, comptime T: type) type {
        _ = self;
        return ArrayType(T);
    }
};

/// Process type stub
const ProcessType = struct {
    name: ?[]const u8 = null,
    pub fn start(self: *ProcessType) void {
        _ = self;
    }
    pub fn join(self: *ProcessType) void {
        _ = self;
    }
};

/// Queue type stub
fn QueueType(comptime T: type) type {
    return struct {
        items: std.ArrayList(T),
        pub fn put(self: *@This(), item: T) !void {
            try self.items.append(item);
        }
        pub fn get(self: *@This()) !T {
            return self.items.orderedRemove(0);
        }
    };
}

/// Lock type
const LockType = struct {
    locked: bool = false,
    pub fn acquire(self: *LockType) void {
        self.locked = true;
    }
    pub fn release(self: *LockType) void {
        self.locked = false;
    }
};

/// Event type
const EventType = struct {
    is_set: bool = false,
    pub fn set(self: *EventType) void {
        self.is_set = true;
    }
    pub fn clear(self: *EventType) void {
        self.is_set = false;
    }
    pub fn wait(self: *EventType) void {
        while (!self.is_set) {}
    }
};

/// Semaphore type
const SemaphoreType = struct {
    value: i32 = 1,
    pub fn acquire(self: *SemaphoreType) void {
        self.value -= 1;
    }
    pub fn release(self: *SemaphoreType) void {
        self.value += 1;
    }
};

/// Barrier type
const BarrierType = struct {
    parties: usize,
    count: usize = 0,
    pub fn wait(self: *BarrierType) usize {
        self.count += 1;
        return self.count;
    }
    pub fn reset(self: *BarrierType) void {
        self.count = 0;
    }
};

/// Shared value type
fn ValueType(comptime T: type) type {
    return struct {
        value: T,
        pub fn get(self: *@This()) T {
            return self.value;
        }
        pub fn set(self: *@This(), v: T) void {
            self.value = v;
        }
    };
}

/// Shared array type
fn ArrayType(comptime T: type) type {
    return struct {
        data: []T,
        pub fn get(self: *@This(), index: usize) T {
            return self.data[index];
        }
        pub fn set(self: *@This(), index: usize, value: T) void {
            self.data[index] = value;
        }
    };
}

/// Get default context
pub fn get_context(method: ?StartMethod) Context {
    return Context.init(std.heap.page_allocator, method orelse .forkserver);
}

/// Get all available start methods
pub fn get_all_start_methods() []const StartMethod {
    return StartMethod.available();
}

/// Get default start method
pub fn get_start_method() StartMethod {
    return StartMethod.default();
}

/// Set default start method (no-op in this implementation)
pub fn set_start_method(method: StartMethod) void {
    _ = method;
}

test "context creation" {
    const ctx = get_context(null);
    try std.testing.expectEqual(StartMethod.forkserver, ctx.method);
}

test "context with specific method" {
    const ctx = get_context(.fork);
    try std.testing.expectEqual(StartMethod.fork, ctx.method);
}

test "available start methods" {
    const methods = get_all_start_methods();
    try std.testing.expectEqual(@as(usize, 3), methods.len);
}

test "lock type" {
    var lock = LockType{};
    try std.testing.expect(!lock.locked);
    lock.acquire();
    try std.testing.expect(lock.locked);
    lock.release();
    try std.testing.expect(!lock.locked);
}

test "event type" {
    var event = EventType{};
    try std.testing.expect(!event.is_set);
    event.set();
    try std.testing.expect(event.is_set);
    event.clear();
    try std.testing.expect(!event.is_set);
}

test "semaphore type" {
    var sem = SemaphoreType{ .value = 2 };
    try std.testing.expectEqual(@as(i32, 2), sem.value);
    sem.acquire();
    try std.testing.expectEqual(@as(i32, 1), sem.value);
    sem.release();
    try std.testing.expectEqual(@as(i32, 2), sem.value);
}
