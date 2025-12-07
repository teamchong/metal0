/// qsbr - Quiescent State Based Reclamation
/// Mirrors cpython/Python/qsbr.c
///
/// This module implements QSBR (Quiescent State Based Reclamation) for
/// safe memory reclamation in concurrent programs without locking:
/// - Deferred freeing of memory until all threads pass quiescent state
/// - Grace period management
/// - Integration with Python's free-threading (PEP 703)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;

// ============================================================================
// Constants
// ============================================================================

/// Maximum number of threads supported
const MAX_THREADS: usize = 256;

/// Batch size for deferred frees
const DEFER_BATCH_SIZE: usize = 64;

/// Initial capacity for deferred items
const INITIAL_DEFER_CAPACITY: usize = 256;

// ============================================================================
// QSBR State
// ============================================================================

/// Thread-local QSBR state
pub const ThreadState = struct {
    /// Current epoch seen by this thread
    epoch: Atomic(u64) = Atomic(u64).init(0),
    /// Whether thread is in quiescent state
    quiescent: Atomic(bool) = Atomic(bool).init(true),
    /// Thread ID for debugging
    tid: u64 = 0,
    /// Active flag
    active: Atomic(bool) = Atomic(bool).init(false),

    const Self = @This();

    /// Mark thread as active (entering critical section)
    pub fn enter(self: *Self) void {
        self.quiescent.store(false, .release);
    }

    /// Mark thread as quiescent (leaving critical section)
    pub fn exit(self: *Self, global_epoch: u64) void {
        self.epoch.store(global_epoch, .release);
        self.quiescent.store(true, .release);
    }

    /// Check if thread has seen the given epoch
    pub fn hasSeen(self: *const Self, epoch: u64) bool {
        if (self.quiescent.load(.acquire)) {
            return true; // Quiescent threads have seen all epochs
        }
        return self.epoch.load(.acquire) >= epoch;
    }
};

// ============================================================================
// Deferred Item
// ============================================================================

/// Item to be freed after grace period
const DeferredItem = struct {
    /// Pointer to free
    ptr: *anyopaque,
    /// Epoch when item was deferred
    epoch: u64,
    /// Custom free function (null = use allocator.free)
    free_fn: ?*const fn (*anyopaque) void,
};

// ============================================================================
// QSBR Domain
// ============================================================================

