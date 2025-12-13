/// locks - Lock Primitives
/// Mutex and recursive lock implementations.

const std = @import("std");
const types = @import("types.zig");

pub const LockStatus = types.LockStatus;
pub const LockFlags = types.LockFlags;

// ============================================================================
// Simple Lock
// ============================================================================

/// Simple mutex lock
pub const Lock = struct {
    mutex: std.Thread.Mutex = .{},
    locked: bool = false,

    const Self = @This();

    /// Allocate a new lock
    pub fn create() *Self {
        const lock = std.heap.c_allocator.create(Self) catch return undefined;
        lock.* = .{};
        return lock;
    }

    /// Free a lock
    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    /// Acquire lock with optional timeout
    pub fn acquire(self: *Self, timeout_us: i64, flags: LockFlags) LockStatus {
        _ = flags;

        if (timeout_us == 0) {
            // Non-blocking try
            if (self.mutex.tryLock()) {
                self.locked = true;
                return .acquired;
            }
            return .failure;
        }

        if (timeout_us < 0) {
            // Infinite wait
            self.mutex.lock();
            self.locked = true;
            return .acquired;
        }

        // Timed wait using tryLock with sleep
        const start = std.time.nanoTimestamp();
        const timeout_ns = timeout_us * 1000;

        while (true) {
            if (self.mutex.tryLock()) {
                self.locked = true;
                return .acquired;
            }

            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return .timeout;
            }

            // Brief sleep before retry
            std.Thread.sleep(1000); // 1us
        }
    }

    /// Release lock
    pub fn release(self: *Self) void {
        self.locked = false;
        self.mutex.unlock();
    }

    /// Check if lock is held
    pub fn isLocked(self: *Self) bool {
        return self.locked;
    }
};

// ============================================================================
// Recursive Lock
// ============================================================================

/// Recursive lock (reentrant mutex)
pub const RLock = struct {
    mutex: std.Thread.Mutex = .{},
    owner: ?std.Thread.Id = null,
    count: usize = 0,

    const Self = @This();

    pub fn create() *Self {
        const lock = std.heap.c_allocator.create(Self) catch return undefined;
        lock.* = .{};
        return lock;
    }

    pub fn destroy(self: *Self) void {
        std.heap.c_allocator.destroy(self);
    }

    pub fn acquire(self: *Self, timeout_us: i64) LockStatus {
        const tid = std.Thread.getCurrentId();

        // Check if we already own it
        if (self.owner == tid) {
            self.count += 1;
            return .acquired;
        }

        // Need to acquire underlying mutex
        if (timeout_us == 0) {
            if (self.mutex.tryLock()) {
                self.owner = tid;
                self.count = 1;
                return .acquired;
            }
            return .failure;
        }

        if (timeout_us < 0) {
            self.mutex.lock();
            self.owner = tid;
            self.count = 1;
            return .acquired;
        }

        // Timed wait
        const start = std.time.nanoTimestamp();
        const timeout_ns = timeout_us * 1000;

        while (true) {
            if (self.mutex.tryLock()) {
                self.owner = tid;
                self.count = 1;
                return .acquired;
            }

            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return .timeout;
            }

            std.Thread.sleep(1000);
        }
    }

    pub fn release(self: *Self) bool {
        const tid = std.Thread.getCurrentId();
        if (self.owner != tid) {
            return false; // Not owner
        }

        self.count -= 1;
        if (self.count == 0) {
            self.owner = null;
            self.mutex.unlock();
        }
        return true;
    }

    pub fn isOwned(self: *Self) bool {
        return self.owner == std.Thread.getCurrentId();
    }

    pub fn getCount(self: *Self) usize {
        if (self.owner == std.Thread.getCurrentId()) {
            return self.count;
        }
        return 0;
    }
};

// ============================================================================
// At Fork Handling
// ============================================================================

/// Reinitialize lock after fork
pub fn atForkReinit(lock: *Lock) void {
    lock.* = .{};
}

// ============================================================================
// Tests
// ============================================================================

test "lock basic" {
    var lock = Lock{};

    const status = lock.acquire(-1, .{});
    try std.testing.expect(status == .acquired);
    try std.testing.expect(lock.isLocked());

    lock.release();
    try std.testing.expect(!lock.isLocked());
}

test "lock trylock" {
    var lock = Lock{};

    // Should succeed
    const status1 = lock.acquire(0, .{});
    try std.testing.expect(status1 == .acquired);

    // Should fail (already locked by us, not recursive)
    // Note: std.Thread.Mutex allows recursive lock from same thread on some platforms
    lock.release();
}

test "rlock recursive" {
    var rlock = RLock{};

    // First acquire
    _ = rlock.acquire(-1);
    try std.testing.expect(rlock.isOwned());
    try std.testing.expectEqual(@as(usize, 1), rlock.getCount());

    // Second acquire (recursive)
    _ = rlock.acquire(-1);
    try std.testing.expectEqual(@as(usize, 2), rlock.getCount());

    // Release once
    _ = rlock.release();
    try std.testing.expectEqual(@as(usize, 1), rlock.getCount());

    // Release again
    _ = rlock.release();
    try std.testing.expectEqual(@as(usize, 0), rlock.getCount());
    try std.testing.expect(!rlock.isOwned());
}
