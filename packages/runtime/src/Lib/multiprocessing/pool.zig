//! Pool - Worker pool for parallel execution
const std = @import("std");
const process_mod = @import("process.zig");
const Process = process_mod.Process;

// Forward declaration for getCpuCount
fn getCpuCount() usize {
    return std.Thread.getCpuCount() catch 1;
}

/// A pool of worker processes
pub const Pool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    processes: i32,
    workers: std.ArrayList(Process),
    closed: bool,
    terminated: bool,

    pub fn init(allocator: std.mem.Allocator, processes: ?i32) Self {
        const num_processes = processes orelse @as(i32, @intCast(getCpuCount()));
        return .{
            .allocator = allocator,
            .processes = num_processes,
            .workers = std.ArrayList(Process){},
            .closed = false,
            .terminated = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.workers.items) |*worker| {
            worker.deinit();
        }
        self.workers.deinit(self.allocator);
    }

    /// Apply a function to arguments (blocking)
    pub fn apply(self: *Self, func: *const fn () void, args: ?[]const []const u8) !void {
        if (self.closed) return error.PoolClosed;
        _ = args;
        func();
    }

    /// Apply function asynchronously
    pub fn applyAsync(self: *Self, func: *const fn () void, args: ?[]const []const u8) !AsyncResult {
        if (self.closed) return error.PoolClosed;

        var proc = Process.init(self.allocator, func, null, args, false);
        try proc.start();
        try self.workers.append(self.allocator, proc);

        return AsyncResult{
            .process = &self.workers.items[self.workers.items.len - 1],
        };
    }

    /// Map function over iterable
    pub fn map(self: *Self, func: *const fn ([]const u8) []const u8, iterable: []const []const u8) ![][]const u8 {
        if (self.closed) return error.PoolClosed;

        var results = try self.allocator.alloc([]const u8, iterable.len);
        for (iterable, 0..) |item, i| {
            results[i] = func(item);
        }
        return results;
    }

    /// Map function asynchronously
    pub fn mapAsync(self: *Self, func: *const fn ([]const u8) []const u8, iterable: []const []const u8) !MapResult {
        if (self.closed) return error.PoolClosed;

        return MapResult{
            .allocator = self.allocator,
            .func = func,
            .iterable = iterable,
            .ready = false,
        };
    }

    /// Close the pool (no new tasks)
    pub fn close(self: *Self) void {
        self.closed = true;
    }

    /// Terminate all workers
    pub fn terminate(self: *Self) void {
        for (self.workers.items) |*worker| {
            worker.terminate() catch {};
        }
        self.terminated = true;
    }

    /// Wait for workers to finish
    pub fn join(self: *Self) !void {
        if (!self.closed) return error.PoolNotClosed;

        for (self.workers.items) |*worker| {
            try worker.join(null);
        }
    }
};

/// Async result from pool.apply_async
pub const AsyncResult = struct {
    process: *Process,

    pub fn get(self: *AsyncResult, timeout: ?f64) !void {
        try self.process.join(timeout);
    }

    pub fn ready(self: *AsyncResult) bool {
        return !self.process.isAlive();
    }

    pub fn successful(self: *AsyncResult) bool {
        if (self.process.exitcode) |code| {
            return code == 0;
        }
        return false;
    }

    pub fn wait(self: *AsyncResult, timeout: ?f64) !void {
        try self.process.join(timeout);
    }
};

/// Map result from pool.map_async
pub const MapResult = struct {
    allocator: std.mem.Allocator,
    func: *const fn ([]const u8) []const u8,
    iterable: []const []const u8,
    ready: bool,

    pub fn get(self: *MapResult, timeout: ?f64) ![][]const u8 {
        _ = timeout;
        var results = try self.allocator.alloc([]const u8, self.iterable.len);
        for (self.iterable, 0..) |item, i| {
            results[i] = self.func(item);
        }
        self.ready = true;
        return results;
    }

    pub fn isReady(self: *MapResult) bool {
        return self.ready;
    }
};