/// QSBR domain managing grace periods
pub const QSBRDomain = struct {
    /// Global epoch counter
    global_epoch: Atomic(u64) = Atomic(u64).init(0),
    /// Minimum epoch seen by all active threads
    min_epoch: Atomic(u64) = Atomic(u64).init(0),
    /// Thread states
    threads: [MAX_THREADS]ThreadState = undefined,
    /// Number of active threads
    active_count: Atomic(usize) = Atomic(usize).init(0),
    /// Deferred items waiting for reclamation
    deferred: std.ArrayList(DeferredItem),
    /// Lock for deferred list
    deferred_lock: std.Thread.Mutex = .{},
    /// Allocator for internal allocations
    allocator: Allocator,

    const Self = @This();

    /// Initialize a new QSBR domain
    pub fn init(allocator: Allocator) !Self {
        var self = Self{
            .deferred = std.ArrayList(DeferredItem).init(allocator),
            .allocator = allocator,
        };

        // Initialize thread states
        for (&self.threads) |*ts| {
            ts.* = .{};
        }

        return self;
    }

    /// Deinitialize the domain
    pub fn deinit(self: *Self) void {
        // Free any remaining deferred items
        self.reclaimAll();
        self.deferred.deinit();
    }

    /// Register a thread, returns thread index
    pub fn registerThread(self: *Self) !usize {
        const tid = @intFromPtr(std.Thread.getCurrentId());

        // Find a free slot
        for (&self.threads, 0..) |*ts, i| {
            if (!ts.active.load(.acquire)) {
                var expected = false;
                if (ts.active.cmpxchgStrong(expected, true, .acq_rel, .acquire) == null) {
                    ts.tid = tid;
                    ts.epoch.store(self.global_epoch.load(.acquire), .release);
                    ts.quiescent.store(true, .release);
                    _ = self.active_count.fetchAdd(1, .release);
                    return i;
                }
            }
        }

        return error.TooManyThreads;
    }

    /// Unregister a thread
    pub fn unregisterThread(self: *Self, index: usize) void {
        if (index < MAX_THREADS) {
            self.threads[index].active.store(false, .release);
            _ = self.active_count.fetchSub(1, .release);
        }
    }

    /// Get thread state for an index
    pub fn getThreadState(self: *Self, index: usize) ?*ThreadState {
        if (index >= MAX_THREADS) return null;
        if (!self.threads[index].active.load(.acquire)) return null;
        return &self.threads[index];
    }

    /// Enter critical section
    pub fn enter(self: *Self, index: usize) void {
        if (self.getThreadState(index)) |ts| {
            ts.enter();
        }
    }

    /// Exit critical section
    pub fn exit(self: *Self, index: usize) void {
        const epoch = self.global_epoch.load(.acquire);
        if (self.getThreadState(index)) |ts| {
            ts.exit(epoch);
        }
    }

    /// Advance the global epoch
    pub fn advance(self: *Self) u64 {
        return self.global_epoch.fetchAdd(1, .acq_rel) + 1;
    }

    /// Defer freeing a pointer until grace period completes
    pub fn defer(self: *Self, ptr: *anyopaque) !void {
        try self.deferWithFn(ptr, null);
    }

    /// Defer with custom free function
    pub fn deferWithFn(self: *Self, ptr: *anyopaque, free_fn: ?*const fn (*anyopaque) void) !void {
        const epoch = self.global_epoch.load(.acquire);

        self.deferred_lock.lock();
        defer self.deferred_lock.unlock();

        try self.deferred.append(.{
            .ptr = ptr,
            .epoch = epoch,
            .free_fn = free_fn,
        });
    }

    /// Synchronize - wait until all threads have passed quiescent state
    pub fn synchronize(self: *Self) void {
        const target_epoch = self.advance();

        // Wait until all active threads have seen the new epoch
        while (true) {
            var all_seen = true;

            for (&self.threads) |*ts| {
                if (ts.active.load(.acquire)) {
                    if (!ts.hasSeen(target_epoch)) {
                        all_seen = false;
                        break;
                    }
                }
            }

            if (all_seen) {
                self.min_epoch.store(target_epoch, .release);
                return;
            }

            // Brief sleep to avoid busy waiting
            std.time.sleep(100);
        }
    }

    /// Try to reclaim deferred items
    pub fn reclaim(self: *Self) usize {
        const safe_epoch = self.min_epoch.load(.acquire);

        self.deferred_lock.lock();

        var freed: usize = 0;
        var i: usize = 0;

        while (i < self.deferred.items.len) {
            const item = self.deferred.items[i];
            if (item.epoch < safe_epoch) {
                // Safe to free
                if (item.free_fn) |free_fn| {
                    free_fn(item.ptr);
                }
                // Remove from list (swap with last)
                _ = self.deferred.swapRemove(i);
                freed += 1;
            } else {
                i += 1;
            }
        }

        self.deferred_lock.unlock();
        return freed;
    }

    /// Force reclaim all items (for shutdown)
    pub fn reclaimAll(self: *Self) void {
        self.deferred_lock.lock();
        defer self.deferred_lock.unlock();

        for (self.deferred.items) |item| {
            if (item.free_fn) |free_fn| {
                free_fn(item.ptr);
            }
        }
        self.deferred.clearRetainingCapacity();
    }

    /// Get number of pending deferred items
    pub fn pendingCount(self: *const Self) usize {
        return self.deferred.items.len;
    }

    /// Get active thread count
    pub fn getActiveCount(self: *const Self) usize {
        return self.active_count.load(.acquire);
    }
};

// ============================================================================
// Global QSBR Domain
// ============================================================================

var global_domain: ?QSBRDomain = null;

/// Initialize global QSBR domain
pub fn initGlobal(allocator: Allocator) !void {
    if (global_domain == null) {
        global_domain = try QSBRDomain.init(allocator);
    }
}

/// Get global domain
pub fn getGlobalDomain() ?*QSBRDomain {
    if (global_domain) |*domain| {
        return domain;
    }
    return null;
}

/// Deinitialize global domain
pub fn deinitGlobal() void {
    if (global_domain) |*domain| {
        domain.deinit();
        global_domain = null;
    }
}

// ============================================================================
// Thread-Local State
// ============================================================================

