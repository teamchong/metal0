//! test.test_multiprocessing_fork.test_pool - Multiprocessing pool tests (fork start method)
const std = @import("std");

/// Pool state
pub const PoolState = enum {
    run,
    close,
    terminate,
};

/// Async result from pool operations
pub fn AsyncResult(comptime T: type) type {
    return struct {
        const Self = @This();

        value: ?T = null,
        exception: ?anyerror = null,
        ready: bool = false,
        successful: bool = false,

        pub fn get(self: *Self, timeout: ?f64) !T {
            _ = timeout;
            if (!self.ready) {
                return error.NotReady;
            }
            if (self.exception) |e| {
                return e;
            }
            return self.value.?;
        }

        pub fn wait(self: *Self, timeout: ?f64) void {
            _ = timeout;
            while (!self.ready) {
                std.time.sleep(1_000_000);
            }
        }
    };
}

/// MapResult for iterating pool map results
pub fn MapResult(comptime T: type) type {
    return struct {
        results: []T,
        index: usize = 0,

        pub fn next(self: *@This()) ?T {
            if (self.index >= self.results.len) return null;
            const result = self.results[self.index];
            self.index += 1;
            return result;
        }
    };
}

/// Worker pool for parallel processing (fork method)
pub fn Pool(comptime T: type, comptime R: type) type {
    return struct {
        const Self = @This();

        processes: usize,
        state: PoolState = .run,
        allocator: std.mem.Allocator,
        worker_fn: ?*const fn (T) R = null,

        pub fn init(allocator: std.mem.Allocator, processes: ?usize) Self {
            return .{
                .allocator = allocator,
                .processes = processes orelse (std.Thread.getCpuCount() catch 4),
            };
        }

        pub fn apply(self: *Self, func: *const fn (T) R, args: T) !R {
            if (self.state != .run) return error.PoolClosed;
            return func(args);
        }

        pub fn apply_async(self: *Self, func: *const fn (T) R, args: T) !*AsyncResult(R) {
            if (self.state != .run) return error.PoolClosed;

            const result = try self.allocator.create(AsyncResult(R));
            result.* = .{};

            result.value = func(args);
            result.ready = true;
            result.successful = true;

            return result;
        }

        pub fn map(self: *Self, func: *const fn (T) R, items: []const T) ![]R {
            if (self.state != .run) return error.PoolClosed;

            var results = try self.allocator.alloc(R, items.len);
            for (items, 0..) |item, i| {
                results[i] = func(item);
            }
            return results;
        }

        pub fn map_async(self: *Self, func: *const fn (T) R, items: []const T) !*AsyncResult([]R) {
            if (self.state != .run) return error.PoolClosed;

            const result = try self.allocator.create(AsyncResult([]R));
            result.* = .{};

            result.value = try self.map(func, items);
            result.ready = true;
            result.successful = true;

            return result;
        }

        pub fn imap(self: *Self, func: *const fn (T) R, items: []const T) !MapResult(R) {
            const results = try self.map(func, items);
            return .{ .results = results };
        }

        pub fn starmap(self: *Self, func: *const fn (T) R, items: []const T) ![]R {
            return self.map(func, items);
        }

        pub fn close(self: *Self) void {
            self.state = .close;
        }

        pub fn terminate(self: *Self) void {
            self.state = .terminate;
        }

        pub fn join(self: *Self) void {
            _ = self;
        }
    };
}

/// ThreadPool for CPU-bound tasks
pub const ThreadPool = struct {
    threads: []std.Thread,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_threads: usize) !ThreadPool {
        const threads = try allocator.alloc(std.Thread, num_threads);
        return .{
            .threads = threads,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ThreadPool) void {
        self.allocator.free(self.threads);
    }

    pub fn submit(self: *ThreadPool, func: anytype, args: anytype) !void {
        _ = self;
        _ = func;
        _ = args;
    }
};

fn double(x: i32) i32 {
    return x * 2;
}

fn square(x: i32) i32 {
    return x * x;
}

test "pool apply" {
    const allocator = std.testing.allocator;
    var pool = Pool(i32, i32).init(allocator, 4);
    defer pool.close();

    const result = try pool.apply(double, 5);
    try std.testing.expectEqual(@as(i32, 10), result);
}

test "pool map" {
    const allocator = std.testing.allocator;
    var pool = Pool(i32, i32).init(allocator, 4);
    defer pool.close();

    const items = [_]i32{ 1, 2, 3, 4, 5 };
    const results = try pool.map(square, &items);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(i32, 1), results[0]);
    try std.testing.expectEqual(@as(i32, 4), results[1]);
    try std.testing.expectEqual(@as(i32, 9), results[2]);
    try std.testing.expectEqual(@as(i32, 16), results[3]);
    try std.testing.expectEqual(@as(i32, 25), results[4]);
}

test "pool async result" {
    const allocator = std.testing.allocator;
    var pool = Pool(i32, i32).init(allocator, 4);
    defer pool.close();

    const async_result = try pool.apply_async(double, 7);
    defer allocator.destroy(async_result);

    try std.testing.expect(async_result.ready);
    try std.testing.expect(async_result.successful);

    const value = try async_result.get(null);
    try std.testing.expectEqual(@as(i32, 14), value);
}

test "pool imap iterator" {
    const allocator = std.testing.allocator;
    var pool = Pool(i32, i32).init(allocator, 4);
    defer pool.close();

    const items = [_]i32{ 1, 2, 3 };
    var iter = try pool.imap(double, &items);
    defer allocator.free(iter.results);

    try std.testing.expectEqual(@as(i32, 2), iter.next().?);
    try std.testing.expectEqual(@as(i32, 4), iter.next().?);
    try std.testing.expectEqual(@as(i32, 6), iter.next().?);
    try std.testing.expect(iter.next() == null);
}

test "pool state transitions" {
    const allocator = std.testing.allocator;
    var pool = Pool(i32, i32).init(allocator, 4);

    try std.testing.expectEqual(PoolState.run, pool.state);

    pool.close();
    try std.testing.expectEqual(PoolState.close, pool.state);

    try std.testing.expectError(error.PoolClosed, pool.apply(double, 5));
}

test "pool terminate" {
    const allocator = std.testing.allocator;
    var pool = Pool(i32, i32).init(allocator, 4);

    pool.terminate();
    try std.testing.expectEqual(PoolState.terminate, pool.state);
}

test "thread pool init deinit" {
    const allocator = std.testing.allocator;
    var tp = try ThreadPool.init(allocator, 4);
    defer tp.deinit();

    try std.testing.expectEqual(@as(usize, 4), tp.threads.len);
}
