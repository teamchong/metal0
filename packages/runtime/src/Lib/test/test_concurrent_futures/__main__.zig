//! test.test_concurrent_futures - Concurrent futures tests
const std = @import("std");

pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();
        
        state: State = .pending,
        result: ?T = null,
        exception: ?anyerror = null,
        callbacks: std.ArrayList(*const fn (?T, ?anyerror) void),
        allocator: std.mem.Allocator,
        
        pub const State = enum { pending, running, cancelled, finished };
        
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .callbacks = std.ArrayList(*const fn (?T, ?anyerror) void).init(allocator),
            };
        }
        
        pub fn deinit(self: *Self) void {
            self.callbacks.deinit();
        }
        
        pub fn cancel(self: *Self) bool {
            if (self.state == .pending) {
                self.state = .cancelled;
                return true;
            }
            return false;
        }
        
        pub fn cancelled(self: Self) bool {
            return self.state == .cancelled;
        }
        
        pub fn running(self: Self) bool {
            return self.state == .running;
        }
        
        pub fn done(self: Self) bool {
            return self.state == .finished or self.state == .cancelled;
        }
        
        pub fn setResult(self: *Self, value: T) void {
            self.result = value;
            self.state = .finished;
            for (self.callbacks.items) |cb| cb(value, null);
        }
        
        pub fn setException(self: *Self, err: anyerror) void {
            self.exception = err;
            self.state = .finished;
            for (self.callbacks.items) |cb| cb(null, err);
        }
        
        pub fn getResult(self: Self) !T {
            if (self.exception) |e| return e;
            if (self.result) |r| return r;
            return error.InvalidState;
        }
        
        pub fn addDoneCallback(self: *Self, cb: *const fn (?T, ?anyerror) void) !void {
            try self.callbacks.append(cb);
        }
    };
}

pub fn ThreadPoolExecutor(comptime max_workers: usize) type {
    return struct {
        const Self = @This();
        
        workers: usize = max_workers,
        shutdown_: bool = false,
        
        pub fn init() Self {
            return .{};
        }
        
        pub fn submit(self: *Self, comptime T: type, allocator: std.mem.Allocator, func: *const fn () T) !*Future(T) {
            _ = self;
            var future = try allocator.create(Future(T));
            future.* = Future(T).init(allocator);
            future.state = .running;
            const result = func();
            future.setResult(result);
            return future;
        }
        
        pub fn shutdown(self: *Self, wait: bool) void {
            _ = wait;
            self.shutdown_ = true;
        }
        
        pub fn isShutdown(self: Self) bool {
            return self.shutdown_;
        }
    };
}

pub fn ProcessPoolExecutor(comptime max_workers: usize) type {
    return ThreadPoolExecutor(max_workers);
}

test "future_init" {
    var f = Future(i32).init(std.testing.allocator);
    defer f.deinit();
    try std.testing.expectEqual(Future(i32).State.pending, f.state);
    try std.testing.expect(!f.done());
}

test "future_cancel" {
    var f = Future(i32).init(std.testing.allocator);
    defer f.deinit();
    try std.testing.expect(f.cancel());
    try std.testing.expect(f.cancelled());
    try std.testing.expect(f.done());
}

test "future_set_result" {
    var f = Future(i32).init(std.testing.allocator);
    defer f.deinit();
    f.setResult(42);
    try std.testing.expect(f.done());
    try std.testing.expectEqual(@as(i32, 42), try f.getResult());
}

test "thread_pool_executor" {
    var pool = ThreadPoolExecutor(4).init();
    try std.testing.expect(!pool.isShutdown());
    pool.shutdown(true);
    try std.testing.expect(pool.isShutdown());
}
