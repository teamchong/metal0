/// gc_gil - GC with GIL
/// Mirrors cpython/Python/gc_gil.c (and gc.c)
///
/// Cyclic garbage collector for standard (GIL-based) Python builds.
/// Uses reference counting with cycle detection via mark-sweep.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// GC Configuration
// ============================================================================

/// GC thresholds per generation
pub const GCThresholds = struct {
    /// Generation 0 (young) threshold
    gen0: u32 = 700,
    /// Generation 1 threshold
    gen1: u32 = 10,
    /// Generation 2 (old) threshold
    gen2: u32 = 10,
};

/// GC flags
pub const GCFlags = packed struct {
    /// Object is tracked
    tracked: bool = false,
    /// Object is reachable
    reachable: bool = false,
    /// Object is a candidate for collection
    collecting: bool = false,
    /// Object has __del__ method
    has_legacy_finalizer: bool = false,
    /// Object's tp_finalize was called
    finalized: bool = false,
    /// Reserved
    _reserved: u3 = 0,
};

// ============================================================================
// GC Object Header
// ============================================================================

/// GC header prepended to container objects
pub const GCHead = struct {
    /// Pointer for doubly-linked list
    gc_next: ?*GCHead = null,
    gc_prev: ?*GCHead = null,
    /// Reference count adjustment for cycle detection
    gc_refs: i64 = 0,
    /// GC flags
    flags: GCFlags = .{},
    /// Generation
    generation: u8 = 0,

    /// Get the actual object pointer
    pub fn fromObject(obj: *anyopaque) *GCHead {
        return @as(*GCHead, @ptrFromInt(@intFromPtr(obj) - @sizeOf(GCHead)));
    }

    /// Get object from GC head
    pub fn toObject(self: *GCHead) *anyopaque {
        return @as(*anyopaque, @ptrFromInt(@intFromPtr(self) + @sizeOf(GCHead)));
    }
};

// ============================================================================
// Generation
// ============================================================================

