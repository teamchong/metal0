/// runtime_state - GC runtime state and collection logic
/// Main GC state machine and collection algorithms

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const generation = @import("generation.zig");

const GCHead = types.GCHead;
const GCThresholds = types.GCThresholds;
const GCDebugFlags = types.GCDebugFlags;
const GCStats = types.GCStats;
const CollectResult = types.CollectResult;
const GCGeneration = generation.GCGeneration;

// ============================================================================
// GC Runtime State
// ============================================================================

/// GC runtime state
pub const GCRuntimeState = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Young generation (0)
    gen0: GCGeneration = .{},
    /// Middle generation (1)
    gen1: GCGeneration = .{},
    /// Old generation (2)
    gen2: GCGeneration = .{},
    /// Permanent generation (immortal objects)
    permanent: GCGeneration = .{},
    /// Objects with legacy finalizers
    garbage: GCGeneration = .{},
    /// Thresholds
    thresholds: GCThresholds = .{},
    /// GC is enabled
    enabled: bool = true,
    /// Debug flags
    debug: GCDebugFlags = .{},
    /// Number of allocations since last gen0 collection
    alloc_count: i64 = 0,
    /// Collecting flag (prevent recursion)
    collecting: bool = false,
    /// Callbacks to run during collection
    callbacks: std.ArrayList(*const fn (*Self) void),

    pub fn init(allocator: Allocator) Self {
        var self = Self{
            .allocator = allocator,
            .callbacks = std.ArrayList(*const fn (*Self) void).init(allocator),
        };
        self.gen0.initList();
        self.gen1.initList();
        self.gen2.initList();
        self.permanent.initList();
        self.garbage.initList();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.callbacks.deinit();
    }

    /// Track a new object
    pub fn track(self: *Self, gc: *GCHead) void {
        gc.flags.tracked = true;
        gc.generation = 0;
        self.gen0.add(gc);
        self.alloc_count += 1;
    }

    /// Untrack an object
    pub fn untrack(self: *Self, gc: *GCHead) void {
        if (!gc.flags.tracked) return;

        const gen = self.getGeneration(gc.generation);
        gen.remove(gc);
        gc.flags.tracked = false;
    }

    /// Get generation by index
    fn getGeneration(self: *Self, index: u8) *GCGeneration {
        return switch (index) {
            0 => &self.gen0,
            1 => &self.gen1,
            2 => &self.gen2,
            else => &self.permanent,
        };
    }

    /// Enable GC
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// Disable GC
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }

    /// Check if collection is needed
    pub fn maybeCollect(self: *Self) bool {
        if (!self.enabled or self.collecting) return false;

        if (self.alloc_count > self.thresholds.gen0) {
            _ = self.collectGeneration(0);
            return true;
        }
        return false;
    }

    /// Collect a specific generation
    pub fn collectGeneration(self: *Self, generation_index: u8) CollectResult {
        if (self.collecting) {
            return .{ .collected = 0, .uncollectable = 0 };
        }

        self.collecting = true;
        defer self.collecting = false;

        // Run callbacks
        for (self.callbacks.items) |callback| {
            callback(self);
        }

        var collected: u64 = 0;
        var uncollectable: u64 = 0;

        // Collect up to and including the specified generation
        var gen: u8 = 0;
        while (gen <= generation_index) : (gen += 1) {
            const result = self.collectSingleGeneration(gen);
            collected += result.collected;
            uncollectable += result.uncollectable;
        }

        // Update allocation count
        if (generation_index == 0) {
            self.alloc_count = 0;
        }

        return .{ .collected = collected, .uncollectable = uncollectable };
    }

    /// Collect a single generation
    fn collectSingleGeneration(self: *Self, generation_index: u8) CollectResult {
        const gen = self.getGeneration(generation_index);

        // Phase 1: Update gc_refs from refcount
        var it = gen.iterator();
        while (it.next()) |gc| {
            gc.gc_refs = 1; // Simplified - would use actual refcount
            gc.flags.reachable = false;
        }

        // Phase 2: Subtract internal references
        // AOT Limitation: tp_traverse requires runtime type info not available in AOT
        // In CPython, this calls obj->ob_type->tp_traverse(obj, visit_decref, NULL)
        // For AOT, objects with cycles must use explicit weak references
        it = gen.iterator();
        while (it.next()) |gc| {
            _ = gc;
        }

        // Phase 3: Mark reachable
        it = gen.iterator();
        while (it.next()) |gc| {
            if (gc.gc_refs > 0) {
                self.markReachable(gc);
            }
        }

        // Phase 4: Collect unreachable
        var collected: u64 = 0;
        var uncollectable: u64 = 0;

        it = gen.iterator();
        while (it.next()) |gc| {
            if (!gc.flags.reachable) {
                if (gc.flags.has_legacy_finalizer) {
                    // Move to garbage list
                    gen.remove(gc);
                    self.garbage.add(gc);
                    uncollectable += 1;
                } else {
                    // Collectable
                    collected += 1;
                }
            }
        }

        // Phase 5: Promote survivors (for gen 0 and 1)
        if (generation_index < 2) {
            self.promoteGeneration(generation_index);
        }

        // Update stats
        gen.collections += 1;
        gen.collected += collected;
        gen.uncollectable += uncollectable;

        return .{ .collected = collected, .uncollectable = uncollectable };
    }

    /// Mark object and all reachable objects
    fn markReachable(self: *Self, gc: *GCHead) void {
        if (gc.flags.reachable) return;
        gc.flags.reachable = true;

        // Would traverse tp_traverse here
        _ = self;
    }

    /// Promote survivors to next generation
    fn promoteGeneration(self: *Self, generation_index: u8) void {
        const from = self.getGeneration(generation_index);
        const to = self.getGeneration(generation_index + 1);

        var it = from.iterator();
        while (it.next()) |gc| {
            if (gc.flags.reachable) {
                from.remove(gc);
                to.add(gc);
                gc.generation = generation_index + 1;
            }
        }
    }

    /// Get thresholds
    pub fn getThresholds(self: *const Self) [3]u32 {
        return .{ self.thresholds.gen0, self.thresholds.gen1, self.thresholds.gen2 };
    }

    /// Set thresholds
    pub fn setThresholds(self: *Self, gen0: u32, gen1: u32, gen2: u32) void {
        self.thresholds.gen0 = gen0;
        self.thresholds.gen1 = gen1;
        self.thresholds.gen2 = gen2;
    }

    /// Get object counts
    pub fn getCounts(self: *const Self) [3]usize {
        return .{ self.gen0.count, self.gen1.count, self.gen2.count };
    }

    /// Get total stats
    pub fn getStats(self: *const Self) GCStats {
        return GCStats{
            .collections = .{
                self.gen0.collections,
                self.gen1.collections,
                self.gen2.collections,
            },
            .collected = .{
                self.gen0.collected,
                self.gen1.collected,
                self.gen2.collected,
            },
            .uncollectable = self.gen0.uncollectable +
                self.gen1.uncollectable +
                self.gen2.uncollectable,
        };
    }

    /// Freeze an object (move to permanent generation)
    pub fn freeze(self: *Self, gc: *GCHead) void {
        if (!gc.flags.tracked) return;

        const gen = self.getGeneration(gc.generation);
        gen.remove(gc);
        self.permanent.add(gc);
        gc.generation = 255; // Mark as permanent
    }

    /// Check if object is tracked
    pub fn isTracked(gc: *const GCHead) bool {
        return gc.flags.tracked;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "gc runtime state" {
    const allocator = std.testing.allocator;

    var state = GCRuntimeState.init(allocator);
    defer state.deinit();

    try std.testing.expect(state.enabled);
    try std.testing.expect(!state.collecting);

    var gc = GCHead{};
    state.track(&gc);
    try std.testing.expect(gc.flags.tracked);
    try std.testing.expectEqual(@as(u8, 0), gc.generation);

    state.untrack(&gc);
    try std.testing.expect(!gc.flags.tracked);
}

test "thresholds" {
    const allocator = std.testing.allocator;

    var state = GCRuntimeState.init(allocator);
    defer state.deinit();

    const thresholds = state.getThresholds();
    try std.testing.expectEqual(@as(u32, 700), thresholds[0]);

    state.setThresholds(100, 5, 5);
    const new_thresholds = state.getThresholds();
    try std.testing.expectEqual(@as(u32, 100), new_thresholds[0]);
}

test "collection" {
    const allocator = std.testing.allocator;

    var state = GCRuntimeState.init(allocator);
    defer state.deinit();

    // Track some objects
    var gc1 = GCHead{};
    var gc2 = GCHead{};
    state.track(&gc1);
    state.track(&gc2);

    // Run collection
    const result = state.collectGeneration(0);
    _ = result;

    // Check stats updated
    try std.testing.expect(state.gen0.collections > 0);
}

test "freeze object" {
    const allocator = std.testing.allocator;

    var state = GCRuntimeState.init(allocator);
    defer state.deinit();

    var gc = GCHead{};
    state.track(&gc);
    try std.testing.expectEqual(@as(u8, 0), gc.generation);

    state.freeze(&gc);
    try std.testing.expectEqual(@as(u8, 255), gc.generation);
}
