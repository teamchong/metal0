/// ceval_gil - GIL Management for Eval
/// Mirrors cpython/Python/ceval_gil.c
///
/// Global Interpreter Lock management for the bytecode evaluation loop.
/// The GIL ensures only one thread executes Python bytecode at a time.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// GIL Configuration
// ============================================================================

/// Default interval for checking signals/thread switching (in bytecode instructions)
pub const DEFAULT_INTERVAL = 5000;

/// Interval for checking GIL release (in microseconds)
pub const DEFAULT_SWITCHINTERVAL: u64 = 5000; // 5ms

// ============================================================================
// GIL State
// ============================================================================

/// GIL holder state
pub const GILState = enum {
    /// No thread holds the GIL
    unlocked,
    /// A thread holds the GIL
    locked,
    /// GIL is being transferred
    transitioning,
};

/// Per-thread GIL state
pub const ThreadGILState = enum {
    /// Thread doesn't have the GIL
    not_held,
    /// Thread holds the GIL
    held,
    /// Thread is waiting for the GIL
    waiting,
};

// ============================================================================
// GIL Structure
// ============================================================================

/// Global Interpreter Lock
pub const GIL = struct {
    const Self = @This();

    /// Mutex for GIL operations
    mutex: std.Thread.Mutex = .{},
    /// Condition variable for GIL waiters
    cond: std.Thread.Condition = .{},
    /// Current state
    state: GILState = .unlocked,
    /// Thread ID of current holder
    holder: ?std.Thread.Id = null,
    /// Number of threads waiting
    waiters: u32 = 0,
    /// Switch interval in microseconds
    switch_interval: u64 = DEFAULT_SWITCHINTERVAL,
    /// Last switch time
    last_switch: i64 = 0,
    /// Whether a thread drop request is pending
    drop_requested: bool = false,
    /// GIL acquisition count (for debugging)
    acquisitions: u64 = 0,
    /// GIL release count (for debugging)
    releases: u64 = 0,

    pub fn init() Self {
        return Self{};
    }

    /// Acquire the GIL
    pub fn acquire(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const tid = std.Thread.getCurrentId();

        // If we already hold it, return (recursive acquisition)
        if (self.holder == tid) {
            return;
        }

        // Wait for GIL to become available
        self.waiters += 1;
        while (self.state == .locked or self.state == .transitioning) {
            self.cond.wait(&self.mutex);
        }
        self.waiters -= 1;

        // Acquire the GIL
        self.state = .locked;
        self.holder = tid;
        self.acquisitions += 1;
        self.last_switch = std.time.milliTimestamp();
    }

    /// Release the GIL
    pub fn release(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const tid = std.Thread.getCurrentId();

        // Only the holder can release
        if (self.holder != tid) {
            return;
        }

        self.state = .unlocked;
        self.holder = null;
        self.releases += 1;
        self.drop_requested = false;

        // Wake up waiters
        if (self.waiters > 0) {
            self.cond.signal();
        }
    }

    /// Try to acquire the GIL without blocking
    pub fn tryAcquire(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state == .unlocked) {
            self.state = .locked;
            self.holder = std.Thread.getCurrentId();
            self.acquisitions += 1;
            return true;
        }
        return false;
    }

    /// Check if current thread holds the GIL
    pub fn isHeld(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.holder == std.Thread.getCurrentId();
    }

    /// Request the holder to drop the GIL
    pub fn requestDrop(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state == .locked) {
            self.drop_requested = true;
        }
    }

    /// Check if a drop was requested
    pub fn dropRequested(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.drop_requested;
    }

    /// Set the switch interval
    pub fn setSwitchInterval(self: *Self, interval: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.switch_interval = interval;
    }

    /// Get the switch interval
    pub fn getSwitchInterval(self: *const Self) u64 {
        return self.switch_interval;
    }

    /// Get statistics
    pub fn getStats(self: *Self) GILStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return GILStats{
            .acquisitions = self.acquisitions,
            .releases = self.releases,
            .waiters = self.waiters,
            .switch_interval = self.switch_interval,
        };
    }
};

/// GIL statistics
pub const GILStats = struct {
    acquisitions: u64,
    releases: u64,
    waiters: u32,
    switch_interval: u64,
};

// ============================================================================
// GIL Guard (RAII)
// ============================================================================

/// RAII guard for GIL acquisition
pub const GILGuard = struct {
    const Self = @This();

    gil: *GIL,
    acquired: bool = false,

    /// Create a guard that acquires the GIL
    pub fn acquire(gil: *GIL) Self {
        gil.acquire();
        return Self{ .gil = gil, .acquired = true };
    }

    /// Release the GIL when guard is destroyed
    pub fn release(self: *Self) void {
        if (self.acquired) {
            self.gil.release();
            self.acquired = false;
        }
    }
};

