//! test.test_free_threading.test_refcount - Reference counting without GIL
//!
//! This module tests reference counting operations in a free-threaded (no-GIL)
//! environment. It verifies that atomic reference counting works correctly
//! when multiple threads are accessing and modifying reference counts.
const std = @import("std");

/// Atomic reference count type for thread-safe reference counting
pub const AtomicRefCount = struct {
    count: std.atomic.Value(usize),

    pub fn init(initial: usize) AtomicRefCount {
        return .{ .count = std.atomic.Value(usize).init(initial) };
    }

    /// Increment reference count atomically
    pub fn incref(self: *AtomicRefCount) void {
        _ = self.count.fetchAdd(1, .monotonic);
    }

    /// Decrement reference count atomically, returns true if count reaches zero
    pub fn decref(self: *AtomicRefCount) bool {
        const prev = self.count.fetchSub(1, .release);
        if (prev == 1) {
            // Synchronize with other threads before destruction
            std.atomic.fence(.acquire);
            return true;
        }
        return false;
    }

    /// Get current reference count (for debugging/testing)
    pub fn getCount(self: *const AtomicRefCount) usize {
        return self.count.load(.acquire);
    }
};

/// A reference-counted object for testing
pub const RefCountedObject = struct {
    refcount: AtomicRefCount,
    data: i64,
    destructor_called: *std.atomic.Value(bool),

    pub fn create(allocator: std.mem.Allocator, data: i64, destructor_flag: *std.atomic.Value(bool)) !*RefCountedObject {
        const obj = try allocator.create(RefCountedObject);
        obj.* = .{
            .refcount = AtomicRefCount.init(1),
            .data = data,
            .destructor_called = destructor_flag,
        };
        return obj;
    }

    pub fn incref(self: *RefCountedObject) *RefCountedObject {
        self.refcount.incref();
        return self;
    }

    pub fn decref(self: *RefCountedObject, allocator: std.mem.Allocator) void {
        if (self.refcount.decref()) {
            self.destructor_called.store(true, .release);
            allocator.destroy(self);
        }
    }

    pub fn getData(self: *const RefCountedObject) i64 {
        return self.data;
    }
};

