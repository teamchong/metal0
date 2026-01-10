//! test.test_free_threading.test_gc - GC in free-threaded mode
//!
//! This module tests garbage collection behavior in free-threaded Python.
//! It provides utilities for tracking object lifetimes, detecting cycles,
//! and testing GC under concurrent access.
const std = @import("std");

/// Garbage collection statistics tracker
pub const GCStats = struct {
    allocations: std.atomic.Value(usize),
    deallocations: std.atomic.Value(usize),
    collections: std.atomic.Value(usize),
    objects_collected: std.atomic.Value(usize),
    cycles_detected: std.atomic.Value(usize),
    peak_objects: std.atomic.Value(usize),
    current_objects: std.atomic.Value(usize),

    pub fn init() GCStats {
        return .{
            .allocations = std.atomic.Value(usize).init(0),
            .deallocations = std.atomic.Value(usize).init(0),
            .collections = std.atomic.Value(usize).init(0),
            .objects_collected = std.atomic.Value(usize).init(0),
            .cycles_detected = std.atomic.Value(usize).init(0),
            .peak_objects = std.atomic.Value(usize).init(0),
            .current_objects = std.atomic.Value(usize).init(0),
        };
    }

    pub fn recordAllocation(self: *GCStats) void {
        _ = self.allocations.fetchAdd(1, .monotonic);
        const current = self.current_objects.fetchAdd(1, .monotonic) + 1;
        self.updatePeak(current);
    }

    pub fn recordDeallocation(self: *GCStats) void {
        _ = self.deallocations.fetchAdd(1, .monotonic);
        _ = self.current_objects.fetchSub(1, .monotonic);
    }

    pub fn recordCollection(self: *GCStats, objects: usize) void {
        _ = self.collections.fetchAdd(1, .monotonic);
        _ = self.objects_collected.fetchAdd(objects, .monotonic);
    }

    pub fn recordCycle(self: *GCStats) void {
        _ = self.cycles_detected.fetchAdd(1, .monotonic);
    }

    fn updatePeak(self: *GCStats, current: usize) void {
        var peak = self.peak_objects.load(.acquire);
        while (current > peak) {
            const result = self.peak_objects.cmpxchgWeak(peak, current, .release, .acquire);
            if (result) |new_peak| {
                peak = new_peak;
            } else {
                break;
            }
        }
    }

    pub fn getStats(self: *const GCStats) struct {
        allocations: usize,
        deallocations: usize,
        collections: usize,
        objects_collected: usize,
        cycles_detected: usize,
        peak_objects: usize,
        current_objects: usize,
    } {
        return .{
            .allocations = self.allocations.load(.acquire),
            .deallocations = self.deallocations.load(.acquire),
            .collections = self.collections.load(.acquire),
            .objects_collected = self.objects_collected.load(.acquire),
            .cycles_detected = self.cycles_detected.load(.acquire),
            .peak_objects = self.peak_objects.load(.acquire),
            .current_objects = self.current_objects.load(.acquire),
        };
    }
};

/// GC generation for generational collection
pub const Generation = enum(u2) {
    young = 0,
    middle = 1,
    old = 2,

    pub fn next(self: Generation) Generation {
        return switch (self) {
            .young => .middle,
            .middle => .old,
            .old => .old,
        };
    }
};

/// Object header for GC tracking
pub const GCHeader = struct {
    refcount: std.atomic.Value(usize),
    gc_refs: std.atomic.Value(isize),
    generation: Generation,
    marked: std.atomic.Value(bool),
    in_cycle: std.atomic.Value(bool),
    next: ?*GCHeader,
    prev: ?*GCHeader,

    pub fn init() GCHeader {
        return .{
            .refcount = std.atomic.Value(usize).init(1),
            .gc_refs = std.atomic.Value(isize).init(0),
            .generation = .young,
            .marked = std.atomic.Value(bool).init(false),
            .in_cycle = std.atomic.Value(bool).init(false),
            .next = null,
            .prev = null,
        };
    }

    pub fn incref(self: *GCHeader) void {
        _ = self.refcount.fetchAdd(1, .monotonic);
    }

    pub fn decref(self: *GCHeader) bool {
        const prev = self.refcount.fetchSub(1, .release);
        if (prev == 1) {
            std.atomic.fence(.acquire);
            return true;
        }
        return false;
    }

    pub fn getRefcount(self: *const GCHeader) usize {
        return self.refcount.load(.acquire);
    }

    pub fn mark(self: *GCHeader) void {
        self.marked.store(true, .release);
    }

    pub fn unmark(self: *GCHeader) void {
        self.marked.store(false, .release);
    }

    pub fn isMarked(self: *const GCHeader) bool {
        return self.marked.load(.acquire);
    }

    pub fn promote(self: *GCHeader) void {
        self.generation = self.generation.next();
    }
};

