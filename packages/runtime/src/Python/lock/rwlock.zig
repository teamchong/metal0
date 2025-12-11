/// rwlock - Reader-Writer Lock
/// Allows multiple readers or single writer

const std = @import("std");
const Atomic = std.atomic.Value;
const helpers = @import("helpers.zig");

// ============================================================================
// RWLock - Reader-Writer Lock
// ============================================================================

/// Reader-writer lock allowing multiple readers or single writer
pub const RWLock = struct {
    state: Atomic(i32) = Atomic(i32).init(0),

    const WRITER: i32 = -1;

    const Self = @This();

    /// Acquire read lock
    pub fn readLock(self: *Self) void {
        while (true) {
            const state = self.state.load(.acquire);
            if (state >= 0) {
                if (self.state.cmpxchgWeak(state, state + 1, .acquire, .relaxed) == null) {
                    return;
                }
            } else {
                helpers.yield();
            }
        }
    }

    /// Release read lock
    pub fn readUnlock(self: *Self) void {
        _ = self.state.fetchSub(1, .release);
    }

    /// Acquire write lock
    pub fn writeLock(self: *Self) void {
        while (true) {
            var expected: i32 = 0;
            if (self.state.cmpxchgWeak(expected, WRITER, .acquire, .relaxed) == null) {
                return;
            }
            helpers.yield();
        }
    }

    /// Release write lock
    pub fn writeUnlock(self: *Self) void {
        self.state.store(0, .release);
    }

    /// Try to acquire read lock
    pub fn tryReadLock(self: *Self) bool {
        const state = self.state.load(.acquire);
        if (state >= 0) {
            return self.state.cmpxchgWeak(state, state + 1, .acquire, .relaxed) == null;
        }
        return false;
    }

    /// Try to acquire write lock
    pub fn tryWriteLock(self: *Self) bool {
        var expected: i32 = 0;
        return self.state.cmpxchgWeak(expected, WRITER, .acquire, .relaxed) == null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "rwlock readers" {
    var rwlock = RWLock{};

    // Multiple readers allowed
    rwlock.readLock();
    try std.testing.expect(rwlock.tryReadLock());
    rwlock.readUnlock();
    rwlock.readUnlock();
}

test "rwlock writer" {
    var rwlock = RWLock{};

    rwlock.writeLock();
    // Can't get read lock while writing
    try std.testing.expect(!rwlock.tryReadLock());
    rwlock.writeUnlock();

    // Now can read
    try std.testing.expect(rwlock.tryReadLock());
    rwlock.readUnlock();
}
