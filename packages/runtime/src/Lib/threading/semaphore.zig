//! Semaphore - Counting semaphore and BoundedSemaphore objects
//!
//! CPython source: Lib/threading.py (Semaphore and BoundedSemaphore classes)

const std = @import("std");

/// A semaphore
pub const Semaphore = struct {
    const Self = @This();

    value: i32,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init(value: i32) Self {
        return .{
            .value = value,
            .mutex = .{},
            .cond = .{},
        };
    }

    /// Acquire the semaphore
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        _ = timeout;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (blocking) {
            while (self.value <= 0) {
                self.cond.wait(&self.mutex);
            }
            self.value -= 1;
            return true;
        } else {
            if (self.value > 0) {
                self.value -= 1;
                return true;
            }
            return false;
        }
    }

    /// Release the semaphore
    pub fn release(self: *Self, n: i32) void {
        self.mutex.lock();
        self.value += n;
        if (n == 1) {
            self.cond.signal();
        } else {
            self.cond.broadcast();
        }
        self.mutex.unlock();
    }

    /// Return the current value
    pub fn getValue(self: *Self) i32 {
        return self.value;
    }
};

/// A bounded semaphore that raises error if released too many times
pub const BoundedSemaphore = struct {
    const Self = @This();

    sem: Semaphore,
    initial_value: i32,

    pub fn init(value: i32) Self {
        return .{
            .sem = Semaphore.init(value),
            .initial_value = value,
        };
    }

    /// Acquire the semaphore
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        return self.sem.acquire(blocking, timeout);
    }

    /// Release the semaphore
    pub fn release(self: *Self) !void {
        if (self.sem.value >= self.initial_value) {
            return error.BoundedSemaphoreOverflow;
        }
        self.sem.release(1);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Semaphore" {
    var sem = Semaphore.init(2);

    try std.testing.expect(sem.acquire(true, null));
    try std.testing.expect(sem.acquire(true, null));
    try std.testing.expect(!sem.acquire(false, null)); // No more permits

    sem.release(1);
    try std.testing.expect(sem.acquire(false, null)); // Now available
    sem.release(2);
}