/// Simple garbage collector for testing
pub const SimpleGC = struct {
    const Self = @This();

    objects: std.ArrayList(*GCHeader),
    allocator: std.mem.Allocator,
    stats: GCStats,
    mutex: std.Thread.Mutex,
    threshold: usize,
    enabled: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .objects = std.ArrayList(*GCHeader).init(allocator),
            .allocator = allocator,
            .stats = GCStats.init(),
            .mutex = .{},
            .threshold = 100,
            .enabled = std.atomic.Value(bool).init(true),
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.objects.items) |obj| {
            self.allocator.destroy(obj);
        }
        self.objects.deinit();
    }

    pub fn alloc(self: *Self) !*GCHeader {
        self.mutex.lock();
        defer self.mutex.unlock();

        const obj = try self.allocator.create(GCHeader);
        obj.* = GCHeader.init();

        try self.objects.append(obj);
        self.stats.recordAllocation();

        // Check if we should collect
        if (self.enabled.load(.acquire) and
            self.objects.items.len >= self.threshold)
        {
            self.collectInternal();
        }

        return obj;
    }

    pub fn free(self: *Self, obj: *GCHeader) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove from tracking list
        for (self.objects.items, 0..) |tracked, i| {
            if (tracked == obj) {
                _ = self.objects.swapRemove(i);
                break;
            }
        }

        self.allocator.destroy(obj);
        self.stats.recordDeallocation();
    }

    pub fn collect(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.collectInternal();
    }

    fn collectInternal(self: *Self) usize {
        var collected: usize = 0;

        // Mark phase
        for (self.objects.items) |obj| {
            obj.unmark();
        }

        // Sweep phase - collect objects with refcount 0
        var i: usize = 0;
        while (i < self.objects.items.len) {
            const obj = self.objects.items[i];
            if (obj.getRefcount() == 0) {
                _ = self.objects.swapRemove(i);
                self.allocator.destroy(obj);
                collected += 1;
            } else {
                i += 1;
            }
        }

        self.stats.recordCollection(collected);
        return collected;
    }

    pub fn enable(self: *Self) void {
        self.enabled.store(true, .release);
    }

    pub fn disable(self: *Self) void {
        self.enabled.store(false, .release);
    }

    pub fn setThreshold(self: *Self, threshold: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.threshold = threshold;
    }

    pub fn objectCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.objects.items.len;
    }
};

/// Cycle detector using DFS
pub const CycleDetector = struct {
    const Self = @This();
    const WHITE: u8 = 0; // Not visited
    const GRAY: u8 = 1; // In progress
    const BLACK: u8 = 2; // Finished

    colors: std.AutoHashMap(*GCHeader, u8),
    allocator: std.mem.Allocator,
    cycles_found: usize,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .colors = std.AutoHashMap(*GCHeader, u8).init(allocator),
            .allocator = allocator,
            .cycles_found = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.colors.deinit();
    }

    pub fn detectCycles(self: *Self, objects: []const *GCHeader) usize {
        self.colors.clearRetainingCapacity();
        self.cycles_found = 0;

        for (objects) |obj| {
            if ((self.colors.get(obj) orelse WHITE) == WHITE) {
                self.dfs(obj);
            }
        }

        return self.cycles_found;
    }

    fn dfs(self: *Self, obj: *GCHeader) void {
        self.colors.put(obj, GRAY) catch return;

        // Check references (simplified - in real impl would traverse object graph)
        if (obj.next) |next| {
            const color = self.colors.get(next) orelse WHITE;
            if (color == GRAY) {
                self.cycles_found += 1;
                obj.in_cycle.store(true, .release);
            } else if (color == WHITE) {
                self.dfs(next);
            }
        }

        self.colors.put(obj, BLACK) catch return;
    }
};

