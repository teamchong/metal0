//! Lock and Synchronization primitives
const std = @import("std");

/// A process-safe lock (reentrant)
pub const Lock = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    locked: bool,

    pub fn init() Self {
        return .{
            .mutex = .{},
            .locked = false,
        };
    }

    pub fn acquire(self: *Self, block: bool, timeout: ?f64) bool {
        _ = timeout;
        if (block) {
            self.mutex.lock();
            self.locked = true;
            return true;
        } else {
            if (self.mutex.tryLock()) {
                self.locked = true;
                return true;
            }
            return false;
        }
    }

    pub fn release(self: *Self) void {
        self.locked = false;
        self.mutex.unlock();
    }
};

/// Reentrant lock
pub const RLock = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    owner: ?std.Thread.Id,
    count: usize,

    pub fn init() Self {
        return .{
            .mutex = .{},
            .owner = null,
            .count = 0,
        };
    }

    pub fn acquire(self: *Self, block: bool, timeout: ?f64) bool {
        _ = timeout;
        const tid = std.Thread.getCurrentId();

        if (self.owner == tid) {
            self.count += 1;
            return true;
        }

        if (block) {
            self.mutex.lock();
        } else {
            if (!self.mutex.tryLock()) {
                return false;
            }
        }

        self.owner = tid;
        self.count = 1;
        return true;
    }

    pub fn release(self: *Self) void {
        if (self.owner != std.Thread.getCurrentId()) {
            return; // Not owner
        }

        self.count -= 1;
        if (self.count == 0) {
            self.owner = null;
            self.mutex.unlock();
        }
    }
};

/// Condition variable
pub const Condition = struct {
    const Self = @This();

    cond: std.Thread.Condition,
    lock: *Lock,

    pub fn init(lock: *Lock) Self {
        return .{
            .cond = .{},
            .lock = lock,
        };
    }

    pub fn wait(self: *Self, timeout: ?f64) bool {
        if (timeout) |t| {
            const ns = @as(u64, @intFromFloat(t * 1_000_000_000));
            self.cond.timedWait(&self.lock.mutex, ns) catch return false;
            return true;
        } else {
            self.cond.wait(&self.lock.mutex);
            return true;
        }
    }

    pub fn notify(self: *Self) void {
        self.cond.signal();
    }

    pub fn notifyAll(self: *Self) void {
        self.cond.broadcast();
    }
};

/// Semaphore
pub const Semaphore = struct {
    const Self = @This();

    value: usize,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init(value: usize) Self {
        return .{
            .value = value,
            .mutex = .{},
            .cond = .{},
        };
    }

    pub fn acquire(self: *Self, block: bool, timeout: ?f64) bool {
        _ = timeout;
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.value == 0) {
            if (!block) return false;
            self.cond.wait(&self.mutex);
        }

        self.value -= 1;
        return true;
    }

    pub fn release(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value += 1;
        self.cond.signal();
    }

    pub fn getValue(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.value;
    }
};

/// Bounded semaphore
pub const BoundedSemaphore = struct {
    const Self = @This();

    semaphore: Semaphore,
    initial_value: usize,

    pub fn init(value: usize) Self {
        return .{
            .semaphore = Semaphore.init(value),
            .initial_value = value,
        };
    }

    pub fn acquire(self: *Self, block: bool, timeout: ?f64) bool {
        return self.semaphore.acquire(block, timeout);
    }

    pub fn release(self: *Self) !void {
        self.semaphore.mutex.lock();
        defer self.semaphore.mutex.unlock();

        if (self.semaphore.value >= self.initial_value) {
            return error.SemaphoreOverflow;
        }

        self.semaphore.value += 1;
        self.semaphore.cond.signal();
    }
};

/// Event object
pub const Event = struct {
    const Self = @This();

    flag: bool,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init() Self {
        return .{
            .flag = false,
            .mutex = .{},
            .cond = .{},
        };
    }

    pub fn set(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flag = true;
        self.cond.broadcast();
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flag = false;
    }

    pub fn isSet(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.flag;
    }

    pub fn wait(self: *Self, timeout: ?f64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.flag) return true;

        if (timeout) |t| {
            const ns = @as(u64, @intFromFloat(t * 1_000_000_000));
            self.cond.timedWait(&self.mutex, ns) catch return self.flag;
        } else {
            while (!self.flag) {
                self.cond.wait(&self.mutex);
            }
        }
        return self.flag;
    }
};

/// Barrier for synchronizing processes
pub const Barrier = struct {
    const Self = @This();

    parties: usize,
    count: usize,
    generation: usize,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    broken: bool,

    pub fn init(parties: usize) Self {
        return .{
            .parties = parties,
            .count = 0,
            .generation = 0,
            .mutex = .{},
            .cond = .{},
            .broken = false,
        };
    }

    pub fn wait(self: *Self, timeout: ?f64) !usize {
        _ = timeout;
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.broken) return error.BrokenBarrier;

        const gen = self.generation;
        self.count += 1;
        const index = self.parties - self.count;

        if (self.count == self.parties) {
            // Last thread - release all
            self.generation += 1;
            self.count = 0;
            self.cond.broadcast();
            return index;
        }

        // Wait for release
        while (gen == self.generation and !self.broken) {
            self.cond.wait(&self.mutex);
        }

        if (self.broken) return error.BrokenBarrier;
        return index;
    }

    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.count = 0;
        self.generation += 1;
        self.broken = false;
        self.cond.broadcast();
    }

    pub fn abort(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.broken = true;
        self.cond.broadcast();
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
