//! Condition - Condition variable object
//!
//! CPython source: Lib/threading.py (Condition class)

const std = @import("std");
const Lock = @import("lock.zig").Lock;

/// A condition variable
pub const Condition = struct {
    const Self = @This();

    lock: *Lock,
    waiters: std.ArrayList(*std.Thread.Condition),
    allocator: std.mem.Allocator,
    internal_cond: std.Thread.Condition,

    pub fn init(allocator: std.mem.Allocator, lock: ?*Lock) !Self {
        const l = lock orelse blk: {
            const new_lock = try allocator.create(Lock);
            new_lock.* = Lock.init();
            break :blk new_lock;
        };

        return .{
            .allocator = allocator,
            .lock = l,
            .waiters = .{},
            .internal_cond = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.waiters.deinit(self.allocator);
    }

    /// Acquire the underlying lock
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        return self.lock.acquire(blocking, timeout);
    }

    /// Release the underlying lock
    pub fn release(self: *Self) void {
        self.lock.release();
    }

    /// Wait until notified
    pub fn wait(self: *Self, timeout: ?f64) bool {
        _ = timeout;
        self.internal_cond.wait(&self.lock.mutex);
        return true;
    }

    /// Wait until a predicate becomes true
    pub fn waitFor(self: *Self, predicate: *const fn () bool, timeout: ?f64) bool {
        _ = timeout;
        while (!predicate()) {
            self.internal_cond.wait(&self.lock.mutex);
        }
        return true;
    }

    /// Wake up one waiting thread
    pub fn notify(self: *Self) void {
        self.internal_cond.signal();
    }

    /// Wake up all waiting threads
    pub fn notifyAll(self: *Self) void {
        self.internal_cond.broadcast();
    }
};