/// Thread-local QSBR handle
pub const ThreadHandle = struct {
    domain: *QSBRDomain,
    index: usize,

    const Self = @This();

    /// Enter read-side critical section
    pub fn enter(self: *const Self) void {
        self.domain.enter(self.index);
    }

    /// Exit read-side critical section
    pub fn exit(self: *const Self) void {
        self.domain.exit(self.index);
    }

    /// Defer freeing a pointer
    pub fn defer(self: *const Self, ptr: *anyopaque) !void {
        try self.domain.defer(ptr);
    }
};

/// Register current thread with global domain
pub fn registerThread() !ThreadHandle {
    const domain = getGlobalDomain() orelse return error.NotInitialized;
    const index = try domain.registerThread();
    return .{
        .domain = domain,
        .index = index,
    };
}

/// Unregister thread
pub fn unregisterThread(handle: ThreadHandle) void {
    handle.domain.unregisterThread(handle.index);
}

// ============================================================================
// RAII Guard
// ============================================================================

/// RAII guard for critical sections
pub const CriticalSection = struct {
    handle: *const ThreadHandle,

    const Self = @This();

    pub fn init(handle: *const ThreadHandle) Self {
        handle.enter();
        return .{ .handle = handle };
    }

    pub fn deinit(self: Self) void {
        self.handle.exit();
    }
};

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "thread state basic" {
    var ts = ThreadState{};

    try std.testing.expect(ts.quiescent.load(.acquire));

    ts.enter();
    try std.testing.expect(!ts.quiescent.load(.acquire));

    ts.exit(1);
    try std.testing.expect(ts.quiescent.load(.acquire));
    try std.testing.expectEqual(@as(u64, 1), ts.epoch.load(.acquire));
}

test "thread state has_seen" {
    var ts = ThreadState{};

    // Quiescent threads have seen all epochs
    try std.testing.expect(ts.hasSeen(100));

    ts.enter();
    ts.epoch.store(5, .release);
    try std.testing.expect(!ts.hasSeen(10));
    try std.testing.expect(ts.hasSeen(5));
    try std.testing.expect(ts.hasSeen(3));

    ts.exit(10);
    try std.testing.expect(ts.hasSeen(10));
    try std.testing.expect(ts.hasSeen(100)); // Quiescent
}

test "qsbr domain basic" {
    var domain = try QSBRDomain.init(std.testing.allocator);
    defer domain.deinit();

    try std.testing.expectEqual(@as(usize, 0), domain.getActiveCount());

    const idx = try domain.registerThread();
    try std.testing.expectEqual(@as(usize, 1), domain.getActiveCount());

    domain.enter(idx);
    domain.exit(idx);

    domain.unregisterThread(idx);
    try std.testing.expectEqual(@as(usize, 0), domain.getActiveCount());
}

test "qsbr domain epochs" {
    var domain = try QSBRDomain.init(std.testing.allocator);
    defer domain.deinit();

    const initial = domain.global_epoch.load(.acquire);
    try std.testing.expectEqual(@as(u64, 0), initial);

    const e1 = domain.advance();
    try std.testing.expectEqual(@as(u64, 1), e1);

    const e2 = domain.advance();
    try std.testing.expectEqual(@as(u64, 2), e2);
}

test "qsbr defer and reclaim" {
    var domain = try QSBRDomain.init(std.testing.allocator);
    defer domain.deinit();

    // Create some test data
    var freed = false;
    const TestData = struct {
        value: u32,
    };

    var data = try std.testing.allocator.create(TestData);
    data.value = 42;

    // Register thread
    const idx = try domain.registerThread();
    domain.enter(idx);

    // Defer the free
    try domain.deferWithFn(@ptrCast(data), struct {
        fn free(ptr: *anyopaque) void {
            const d: *TestData = @ptrCast(@alignCast(ptr));
            std.testing.allocator.destroy(d);
        }
    }.free);

    try std.testing.expectEqual(@as(usize, 1), domain.pendingCount());

    // Exit critical section
    domain.exit(idx);
    domain.unregisterThread(idx);

    // Advance epoch past the defer
    _ = domain.advance();
    domain.min_epoch.store(domain.global_epoch.load(.acquire), .release);

    // Reclaim
    const reclaimed = domain.reclaim();
    try std.testing.expectEqual(@as(usize, 1), reclaimed);
    try std.testing.expectEqual(@as(usize, 0), domain.pendingCount());

    _ = freed;
}
