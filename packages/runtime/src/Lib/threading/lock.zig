//! Lock - Primitive lock object
//!
//! CPython source: Lib/threading.py (Lock class)

const std = @import("std");

/// A factory function that returns a new primitive lock object
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

    /// Acquire the lock with optional timeout
    /// If blocking=true and timeout is set, will try to acquire for up to timeout seconds
    /// Returns true if lock was acquired, false otherwise
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        if (!blocking) {
            // Non-blocking: try once
            if (self.mutex.tryLock()) {
                self.locked = true;
                return true;
            }
            return false;
        }

        if (timeout) |t| {
            // Blocking with timeout: spin-wait with tryLock
            if (t <= 0) {
                // Zero or negative timeout means try once
                if (self.mutex.tryLock()) {
                    self.locked = true;
                    return true;
                }
                return false;
            }

            const timeout_ns: u64 = @intFromFloat(t * std.time.ns_per_s);
            const start = std.time.nanoTimestamp();
            const deadline = start + @as(i128, timeout_ns);

            while (std.time.nanoTimestamp() < deadline) {
                if (self.mutex.tryLock()) {
                    self.locked = true;
                    return true;
                }
                // Brief sleep to avoid spinning too hard
                std.Thread.sleep(1_000_000); // 1ms
            }
            return false;
        } else {
            // Blocking without timeout: wait indefinitely
            self.mutex.lock();
            self.locked = true;
            return true;
        }
    }

    /// Release the lock
    pub fn release(self: *Self) void {
        self.locked = false;
        self.mutex.unlock();
    }

    /// Check if lock is held
    pub fn isLocked(self: *Self) bool {
        return self.locked;
    }

    /// Check if lock is held (alias)
    pub fn locked_status(self: *Self) bool {
        return self.locked;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Lock" {
    var lock = Lock.init();

    try std.testing.expect(lock.acquire(true, null));
    try std.testing.expect(lock.isLocked());
    lock.release();
    try std.testing.expect(!lock.isLocked());
}

test "Lock non-blocking" {
    var lock = Lock.init();

    try std.testing.expect(lock.acquire(false, null));
    try std.testing.expect(!lock.acquire(false, null)); // Already locked
    lock.release();
    try std.testing.expect(lock.acquire(false, null)); // Now available
    lock.release();
}
