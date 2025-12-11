//! Barrier - Synchronization barrier object
//!
//! CPython source: Lib/threading.py (Barrier class)

const std = @import("std");

/// A barrier for a fixed number of threads
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

    /// Wait for all parties to reach the barrier
    pub fn wait(self: *Self, timeout: ?f64) !usize {
        _ = timeout;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.broken) return error.BrokenBarrier;

        const gen = self.generation;
        self.count += 1;
        const index = self.count;

        if (self.count == self.parties) {
            // Last thread - reset and wake all
            self.count = 0;
            self.generation += 1;
            self.cond.broadcast();
            return index - 1;
        }

        // Wait for other threads
        while (gen == self.generation and !self.broken) {
            self.cond.wait(&self.mutex);
        }

        if (self.broken) return error.BrokenBarrier;
        return index - 1;
    }

    /// Reset the barrier
    pub fn reset(self: *Self) void {
        self.mutex.lock();
        self.count = 0;
        self.generation += 1;
        self.broken = false;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    /// Put the barrier into a broken state
    pub fn abort(self: *Self) void {
        self.mutex.lock();
        self.broken = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    /// Return the number of threads required
    pub fn getParties(self: *Self) usize {
        return self.parties;
    }

    /// Return the number of threads waiting
    pub fn getWaiting(self: *Self) usize {
        return self.count;
    }

    /// Return whether the barrier is broken
    pub fn isBroken(self: *Self) bool {
        return self.broken;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Barrier" {
    var barrier = Barrier.init(2);

    try std.testing.expectEqual(@as(usize, 2), barrier.getParties());
    try std.testing.expectEqual(@as(usize, 0), barrier.getWaiting());
    try std.testing.expect(!barrier.isBroken());
}
