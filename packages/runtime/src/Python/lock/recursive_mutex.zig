/// recursive_mutex - Recursive Mutex Implementation
/// Mutex that can be locked multiple times by the same thread

const std = @import("std");
const Atomic = std.atomic.Value;
const pymutex = @import("pymutex.zig");

// ============================================================================
// Recursive Mutex
// ============================================================================

/// Mutex that can be locked multiple times by the same thread
pub const RecursiveMutex = struct {
    mutex: pymutex.PyMutex = .{},
    owner: Atomic(?std.Thread.Id) = Atomic(?std.Thread.Id).init(null),
    count: u32 = 0,

    const Self = @This();

    /// Lock (can be called multiple times by owner)
    pub fn lock(self: *Self) void {
        const tid = std.Thread.getCurrentId();

        if (self.owner.load(.relaxed) == tid) {
            self.count += 1;
            return;
        }

        self.mutex.lock();
        self.owner.store(tid, .relaxed);
        self.count = 1;
    }

    /// Unlock
    pub fn unlock(self: *Self) void {
        self.count -= 1;
        if (self.count == 0) {
            self.owner.store(null, .relaxed);
            self.mutex.unlock();
        }
    }

    /// Try lock
    pub fn tryLock(self: *Self) bool {
        const tid = std.Thread.getCurrentId();

        if (self.owner.load(.relaxed) == tid) {
            self.count += 1;
            return true;
        }

        if (self.mutex.tryLock()) {
            self.owner.store(tid, .relaxed);
            self.count = 1;
            return true;
        }
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "recursive mutex" {
    var rmutex = RecursiveMutex{};

    rmutex.lock();
    rmutex.lock(); // Should not deadlock
    rmutex.lock();

    rmutex.unlock();
    rmutex.unlock();
    rmutex.unlock();
}
