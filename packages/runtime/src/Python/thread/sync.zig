/// sync - Synchronization Primitives
/// Condition variables, semaphores, events, and barriers.

const std = @import("std");
const types = @import("types.zig");
const locks = @import("locks.zig");

pub const LockStatus = types.LockStatus;
pub const Lock = locks.Lock;

// ============================================================================
// Condition Variable
// ============================================================================

pub const Condition = struct {
    cond: std.Thread.Condition = .{},

    const Self = @This();

    pub fn create() *Self {
        const cond = std.heap.c_allocator.create(Self) catch return undefined;
        cond.* = .{};
        return cond;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    /// Wait on condition with optional timeout
    pub fn wait(self: *Self, lock: *Lock, timeout_us: i64) LockStatus {
        if (timeout_us < 0) {
            self.cond.wait(&lock.mutex);
            return .acquired;
        }

        const timeout_ns: u64 = @intCast(timeout_us * 1000);
        const result = self.cond.timedWait(&lock.mutex, timeout_ns);
        if (result) {
            return .acquired;
        } else {
            return .timeout;
        }
    }

    /// Signal one waiting thread
    pub fn signal(self: *Self) void {
        self.cond.signal();
    }

    /// Signal all waiting threads
    pub fn broadcast(self: *Self) void {
        self.cond.broadcast();
    }
};

// ============================================================================
// Semaphore
// ============================================================================

pub const Semaphore = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    count: i32 = 0,

    const Self = @This();

    pub fn create(initial: i32) *Self {
        const sem = std.heap.c_allocator.create(Self) catch return undefined;
        sem.* = .{ .count = initial };
        return sem;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    pub fn acquire(self: *Self, timeout_us: i64) LockStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (timeout_us == 0) {
            // Non-blocking
            if (self.count > 0) {
                self.count -= 1;
                return .acquired;
            }
            return .failure;
        }

        if (timeout_us < 0) {
            // Infinite wait
            while (self.count <= 0) {
                self.cond.wait(&self.mutex);
            }
            self.count -= 1;
            return .acquired;
        }

        // Timed wait
        const start = std.time.nanoTimestamp();
        const timeout_ns = timeout_us * 1000;

        while (self.count <= 0) {
            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return .timeout;
            }

            const remaining: u64 = @intCast(timeout_ns - elapsed);
            _ = self.cond.timedWait(&self.mutex, remaining);
        }

        self.count -= 1;
        return .acquired;
    }

    pub fn release(self: *Self) void {
        self.mutex.lock();
        self.count += 1;
        self.cond.signal();
        self.mutex.unlock();
    }

    pub fn getValue(self: *Self) i32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }
};

// ============================================================================
// Event
// ============================================================================

/// Simple event for thread synchronization
pub const Event = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    is_set: bool = false,

    const Self = @This();

    pub fn create() *Self {
        const event = std.heap.c_allocator.create(Self) catch return undefined;
        event.* = .{};
        return event;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    pub fn set(self: *Self) void {
        self.mutex.lock();
        self.is_set = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        self.is_set = false;
        self.mutex.unlock();
    }

    pub fn isSet(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.is_set;
    }

    pub fn wait(self: *Self, timeout_us: i64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_set) {
            return true;
        }

        if (timeout_us == 0) {
            return self.is_set;
        }

        if (timeout_us < 0) {
            while (!self.is_set) {
                self.cond.wait(&self.mutex);
            }
            return true;
        }

        const start = std.time.nanoTimestamp();
        const timeout_ns = timeout_us * 1000;

        while (!self.is_set) {
            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return false;
            }

            const remaining: u64 = @intCast(timeout_ns - elapsed);
            _ = self.cond.timedWait(&self.mutex, remaining);
        }

        return true;
    }
};

// ============================================================================
// Barrier
// ============================================================================

/// Thread barrier for synchronization
pub const Barrier = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    parties: usize,
    count: usize = 0,
    generation: usize = 0,
    broken: bool = false,

    const Self = @This();

    pub fn create(parties: usize) *Self {
        const barrier = std.heap.c_allocator.create(Self) catch return undefined;
        barrier.* = .{ .parties = parties };
        return barrier;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    /// Wait at barrier, return index (0 to parties-1)
    pub fn wait(self: *Self, timeout_us: i64) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.broken) {
            return error.BrokenBarrier;
        }

        const gen = self.generation;
        const index = self.count;
        self.count += 1;

        if (self.count == self.parties) {
            // Last thread - release all
            self.count = 0;
            self.generation += 1;
            self.cond.broadcast();
            return index;
        }

        // Wait for release
        if (timeout_us < 0) {
            while (gen == self.generation and !self.broken) {
                self.cond.wait(&self.mutex);
            }
        } else {
            const start = std.time.nanoTimestamp();
            const timeout_ns = timeout_us * 1000;

            while (gen == self.generation and !self.broken) {
                const elapsed = std.time.nanoTimestamp() - start;
                if (elapsed >= timeout_ns) {
                    self.broken = true;
                    self.cond.broadcast();
                    return error.Timeout;
                }

                const remaining: u64 = @intCast(timeout_ns - elapsed);
                _ = self.cond.timedWait(&self.mutex, remaining);
            }
        }

        if (self.broken) {
            return error.BrokenBarrier;
        }

        return index;
    }

    pub fn reset(self: *Self) void {
        self.mutex.lock();
        self.count = 0;
        self.generation += 1;
        self.broken = false;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    pub fn abort(self: *Self) void {
        self.mutex.lock();
        self.broken = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    pub fn getParties(self: *Self) usize {
        return self.parties;
    }

    pub fn getWaiting(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }

    pub fn isBroken(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.broken;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "semaphore" {
    var sem = Semaphore{ .count = 2 };

    // Should succeed twice
    try std.testing.expect(sem.acquire(0) == .acquired);
    try std.testing.expect(sem.acquire(0) == .acquired);

    // Should fail now
    try std.testing.expect(sem.acquire(0) == .failure);

    // Release and try again
    sem.release();
    try std.testing.expect(sem.acquire(0) == .acquired);
}

test "event" {
    var event = Event{};

    try std.testing.expect(!event.isSet());

    event.set();
    try std.testing.expect(event.isSet());
    try std.testing.expect(event.wait(0));

    event.clear();
    try std.testing.expect(!event.isSet());
    try std.testing.expect(!event.wait(0));
}
