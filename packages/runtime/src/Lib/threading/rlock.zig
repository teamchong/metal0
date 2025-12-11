//! RLock - Reentrant lock object
//!
//! CPython source: Lib/threading.py (RLock class)

const std = @import("std");

/// A reentrant lock
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

    /// Acquire the lock
    pub fn acquire(self: *Self, blocking: bool, timeout: ?f64) bool {
        _ = timeout;

        const current = std.Thread.getCurrentId();

        if (self.owner == current) {
            self.count += 1;
            return true;
        }

        if (blocking) {
            self.mutex.lock();
            self.owner = current;
            self.count = 1;
            return true;
        } else {
            if (self.mutex.tryLock()) {
                self.owner = current;
                self.count = 1;
                return true;
            }
            return false;
        }
    }

    /// Release the lock
    pub fn release(self: *Self) !void {
        const current = std.Thread.getCurrentId();
        if (self.owner != current) return error.NotOwner;

        self.count -= 1;
        if (self.count == 0) {
            self.owner = null;
            self.mutex.unlock();
        }
    }

    /// Check if lock is owned by current thread
    pub fn isOwned(self: *Self) bool {
        return self.owner == std.Thread.getCurrentId();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RLock" {
    var rlock = RLock.init();

    try std.testing.expect(rlock.acquire(true, null));
    try std.testing.expect(rlock.acquire(true, null)); // Reentrant
    try rlock.release();
    try rlock.release();
}
