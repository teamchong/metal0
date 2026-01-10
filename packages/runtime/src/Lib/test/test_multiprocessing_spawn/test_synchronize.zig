//! test.test_multiprocessing_spawn.test_synchronize - Multiprocessing synchronize tests
const std = @import("std");

/// Lock for mutual exclusion
pub const Lock = struct {
    mutex: std.Thread.Mutex = .{},
    owner: ?std.Thread.Id = null,

    pub fn acquire(self: *Lock, block: bool, timeout: ?f64) bool {
        _ = timeout;
        if (block) {
            self.mutex.lock();
            self.owner = std.Thread.getCurrentId();
            return true;
        } else {
            if (self.mutex.tryLock()) {
                self.owner = std.Thread.getCurrentId();
                return true;
            }
            return false;
        }
    }

    pub fn release(self: *Lock) void {
        self.owner = null;
        self.mutex.unlock();
    }

    pub fn locked(self: *Lock) bool {
        if (self.mutex.tryLock()) {
            self.mutex.unlock();
            return false;
        }
        return true;
    }
};

/// Reentrant lock (RLock)
pub const RLock = struct {
    mutex: std.Thread.Mutex = .{},
    owner: ?std.Thread.Id = null,
    count: usize = 0,

    pub fn acquire(self: *RLock, block: bool, timeout: ?f64) bool {
        _ = timeout;
        const current = std.Thread.getCurrentId();

        if (self.owner == current) {
            self.count += 1;
            return true;
        }

        if (block) {
            self.mutex.lock();
        } else {
            if (!self.mutex.tryLock()) return false;
        }

        self.owner = current;
        self.count = 1;
        return true;
    }

    pub fn release(self: *RLock) void {
        if (self.count > 0) {
            self.count -= 1;
            if (self.count == 0) {
                self.owner = null;
                self.mutex.unlock();
            }
        }
    }
};

/// Condition variable
pub const Condition = struct {
    lock: *Lock,
    waiters: std.ArrayList(*std.Thread.Condition) = undefined,

    pub fn init(lock: *Lock, allocator: std.mem.Allocator) Condition {
        return .{
            .lock = lock,
            .waiters = std.ArrayList(*std.Thread.Condition).init(allocator),
        };
    }

    pub fn deinit(self: *Condition) void {
        self.waiters.deinit();
    }

    pub fn wait(self: *Condition, timeout: ?f64) bool {
        _ = timeout;
        _ = self;
        // In real implementation, would release lock and wait
        return true;
    }

    pub fn notify(self: *Condition, n: usize) void {
        _ = self;
        _ = n;
        // Wake up n waiters
    }

    pub fn notify_all(self: *Condition) void {
        self.notify(self.waiters.items.len);
    }
};

/// Event for signaling between processes
pub const Event = struct {
    flag: bool = false,
    mutex: std.Thread.Mutex = .{},

    pub fn set(self: *Event) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flag = true;
    }

    pub fn clear(self: *Event) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flag = false;
    }

    pub fn is_set(self: *Event) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.flag;
    }

    pub fn wait(self: *Event, timeout: ?f64) bool {
        _ = timeout;
        // In real implementation, would block until set
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.flag;
    }
};

/// Semaphore for counting access
pub const Semaphore = struct {
    value: i32,
    mutex: std.Thread.Mutex = .{},

    pub fn init(value: i32) Semaphore {
        return .{ .value = value };
    }

    pub fn acquire(self: *Semaphore, block: bool, timeout: ?f64) bool {
        _ = timeout;
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.value <= 0) {
            if (!block) return false;
            // In real implementation, would wait
            return false;
        }

        self.value -= 1;
        return true;
    }

    pub fn release(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value += 1;
    }

    pub fn get_value(self: *Semaphore) i32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.value;
    }
};

/// Bounded semaphore
pub const BoundedSemaphore = struct {
    sem: Semaphore,
    max_value: i32,

    pub fn init(value: i32) BoundedSemaphore {
        return .{
            .sem = Semaphore.init(value),
            .max_value = value,
        };
    }

    pub fn acquire(self: *BoundedSemaphore, block: bool, timeout: ?f64) bool {
        return self.sem.acquire(block, timeout);
    }

    pub fn release(self: *BoundedSemaphore) !void {
        self.sem.mutex.lock();
        defer self.sem.mutex.unlock();

        if (self.sem.value >= self.max_value) {
            return error.ValueError;
        }
        self.sem.value += 1;
    }
};

/// Barrier for synchronizing processes
pub const Barrier = struct {
    parties: usize,
    count: usize = 0,
    generation: usize = 0,
    broken: bool = false,
    mutex: std.Thread.Mutex = .{},

    pub fn init(parties: usize) Barrier {
        return .{ .parties = parties };
    }

    pub fn wait(self: *Barrier, timeout: ?f64) !usize {
        _ = timeout;
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.broken) return error.BrokenBarrierError;

        self.count += 1;
        const position = self.count;

        if (self.count >= self.parties) {
            self.count = 0;
            self.generation += 1;
        }

        return position - 1;
    }

    pub fn reset(self: *Barrier) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.count = 0;
        self.generation += 1;
    }

    pub fn abort(self: *Barrier) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.broken = true;
    }

    pub fn n_waiting(self: *Barrier) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }
};

test "lock acquire release" {
    var lock = Lock{};
    try std.testing.expect(lock.acquire(true, null));
    try std.testing.expect(lock.owner != null);
    lock.release();
    try std.testing.expect(lock.owner == null);
}

test "lock non-blocking" {
    var lock = Lock{};
    try std.testing.expect(lock.acquire(false, null));
    // Can't acquire again non-blocking since we hold it
    lock.release();
}

test "event set clear" {
    var event = Event{};
    try std.testing.expect(!event.is_set());
    event.set();
    try std.testing.expect(event.is_set());
    event.clear();
    try std.testing.expect(!event.is_set());
}

test "semaphore counting" {
    var sem = Semaphore.init(2);

    try std.testing.expectEqual(@as(i32, 2), sem.get_value());

    try std.testing.expect(sem.acquire(false, null));
    try std.testing.expectEqual(@as(i32, 1), sem.get_value());

    try std.testing.expect(sem.acquire(false, null));
    try std.testing.expectEqual(@as(i32, 0), sem.get_value());

    try std.testing.expect(!sem.acquire(false, null));

    sem.release();
    try std.testing.expectEqual(@as(i32, 1), sem.get_value());
}

test "bounded semaphore" {
    var bsem = BoundedSemaphore.init(1);

    try std.testing.expect(bsem.acquire(false, null));
    try bsem.release();

    // Can't release beyond initial value
    try std.testing.expectError(error.ValueError, bsem.release());
}

test "barrier" {
    var barrier = Barrier.init(2);
    try std.testing.expectEqual(@as(usize, 0), barrier.n_waiting());

    const pos = try barrier.wait(null);
    try std.testing.expectEqual(@as(usize, 0), pos);
}

test "barrier reset" {
    var barrier = Barrier.init(3);
    _ = try barrier.wait(null);
    try std.testing.expectEqual(@as(usize, 1), barrier.n_waiting());

    barrier.reset();
    try std.testing.expectEqual(@as(usize, 0), barrier.n_waiting());
}

test "barrier abort" {
    var barrier = Barrier.init(2);
    barrier.abort();
    try std.testing.expectError(error.BrokenBarrierError, barrier.wait(null));
}