/// Thread-local reference holder for testing
pub const RefHolder = struct {
    refs: std.ArrayList(*RefCountedObject),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RefHolder {
        return .{
            .refs = std.ArrayList(*RefCountedObject).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RefHolder, obj_allocator: std.mem.Allocator) void {
        for (self.refs.items) |ref| {
            ref.decref(obj_allocator);
        }
        self.refs.deinit();
    }

    pub fn hold(self: *RefHolder, obj: *RefCountedObject) !void {
        try self.refs.append(obj.incref());
    }

    pub fn release(self: *RefHolder, obj_allocator: std.mem.Allocator) void {
        if (self.refs.popOrNull()) |ref| {
            ref.decref(obj_allocator);
        }
    }
};

/// Statistics for reference counting operations
pub const RefCountStats = struct {
    total_increfs: std.atomic.Value(usize),
    total_decrefs: std.atomic.Value(usize),
    peak_refcount: std.atomic.Value(usize),
    objects_destroyed: std.atomic.Value(usize),

    pub fn init() RefCountStats {
        return .{
            .total_increfs = std.atomic.Value(usize).init(0),
            .total_decrefs = std.atomic.Value(usize).init(0),
            .peak_refcount = std.atomic.Value(usize).init(0),
            .objects_destroyed = std.atomic.Value(usize).init(0),
        };
    }

    pub fn recordIncref(self: *RefCountStats) void {
        _ = self.total_increfs.fetchAdd(1, .monotonic);
    }

    pub fn recordDecref(self: *RefCountStats) void {
        _ = self.total_decrefs.fetchAdd(1, .monotonic);
    }

    pub fn recordDestruction(self: *RefCountStats) void {
        _ = self.objects_destroyed.fetchAdd(1, .monotonic);
    }

    pub fn updatePeak(self: *RefCountStats, current: usize) void {
        var peak = self.peak_refcount.load(.acquire);
        while (current > peak) {
            const result = self.peak_refcount.cmpxchgWeak(peak, current, .release, .acquire);
            if (result) |new_peak| {
                peak = new_peak;
            } else {
                break;
            }
        }
    }
};

/// Weak reference implementation for cycle breaking
pub const WeakRef = struct {
    target: ?*RefCountedObject,
    control_block: *ControlBlock,

    pub const ControlBlock = struct {
        strong_count: std.atomic.Value(usize),
        weak_count: std.atomic.Value(usize),
        object: ?*RefCountedObject,

        pub fn init(allocator: std.mem.Allocator, obj: *RefCountedObject) !*ControlBlock {
            const block = try allocator.create(ControlBlock);
            block.* = .{
                .strong_count = std.atomic.Value(usize).init(1),
                .weak_count = std.atomic.Value(usize).init(1),
                .object = obj,
            };
            return block;
        }

        pub fn addWeak(self: *ControlBlock) void {
            _ = self.weak_count.fetchAdd(1, .monotonic);
        }

        pub fn releaseWeak(self: *ControlBlock, allocator: std.mem.Allocator) void {
            if (self.weak_count.fetchSub(1, .release) == 1) {
                std.atomic.fence(.acquire);
                allocator.destroy(self);
            }
        }

        pub fn lock(self: *ControlBlock) ?*RefCountedObject {
            var count = self.strong_count.load(.acquire);
            while (count > 0) {
                const result = self.strong_count.cmpxchgWeak(count, count + 1, .acquire, .acquire);
                if (result) |new_count| {
                    count = new_count;
                } else {
                    return self.object;
                }
            }
            return null;
        }
    };

    pub fn init(control_block: *ControlBlock) WeakRef {
        control_block.addWeak();
        return .{
            .target = control_block.object,
            .control_block = control_block,
        };
    }

    pub fn deinit(self: *WeakRef, allocator: std.mem.Allocator) void {
        self.control_block.releaseWeak(allocator);
    }

    pub fn lock(self: *const WeakRef) ?*RefCountedObject {
        return self.control_block.lock();
    }
};

/// Test context for reference counting tests
pub const RefCountTestContext = struct {
    allocator: std.mem.Allocator,
    stats: RefCountStats,
    thread_count: usize,
    iterations_per_thread: usize,

    pub fn init(allocator: std.mem.Allocator) RefCountTestContext {
        return .{
            .allocator = allocator,
            .stats = RefCountStats.init(),
            .thread_count = 4,
            .iterations_per_thread = 1000,
        };
    }

    pub fn runConcurrentTest(self: *RefCountTestContext, obj: *RefCountedObject) !void {
        var threads: [8]std.Thread = undefined;
        const actual_threads = @min(self.thread_count, 8);

        for (0..actual_threads) |i| {
            threads[i] = try std.Thread.spawn(.{}, workerThread, .{ self, obj });
        }

        for (0..actual_threads) |i| {
            threads[i].join();
        }
    }

    fn workerThread(ctx: *RefCountTestContext, obj: *RefCountedObject) void {
        for (0..ctx.iterations_per_thread) |_| {
            obj.refcount.incref();
            ctx.stats.recordIncref();
            std.atomic.spinLoopHint();
            const is_last = obj.refcount.decref();
            ctx.stats.recordDecref();
            if (is_last) {
                ctx.stats.recordDestruction();
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "atomic_refcount_basic" {
    var rc = AtomicRefCount.init(1);
    try std.testing.expectEqual(@as(usize, 1), rc.getCount());

    rc.incref();
    try std.testing.expectEqual(@as(usize, 2), rc.getCount());

    const is_zero = rc.decref();
    try std.testing.expect(!is_zero);
    try std.testing.expectEqual(@as(usize, 1), rc.getCount());

    const is_last = rc.decref();
    try std.testing.expect(is_last);
}

test "refcounted_object_lifecycle" {
    const allocator = std.testing.allocator;
    var destructor_called = std.atomic.Value(bool).init(false);

    const obj = try RefCountedObject.create(allocator, 42, &destructor_called);
    try std.testing.expectEqual(@as(i64, 42), obj.getData());
    try std.testing.expectEqual(@as(usize, 1), obj.refcount.getCount());

    _ = obj.incref();
    try std.testing.expectEqual(@as(usize, 2), obj.refcount.getCount());

    obj.decref(allocator);
    try std.testing.expectEqual(@as(usize, 1), obj.refcount.getCount());
    try std.testing.expect(!destructor_called.load(.acquire));

    obj.decref(allocator);
    try std.testing.expect(destructor_called.load(.acquire));
}

test "ref_holder_multiple_refs" {
    const allocator = std.testing.allocator;
    var destructor_called = std.atomic.Value(bool).init(false);

    const obj = try RefCountedObject.create(allocator, 100, &destructor_called);
    var holder = RefHolder.init(allocator);

    try holder.hold(obj);
    try std.testing.expectEqual(@as(usize, 2), obj.refcount.getCount());

    try holder.hold(obj);
    try std.testing.expectEqual(@as(usize, 3), obj.refcount.getCount());

    holder.release(allocator);
    try std.testing.expectEqual(@as(usize, 2), obj.refcount.getCount());

    holder.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), obj.refcount.getCount());

    obj.decref(allocator);
    try std.testing.expect(destructor_called.load(.acquire));
}

test "refcount_stats_tracking" {
    var stats = RefCountStats.init();

    stats.recordIncref();
    stats.recordIncref();
    stats.recordDecref();

    try std.testing.expectEqual(@as(usize, 2), stats.total_increfs.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), stats.total_decrefs.load(.acquire));

    stats.updatePeak(5);
    try std.testing.expectEqual(@as(usize, 5), stats.peak_refcount.load(.acquire));

    stats.updatePeak(3);
    try std.testing.expectEqual(@as(usize, 5), stats.peak_refcount.load(.acquire));

    stats.updatePeak(10);
    try std.testing.expectEqual(@as(usize, 10), stats.peak_refcount.load(.acquire));
}

test "concurrent_incref_decref" {
    const allocator = std.testing.allocator;
    var destructor_called = std.atomic.Value(bool).init(false);

    const obj = try RefCountedObject.create(allocator, 999, &destructor_called);

    // Add extra refs to prevent destruction during test
    for (0..100) |_| {
        obj.refcount.incref();
    }

    var ctx = RefCountTestContext.init(allocator);
    try ctx.runConcurrentTest(obj);

    // Remove the extra refs
    for (0..100) |_| {
        _ = obj.refcount.decref();
    }

    // Final reference
    try std.testing.expectEqual(@as(usize, 1), obj.refcount.getCount());
    obj.decref(allocator);
    try std.testing.expect(destructor_called.load(.acquire));
}

test "weak_reference_basic" {
    const allocator = std.testing.allocator;
    var destructor_called = std.atomic.Value(bool).init(false);

    const obj = try RefCountedObject.create(allocator, 777, &destructor_called);
    const control = try WeakRef.ControlBlock.init(allocator, obj);

    var weak = WeakRef.init(control);

    // Lock should succeed while strong ref exists
    if (weak.lock()) |locked| {
        try std.testing.expectEqual(@as(i64, 777), locked.getData());
        _ = locked.refcount.decref();
    } else {
        try std.testing.expect(false);
    }

    weak.deinit(allocator);
    control.releaseWeak(allocator);
    obj.decref(allocator);
}