/// GC generation list
pub const GCGeneration = struct {
    const Self = @This();

    /// List head (sentinel)
    head: GCHead = .{},
    /// Object count
    count: usize = 0,
    /// Collection count
    collections: u64 = 0,
    /// Objects collected
    collected: u64 = 0,
    /// Uncollectable (legacy finalizers)
    uncollectable: u64 = 0,

    pub fn initList(self: *Self) void {
        self.head.gc_next = &self.head;
        self.head.gc_prev = &self.head;
    }

    /// Add object to generation list
    pub fn add(self: *Self, gc: *GCHead) void {
        gc.gc_next = self.head.gc_next;
        gc.gc_prev = &self.head;
        if (self.head.gc_next) |next| {
            next.gc_prev = gc;
        }
        self.head.gc_next = gc;
        self.count += 1;
    }

    /// Remove object from list
    pub fn remove(self: *Self, gc: *GCHead) void {
        if (gc.gc_prev) |prev| {
            prev.gc_next = gc.gc_next;
        }
        if (gc.gc_next) |next| {
            next.gc_prev = gc.gc_prev;
        }
        gc.gc_next = null;
        gc.gc_prev = null;
        if (self.count > 0) {
            self.count -= 1;
        }
    }

    /// Check if list is empty
    pub fn isEmpty(self: *const Self) bool {
        return self.head.gc_next == &self.head or self.count == 0;
    }

    /// Iterate over objects in generation
    pub fn iterator(self: *Self) Iterator {
        return Iterator{ .current = self.head.gc_next, .sentinel = &self.head };
    }

    pub const Iterator = struct {
        current: ?*GCHead,
        sentinel: *GCHead,

        pub fn next(self: *Iterator) ?*GCHead {
            if (self.current == self.sentinel or self.current == null) {
                return null;
            }
            const gc = self.current.?;
            self.current = gc.gc_next;
            return gc;
        }
    };
};

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
    pub fn collectGeneration(self: *Self, generation: u8) CollectResult {
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
        while (gen <= generation) : (gen += 1) {
            const result = self.collectSingleGeneration(gen);
            collected += result.collected;
            uncollectable += result.uncollectable;
        }

        // Update allocation count
        if (generation == 0) {
            self.alloc_count = 0;
        }

        return .{ .collected = collected, .uncollectable = uncollectable };
    }

    /// Collect a single generation
    fn collectSingleGeneration(self: *Self, generation: u8) CollectResult {
        const gen = self.getGeneration(generation);

        // Phase 1: Update gc_refs from refcount
        var it = gen.iterator();
        while (it.next()) |gc| {
            gc.gc_refs = 1; // Simplified - would use actual refcount
            gc.flags.reachable = false;
        }

        // Phase 2: Subtract internal references
        it = gen.iterator();
        while (it.next()) |gc| {
            // For each object gc references, decrement its gc_refs
            // This is simplified - real impl traverses tp_traverse
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
        if (generation < 2) {
            self.promoteGeneration(generation);
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
    fn promoteGeneration(self: *Self, generation: u8) void {
        const from = self.getGeneration(generation);
        const to = self.getGeneration(generation + 1);

        var it = from.iterator();
        while (it.next()) |gc| {
            if (gc.flags.reachable) {
                from.remove(gc);
                to.add(gc);
                gc.generation = generation + 1;
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

/// Collection result
pub const CollectResult = struct {
    collected: u64,
    uncollectable: u64,
};

/// GC statistics
pub const GCStats = struct {
    collections: [3]u64,
    collected: [3]u64,
    uncollectable: u64,
};

/// Debug flags
pub const GCDebugFlags = packed struct {
    stats: bool = false,
    collectable: bool = false,
    uncollectable: bool = false,
    saveall: bool = false,
    leak: bool = false,
    _reserved: u3 = 0,
};

// ============================================================================
// Public API
// ============================================================================

/// Collect garbage
pub fn collect(state: *GCRuntimeState, generation: ?u8) u64 {
    const gen = generation orelse 2;
    const result = state.collectGeneration(gen);
    return result.collected;
}

/// Enable automatic collection
pub fn enable(state: *GCRuntimeState) void {
    state.enable();
}

/// Disable automatic collection
pub fn disable(state: *GCRuntimeState) void {
    state.disable();
}

/// Check if GC is enabled
pub fn isEnabled(state: *const GCRuntimeState) bool {
    return state.enabled;
}

/// Get/set thresholds
pub fn getThreshold(state: *const GCRuntimeState) [3]u32 {
    return state.getThresholds();
}

pub fn setThreshold(state: *GCRuntimeState, gen0: u32, gen1: u32, gen2: u32) void {
    state.setThresholds(gen0, gen1, gen2);
}

/// Get object count
pub fn getCount(state: *const GCRuntimeState) [3]usize {
    return state.getCounts();
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;
var gc_state: ?*GCRuntimeState = null;

/// Initialize the gc_gil module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global GC state
pub fn getGCState() ?*GCRuntimeState {
    return gc_state;
}

/// Set global GC state
pub fn setGCState(state: *GCRuntimeState) void {
    gc_state = state;
}

/// Reset module state
pub fn reset() void {
    gc_state = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "gc head operations" {
    var gc = GCHead{};
    try std.testing.expect(!gc.flags.tracked);

    gc.flags.tracked = true;
    try std.testing.expect(gc.flags.tracked);
}

test "generation list" {
    var gen = GCGeneration{};
    gen.initList();

    try std.testing.expect(gen.isEmpty());

    var gc1 = GCHead{};
    var gc2 = GCHead{};

    gen.add(&gc1);
    try std.testing.expectEqual(@as(usize, 1), gen.count);
    try std.testing.expect(!gen.isEmpty());

    gen.add(&gc2);
    try std.testing.expectEqual(@as(usize, 2), gen.count);

    gen.remove(&gc1);
    try std.testing.expectEqual(@as(usize, 1), gen.count);
}

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