/// Finalization queue for deferred cleanup
pub const FinalizationQueue = struct {
    const Self = @This();

    queue: std.ArrayList(*GCHeader),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    processing: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .queue = std.ArrayList(*GCHeader).init(allocator),
            .mutex = .{},
            .allocator = allocator,
            .processing = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.queue.deinit();
    }

    pub fn enqueue(self: *Self, obj: *GCHeader) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.queue.append(obj);
    }

    pub fn process(self: *Self) usize {
        if (self.processing.swap(true, .acquire)) {
            return 0; // Already processing
        }
        defer self.processing.store(false, .release);

        self.mutex.lock();
        const items = self.queue.toOwnedSlice() catch return 0;
        self.mutex.unlock();
        defer self.allocator.free(items);

        var processed: usize = 0;
        for (items) |obj| {
            // Finalize object
            obj.unmark();
            processed += 1;
        }

        return processed;
    }

    pub fn len(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.queue.items.len;
    }
};

/// Write barrier for tracking mutations
pub const WriteBarrier = struct {
    const Self = @This();

    mutations: std.ArrayList(Mutation),
    mutex: std.Thread.Mutex,
    enabled: std.atomic.Value(bool),

    const Mutation = struct {
        source: *GCHeader,
        target: ?*GCHeader,
        timestamp: i64,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .mutations = std.ArrayList(Mutation).init(allocator),
            .mutex = .{},
            .enabled = std.atomic.Value(bool).init(true),
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.mutations.deinit();
    }

    pub fn recordMutation(self: *Self, source: *GCHeader, target: ?*GCHeader) !void {
        if (!self.enabled.load(.acquire)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.mutations.append(.{
            .source = source,
            .target = target,
            .timestamp = std.time.milliTimestamp(),
        });
    }

    pub fn clearMutations(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.mutations.clearRetainingCapacity();
    }

    pub fn mutationCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.mutations.items.len;
    }

    pub fn enable(self: *Self) void {
        self.enabled.store(true, .release);
    }

    pub fn disable(self: *Self) void {
        self.enabled.store(false, .release);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "gc_stats_tracking" {
    var stats = GCStats.init();

    stats.recordAllocation();
    stats.recordAllocation();
    stats.recordAllocation();
    stats.recordDeallocation();

    const s = stats.getStats();
    try std.testing.expectEqual(@as(usize, 3), s.allocations);
    try std.testing.expectEqual(@as(usize, 1), s.deallocations);
    try std.testing.expectEqual(@as(usize, 2), s.current_objects);
    try std.testing.expectEqual(@as(usize, 3), s.peak_objects);
}

test "gc_header_refcount" {
    var header = GCHeader.init();

    try std.testing.expectEqual(@as(usize, 1), header.getRefcount());

    header.incref();
    try std.testing.expectEqual(@as(usize, 2), header.getRefcount());

    try std.testing.expect(!header.decref());
    try std.testing.expectEqual(@as(usize, 1), header.getRefcount());

    try std.testing.expect(header.decref());
}

test "gc_header_marking" {
    var header = GCHeader.init();

    try std.testing.expect(!header.isMarked());
    header.mark();
    try std.testing.expect(header.isMarked());
    header.unmark();
    try std.testing.expect(!header.isMarked());
}

test "gc_header_promotion" {
    var header = GCHeader.init();

    try std.testing.expectEqual(Generation.young, header.generation);
    header.promote();
    try std.testing.expectEqual(Generation.middle, header.generation);
    header.promote();
    try std.testing.expectEqual(Generation.old, header.generation);
    header.promote();
    try std.testing.expectEqual(Generation.old, header.generation);
}

test "simple_gc_alloc_free" {
    const allocator = std.testing.allocator;
    var gc = SimpleGC.init(allocator);
    defer gc.deinit();

    const obj1 = try gc.alloc();
    const obj2 = try gc.alloc();

    try std.testing.expectEqual(@as(usize, 2), gc.objectCount());

    gc.free(obj1);
    try std.testing.expectEqual(@as(usize, 1), gc.objectCount());

    gc.free(obj2);
    try std.testing.expectEqual(@as(usize, 0), gc.objectCount());
}

test "simple_gc_collect" {
    const allocator = std.testing.allocator;
    var gc = SimpleGC.init(allocator);
    gc.disable(); // Prevent auto collection
    defer gc.deinit();

    const obj1 = try gc.alloc();
    const obj2 = try gc.alloc();
    _ = try gc.alloc();

    // Simulate object becoming garbage
    _ = obj1.decref();
    _ = obj2.decref();

    const collected = gc.collect();
    try std.testing.expectEqual(@as(usize, 2), collected);
    try std.testing.expectEqual(@as(usize, 1), gc.objectCount());
}

test "cycle_detector_basic" {
    const allocator = std.testing.allocator;

    var obj1 = GCHeader.init();
    var obj2 = GCHeader.init();
    var obj3 = GCHeader.init();

    // Create a cycle: obj1 -> obj2 -> obj3 -> obj1
    obj1.next = &obj2;
    obj2.next = &obj3;
    obj3.next = &obj1;

    var detector = CycleDetector.init(allocator);
    defer detector.deinit();

    var objects = [_]*GCHeader{ &obj1, &obj2, &obj3 };
    const cycles = detector.detectCycles(&objects);

    try std.testing.expect(cycles > 0);
}

test "finalization_queue_basic" {
    const allocator = std.testing.allocator;

    var obj1 = GCHeader.init();
    var obj2 = GCHeader.init();

    var queue = FinalizationQueue.init(allocator);
    defer queue.deinit();

    try queue.enqueue(&obj1);
    try queue.enqueue(&obj2);

    try std.testing.expectEqual(@as(usize, 2), queue.len());

    const processed = queue.process();
    try std.testing.expectEqual(@as(usize, 2), processed);
    try std.testing.expectEqual(@as(usize, 0), queue.len());
}

test "write_barrier_recording" {
    const allocator = std.testing.allocator;

    var source = GCHeader.init();
    var target = GCHeader.init();

    var barrier = WriteBarrier.init(allocator);
    defer barrier.deinit();

    try barrier.recordMutation(&source, &target);
    try barrier.recordMutation(&source, null);

    try std.testing.expectEqual(@as(usize, 2), barrier.mutationCount());

    barrier.clearMutations();
    try std.testing.expectEqual(@as(usize, 0), barrier.mutationCount());
}

test "write_barrier_enable_disable" {
    const allocator = std.testing.allocator;

    var source = GCHeader.init();
    var target = GCHeader.init();

    var barrier = WriteBarrier.init(allocator);
    defer barrier.deinit();

    try barrier.recordMutation(&source, &target);
    try std.testing.expectEqual(@as(usize, 1), barrier.mutationCount());

    barrier.disable();
    try barrier.recordMutation(&source, &target);
    try std.testing.expectEqual(@as(usize, 1), barrier.mutationCount());

    barrier.enable();
    try barrier.recordMutation(&source, &target);
    try std.testing.expectEqual(@as(usize, 2), barrier.mutationCount());
}

test "gc_concurrent_allocation" {
    const allocator = std.testing.allocator;
    var gc = SimpleGC.init(allocator);
    gc.disable();
    defer gc.deinit();

    const num_threads = 4;
    const allocs_per_thread = 10;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(g: *SimpleGC) void {
                for (0..allocs_per_thread) |_| {
                    if (g.alloc()) |obj| {
                        _ = obj.decref();
                    } else |_| {}
                }
            }
        }.run, .{&gc}) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    try std.testing.expectEqual(@as(usize, num_threads * allocs_per_thread), gc.objectCount());
}