// ============================================================================
// Thread State
// ============================================================================

/// Thread state for GIL management
pub const ThreadState = struct {
    const Self = @This();

    /// Thread ID
    thread_id: std.Thread.Id,
    /// GIL state for this thread
    gil_state: ThreadGILState = .not_held,
    /// Interpreter state (opaque)
    interp: ?*anyopaque = null,
    /// Next thread state in list
    next: ?*Self = null,
    /// Previous thread state in list
    prev: ?*Self = null,
    /// Check counter (for periodic checks)
    check_counter: i32 = 0,
    /// Whether to check signals
    check_signals: bool = true,

    pub fn init(thread_id: std.Thread.Id) Self {
        return Self{ .thread_id = thread_id };
    }

    /// Check if this thread should yield the GIL
    pub fn shouldYield(self: *Self, gil: *GIL) bool {
        // Decrement check counter
        self.check_counter -= 1;
        if (self.check_counter > 0) {
            return false;
        }

        // Reset counter
        self.check_counter = DEFAULT_INTERVAL;

        // Check if there are waiters
        const stats = gil.getStats();
        if (stats.waiters > 0) {
            return true;
        }

        // Check time interval
        const now = std.time.milliTimestamp();
        const elapsed: u64 = @intCast(@max(0, now - gil.last_switch));
        return elapsed >= gil.switch_interval / 1000;
    }
};

// ============================================================================
// Eval Breaker
// ============================================================================

/// Flags for evaluation loop interruption
pub const EvalBreaker = packed struct {
    /// Signal handler wants to be called
    signals_pending: bool = false,
    /// Thread switch requested
    gil_drop_request: bool = false,
    /// Async exception pending
    async_exc: bool = false,
    /// GC is running
    gc_scheduled: bool = false,
    /// Pending finalizers
    finalizers_pending: bool = false,
    /// Reserved
    _reserved: u3 = 0,
};

/// Check if eval loop should break
pub fn shouldBreak(breaker: EvalBreaker) bool {
    return breaker.signals_pending or
        breaker.gil_drop_request or
        breaker.async_exc or
        breaker.gc_scheduled or
        breaker.finalizers_pending;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_gil: ?GIL = null;

/// Initialize the ceval_gil module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global GIL
pub fn getGIL() *GIL {
    if (global_gil == null) {
        global_gil = GIL.init();
    }
    return &global_gil.?;
}

/// Reset module state
pub fn reset() void {
    global_gil = null;
    initialized = false;
}

// ============================================================================
// Public API
// ============================================================================

/// Acquire GIL and ensure thread state
pub fn ensureGIL() void {
    getGIL().acquire();
}

/// Release GIL
pub fn releaseGIL() void {
    getGIL().release();
}

/// Check if GIL is held by current thread
pub fn gilHeld() bool {
    return getGIL().isHeld();
}

/// Set switch interval
pub fn setSwitchInterval(interval: f64) void {
    const usec: u64 = @intFromFloat(interval * 1_000_000);
    getGIL().setSwitchInterval(usec);
}

/// Get switch interval
pub fn getSwitchInterval() f64 {
    const usec = getGIL().getSwitchInterval();
    return @as(f64, @floatFromInt(usec)) / 1_000_000.0;
}

// ============================================================================
// Tests
// ============================================================================

test "gil init" {
    var gil = GIL.init();
    try std.testing.expectEqual(GILState.unlocked, gil.state);
    try std.testing.expect(gil.holder == null);
}

test "gil acquire release" {
    var gil = GIL.init();

    gil.acquire();
    try std.testing.expectEqual(GILState.locked, gil.state);
    try std.testing.expect(gil.isHeld());

    gil.release();
    try std.testing.expectEqual(GILState.unlocked, gil.state);
    try std.testing.expect(!gil.isHeld());
}

test "gil try acquire" {
    var gil = GIL.init();

    try std.testing.expect(gil.tryAcquire());
    try std.testing.expect(!gil.tryAcquire()); // Already held
    gil.release();
}

test "gil stats" {
    var gil = GIL.init();
    gil.acquire();
    gil.release();

    const stats = gil.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.acquisitions);
    try std.testing.expectEqual(@as(u64, 1), stats.releases);
}

test "thread state" {
    const state = ThreadState.init(std.Thread.getCurrentId());
    try std.testing.expectEqual(ThreadGILState.not_held, state.gil_state);
}

test "eval breaker" {
    var breaker = EvalBreaker{};
    try std.testing.expect(!shouldBreak(breaker));

    breaker.signals_pending = true;
    try std.testing.expect(shouldBreak(breaker));
}

test "switch interval" {
    var gil = GIL.init();
    gil.setSwitchInterval(10000);
    try std.testing.expectEqual(@as(u64, 10000), gil.getSwitchInterval());
}
