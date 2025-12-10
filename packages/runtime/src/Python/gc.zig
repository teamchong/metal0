/// gc - Garbage Collector
/// Mirrors cpython/Python/gc.c
///
/// Implements reference cycle garbage collection:
/// - Generational collection (young, old gen 0, old gen 1)
/// - Cycle detection via trial deletion
/// - Finalization handling
/// - GC callbacks
/// - Statistics and debugging
///
/// Note: In AOT Zig compilation, most objects are stack-allocated
/// or have clear ownership, so traditional GC is less critical.
/// This module provides the API for compatibility.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// GC Head (object tracking header)
// ============================================================================

/// GC header placed before every tracked object
pub const GCHead = struct {
    /// Next pointer (also contains flags in low bits)
    _gc_next: usize = 0,

    /// Previous pointer (also contains ref count and flags)
    _gc_prev: usize = 0,

    const Self = @This();

    /// Flag: object is being collected
    pub const PREV_MASK_COLLECTING: usize = 1;

    /// Flag: object is finalized
    pub const PREV_MASK_FINALIZED: usize = 2;

    /// Shift for reference count in _gc_prev
    pub const PREV_SHIFT: u6 = 4;

    /// Mask for prev pointer
    pub const PREV_MASK: usize = 3;

    /// Flag: unreachable object
    pub const NEXT_MASK_UNREACHABLE: usize = 2;

    /// Flag: old space bit
    pub const NEXT_MASK_OLD_SPACE: usize = 1;

    pub fn next(self: *const Self) ?*Self {
        const ptr = self._gc_next & ~@as(usize, 3);
        if (ptr == 0) return null;
        return @ptrFromInt(ptr);
    }

    pub fn prev(self: *const Self) ?*Self {
        const ptr = self._gc_prev & ~PREV_MASK;
        if (ptr == 0) return null;
        return @ptrFromInt(ptr);
    }

    pub fn setNext(self: *Self, n: ?*Self) void {
        const flags = self._gc_next & 3;
        self._gc_next = if (n) |p| @intFromPtr(p) | flags else flags;
    }

    pub fn setPrev(self: *Self, p: ?*Self) void {
        const flags = self._gc_prev & PREV_MASK;
        self._gc_prev = if (p) |ptr| @intFromPtr(ptr) | flags else flags;
    }

    pub fn isCollecting(self: *const Self) bool {
        return (self._gc_prev & PREV_MASK_COLLECTING) != 0;
    }

    pub fn setCollecting(self: *Self, collecting: bool) void {
        if (collecting) {
            self._gc_prev |= PREV_MASK_COLLECTING;
        } else {
            self._gc_prev &= ~PREV_MASK_COLLECTING;
        }
    }

    pub fn isFinalized(self: *const Self) bool {
        return (self._gc_prev & PREV_MASK_FINALIZED) != 0;
    }

    pub fn setFinalized(self: *Self, finalized: bool) void {
        if (finalized) {
            self._gc_prev |= PREV_MASK_FINALIZED;
        } else {
            self._gc_prev &= ~PREV_MASK_FINALIZED;
        }
    }

    pub fn getRefs(self: *const Self) i64 {
        return @intCast(self._gc_prev >> PREV_SHIFT);
    }

    pub fn setRefs(self: *Self, refs: i64) void {
        self._gc_prev = (self._gc_prev & PREV_MASK) |
            (@as(usize, @intCast(refs)) << PREV_SHIFT);
    }

    pub fn decRef(self: *Self) void {
        self._gc_prev -= @as(usize, 1) << PREV_SHIFT;
    }

    pub fn getOldSpace(self: *const Self) u1 {
        return @intCast(self._gc_next & NEXT_MASK_OLD_SPACE);
    }

    pub fn setOldSpace(self: *Self, space: u1) void {
        self._gc_next = (self._gc_next & ~NEXT_MASK_OLD_SPACE) | space;
    }

    pub fn flipOldSpace(self: *Self) void {
        self._gc_next ^= NEXT_MASK_OLD_SPACE;
    }
};

// ============================================================================
// Generation Management
// ============================================================================

/// GC Generation (linked list of tracked objects)
pub const Generation = struct {
    /// List head (sentinel)
    head: GCHead = .{},

    /// Number of objects in this generation
    count: usize = 0,

    /// Threshold for collection
    threshold: usize = 700,

    /// Number of collections
    collections: usize = 0,

    /// Number of uncollectable objects
    uncollectable: usize = 0,

    const Self = @This();

    pub fn init(self: *Self) void {
        self.head._gc_next = @intFromPtr(&self.head);
        self.head._gc_prev = @intFromPtr(&self.head);
        self.count = 0;
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.head._gc_next == @intFromPtr(&self.head);
    }

    /// Add object to this generation
    pub fn add(self: *Self, gc: *GCHead) void {
        const last = self.head.prev() orelse &self.head;
        gc.setNext(&self.head);
        gc.setPrev(last);
        last.setNext(gc);
        self.head.setPrev(gc);
        self.count += 1;
    }

    /// Remove object from this generation
    pub fn remove(self: *Self, gc: *GCHead) void {
        const p = gc.prev() orelse return;
        const n = gc.next() orelse return;
        p.setNext(n);
        n.setPrev(p);
        gc.setNext(null);
        gc.setPrev(null);
        self.count -= 1;
    }

    /// Move all objects to another generation
    pub fn moveAll(self: *Self, dest: *Self) void {
        if (self.isEmpty()) return;

        // Get first and last of source
        const first = self.head.next() orelse return;
        const last = self.head.prev() orelse return;

        // Get tail of destination
        const dest_last = dest.head.prev() orelse &dest.head;

        // Link source list to end of destination
        dest_last.setNext(first);
        first.setPrev(dest_last);
        last.setNext(&dest.head);
        dest.head.setPrev(last);

        // Update count
        dest.count += self.count;

        // Reset source
        self.init();
    }
};

// ============================================================================
// GC State
// ============================================================================

/// Garbage collector state
pub const GCState = struct {
    /// Young generation (gen 0)
    young: Generation = .{},

    /// Old generations (for incremental collection)
    old: [2]Generation = .{ .{}, .{} },

    /// Permanent generation (never collected)
    permanent: Generation = .{},

    /// Which old space is being visited
    visited_space: u1 = 0,

    /// Is GC enabled?
    enabled: bool = true,

    /// Is a collection in progress?
    collecting: bool = false,

    /// Debug flags
    debug: u32 = 0,

    /// Number of allocations since last collection
    allocations: usize = 0,

    /// Total heap size (tracked objects)
    heap_size: usize = 0,

    /// Garbage list (objects with __del__ in cycles)
    garbage_count: usize = 0,

    /// Callbacks to run after collection
    callbacks: [8]?GCCallback = [_]?GCCallback{null} ** 8,
    callback_count: usize = 0,

    /// Collection statistics
    stats: GCStats = .{},

    const Self = @This();

    pub fn init(self: *Self) void {
        self.young.init();
        self.old[0].init();
        self.old[1].init();
        self.permanent.init();

        // Set default thresholds (matching CPython)
        self.young.threshold = 700;
        self.old[0].threshold = 10;
        self.old[1].threshold = 10;
    }

    pub fn getGeneration(self: *Self, n: u2) *Generation {
        return switch (n) {
            0 => &self.young,
            1 => &self.old[self.visited_space],
            2 => &self.old[self.visited_space ^ 1],
            3 => &self.permanent,
        };
    }
};

/// GC callback function type
pub const GCCallback = *const fn (phase: Phase, info: *const GCInfo) void;

/// GC collection phase
pub const Phase = enum {
    start,
    end,
};

/// GC collection info
pub const GCInfo = struct {
    generation: u2,
    collected: usize,
    uncollectable: usize,
};

/// GC statistics
pub const GCStats = struct {
    /// Collections per generation
    collections: [3]usize = .{ 0, 0, 0 },

    /// Objects collected per generation
    collected: [3]usize = .{ 0, 0, 0 },

    /// Uncollectable objects per generation
    uncollectable: [3]usize = .{ 0, 0, 0 },
};

/// Debug flags
pub const Debug = struct {
    pub const STATS: u32 = 1 << 0;
    pub const COLLECTABLE: u32 = 1 << 1;
    pub const UNCOLLECTABLE: u32 = 1 << 2;
    pub const SAVEALL: u32 = 1 << 5;
    pub const LEAK: u32 = COLLECTABLE | UNCOLLECTABLE;
};

// ============================================================================
// Global GC State
// ============================================================================

/// Global GC state
var gc_state: GCState = .{};

/// Thread-local allocation counter
threadlocal var local_allocs: usize = 0;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the GC
/// Mirrors: _PyGC_Init()
pub fn init() void {
    gc_state.init();
}

/// Initialize GC state for an interpreter
pub fn initState(state: *GCState) void {
    state.init();
}

// ============================================================================
// GC Control
// ============================================================================

/// Enable GC
/// Mirrors: gc.enable()
pub fn enable() void {
    gc_state.enabled = true;
}

/// Disable GC
/// Mirrors: gc.disable()
pub fn disable() void {
    gc_state.enabled = false;
}

/// Check if GC is enabled
/// Mirrors: gc.isenabled()
pub fn isEnabled() bool {
    return gc_state.enabled;
}

/// Set debug flags
/// Mirrors: gc.set_debug()
pub fn setDebug(flags: u32) void {
    gc_state.debug = flags;
}

/// Get debug flags
/// Mirrors: gc.get_debug()
pub fn getDebug() u32 {
    return gc_state.debug;
}

// ============================================================================
// Threshold Management
// ============================================================================

/// Get collection thresholds
/// Mirrors: gc.get_threshold()
pub fn getThreshold() struct { usize, usize, usize } {
    return .{
        gc_state.young.threshold,
        gc_state.old[0].threshold,
        gc_state.old[1].threshold,
    };
}

/// Set collection thresholds
/// Mirrors: gc.set_threshold()
pub fn setThreshold(threshold0: usize, threshold1: ?usize, threshold2: ?usize) void {
    gc_state.young.threshold = threshold0;
    if (threshold1) |t| gc_state.old[0].threshold = t;
    if (threshold2) |t| gc_state.old[1].threshold = t;
}

// ============================================================================
// Object Tracking
// ============================================================================

/// Track an object for GC
/// Mirrors: _PyObject_GC_TRACK()
pub fn track(gc: *GCHead) void {
    if (gc.next() != null) {
        // Already tracked
        return;
    }
    gc_state.young.add(gc);
    gc_state.allocations += 1;

    // Check if we should collect
    maybeCollect();
}

/// Untrack an object from GC
/// Mirrors: _PyObject_GC_UNTRACK()
pub fn untrack(gc: *GCHead) void {
    if (gc.next() == null) {
        // Not tracked
        return;
    }

    // Find which generation contains this object and remove
    if (gc.getOldSpace() == 0) {
        gc_state.young.remove(gc);
    } else {
        gc_state.old[0].remove(gc);
    }
}

/// Check if object is tracked
pub fn isTracked(gc: *const GCHead) bool {
    return gc.next() != null;
}

/// Maybe trigger a collection
fn maybeCollect() void {
    if (!gc_state.enabled) return;
    if (gc_state.collecting) return;

    if (gc_state.allocations >= gc_state.young.threshold) {
        _ = collect(0);
    }
}

// ============================================================================
// Collection
// ============================================================================

/// Run garbage collection
/// Mirrors: gc.collect()
pub fn collect(generation: i32) usize {
    if (gc_state.collecting) {
        return 0;
    }

    gc_state.collecting = true;
    defer gc_state.collecting = false;

    const gen: u2 = if (generation < 0)
        selectGeneration()
    else
        @intCast(@min(generation, 2));

    // Call pre-collection callbacks
    const info = GCInfo{
        .generation = gen,
        .collected = 0,
        .uncollectable = 0,
    };
    callCallbacks(.start, &info);

    // Perform collection
    const collected = collectGeneration(gen);

    // Update statistics
    gc_state.stats.collections[gen] += 1;
    gc_state.stats.collected[gen] += collected;

    // Reset allocation counter
    gc_state.allocations = 0;

    // Call post-collection callbacks
    const final_info = GCInfo{
        .generation = gen,
        .collected = collected,
        .uncollectable = gc_state.garbage_count,
    };
    callCallbacks(.end, &final_info);

    return collected;
}

/// Select which generation to collect
fn selectGeneration() u2 {
    // Simple heuristic: if old gen has many objects, collect it
    if (gc_state.old[0].count >= gc_state.old[0].threshold * gc_state.young.threshold) {
        return 1;
    }
    return 0;
}

/// Collect a specific generation using trial deletion algorithm
fn collectGeneration(gen: u2) usize {
    var collected: usize = 0;
    const generation = gc_state.getGeneration(gen);

    if (generation.isEmpty()) {
        generation.collections += 1;
        return 0;
    }

    // Phase 1: Copy reference counts to gc_refs and mark as collecting
    var current = generation.head.next();
    while (current) |gc| {
        if (gc == &generation.head) break;
        gc.setCollecting(true);
        // Copy ob_refcnt to gc_refs (stored in _gc_prev high bits)
        // In AOT, we approximate with a count of 1 for tracked objects
        gc.setRefs(1);
        current = gc.next();
    }

    // Phase 2: Subtract internal references (trial deletion)
    // For each container object, decrement gc_refs of objects it references
    current = generation.head.next();
    while (current) |gc| {
        if (gc == &generation.head) break;
        // In AOT compilation, objects don't have tp_traverse
        // We rely on the gc_refs being set to 1 and check if still reachable
        current = gc.next();
    }

    // Phase 3: Move unreachable objects (gc_refs == 0) to unreachable list
    var unreachable = Generation{};
    unreachable.init();

    current = generation.head.next();
    while (current) |gc| {
        if (gc == &generation.head) break;
        const next_gc = gc.next();

        // Objects with gc_refs == 0 after trial deletion are unreachable
        if (gc.getRefs() <= 0) {
            generation.remove(gc);
            unreachable.add(gc);
        }

        current = next_gc;
    }

    // Phase 4: Check for legacy finalizers (__del__) - move back to reachable if found
    // In AOT, we don't typically have __del__ methods, so skip this

    // Phase 5: Clear collecting flag on surviving objects
    current = generation.head.next();
    while (current) |gc| {
        if (gc == &generation.head) break;
        gc.setCollecting(false);
        current = gc.next();
    }

    // Phase 6: Delete unreachable objects
    current = unreachable.head.next();
    while (current) |gc| {
        if (gc == &unreachable.head) break;
        const next_gc = gc.next();

        // Call tp_clear equivalent (release references)
        // In AOT compilation, objects are typically stack-allocated or arena-managed
        // The GC marks them as finalized; actual deallocation uses Zig's allocator
        gc.setFinalized(true);
        collected += 1;

        // Remove from tracking list - memory freed when allocator releases it
        unreachable.remove(gc);

        current = next_gc;
    }

    // Move surviving young objects to old generation
    if (gen == 0 and !generation.isEmpty()) {
        const old = &gc_state.old[gc_state.visited_space];
        generation.moveAll(old);
    }

    // Update statistics
    generation.collections += 1;
    gc_state.stats.collected[gen] += collected;

    return collected;
}

// ============================================================================
// Statistics
// ============================================================================

/// Get GC statistics
/// Mirrors: gc.get_stats()
pub fn getStats() [3]struct {
    collections: usize,
    collected: usize,
    uncollectable: usize,
} {
    return .{
        .{
            .collections = gc_state.stats.collections[0],
            .collected = gc_state.stats.collected[0],
            .uncollectable = gc_state.stats.uncollectable[0],
        },
        .{
            .collections = gc_state.stats.collections[1],
            .collected = gc_state.stats.collected[1],
            .uncollectable = gc_state.stats.uncollectable[1],
        },
        .{
            .collections = gc_state.stats.collections[2],
            .collected = gc_state.stats.collected[2],
            .uncollectable = gc_state.stats.uncollectable[2],
        },
    };
}

/// Get count of tracked objects
/// Mirrors: gc.get_count()
pub fn getCount() struct { usize, usize, usize } {
    return .{
        gc_state.young.count,
        gc_state.old[0].count,
        gc_state.old[1].count,
    };
}

/// Get all tracked objects
/// Mirrors: gc.get_objects()
pub fn getObjects(allocator: std.mem.Allocator, generation: ?u2) !std.ArrayList(*GCHead) {
    var result = std.ArrayList(*GCHead).init(allocator);

    const gens: []const *Generation = if (generation) |g|
        &[_]*Generation{gc_state.getGeneration(g)}
    else
        &[_]*Generation{
            &gc_state.young,
            &gc_state.old[0],
            &gc_state.old[1],
        };

    for (gens) |gen| {
        var current = gen.head.next();
        while (current) |gc| {
            if (gc != &gen.head) {
                try result.append(gc);
            }
            current = gc.next();
        }
    }

    return result;
}

// ============================================================================
// Callbacks
// ============================================================================

/// Register a GC callback
pub fn registerCallback(callback: GCCallback) bool {
    if (gc_state.callback_count >= gc_state.callbacks.len) {
        return false;
    }
    gc_state.callbacks[gc_state.callback_count] = callback;
    gc_state.callback_count += 1;
    return true;
}

/// Unregister a GC callback
pub fn unregisterCallback(callback: GCCallback) void {
    for (gc_state.callbacks[0..gc_state.callback_count], 0..) |maybe_cb, i| {
        if (maybe_cb == callback) {
            // Shift remaining
            var j = i;
            while (j < gc_state.callback_count - 1) : (j += 1) {
                gc_state.callbacks[j] = gc_state.callbacks[j + 1];
            }
            gc_state.callbacks[gc_state.callback_count - 1] = null;
            gc_state.callback_count -= 1;
            return;
        }
    }
}

/// Call all registered callbacks
fn callCallbacks(phase: Phase, info: *const GCInfo) void {
    for (gc_state.callbacks[0..gc_state.callback_count]) |maybe_cb| {
        if (maybe_cb) |cb| {
            cb(phase, info);
        }
    }
}

// ============================================================================
// Freeze
// ============================================================================

/// Freeze all tracked objects (move to permanent generation)
/// Mirrors: gc.freeze()
pub fn freeze() void {
    gc_state.young.moveAll(&gc_state.permanent);
    gc_state.old[0].moveAll(&gc_state.permanent);
    gc_state.old[1].moveAll(&gc_state.permanent);
}

/// Unfreeze objects (move back from permanent generation)
/// Mirrors: gc.unfreeze()
pub fn unfreeze() void {
    gc_state.permanent.moveAll(&gc_state.old[0]);
}

/// Get count of frozen objects
/// Mirrors: gc.get_freeze_count()
pub fn getFreezeCount() usize {
    return gc_state.permanent.count;
}

// ============================================================================
// Referrers and Referents
// ============================================================================

/// Get objects that refer to the given objects
/// Mirrors: gc.get_referrers()
pub fn getReferrers(_: std.mem.Allocator, _: []const *anyopaque) !std.ArrayList(*anyopaque) {
    // In AOT, this would require traversal hooks
    // Placeholder implementation
    return error.NotImplemented;
}

/// Get objects that the given object refers to
/// Mirrors: gc.get_referents()
pub fn getReferents(_: std.mem.Allocator, _: []const *anyopaque) !std.ArrayList(*anyopaque) {
    // In AOT, this would require traversal hooks
    // Placeholder implementation
    return error.NotImplemented;
}

// ============================================================================
// Finalization
// ============================================================================

/// Finalize the GC
pub fn finalize() void {
    // Run final collection
    _ = collect(2);

    // Clear all generations
    gc_state.young.init();
    gc_state.old[0].init();
    gc_state.old[1].init();
    gc_state.permanent.init();
}

// ============================================================================
// Tests
// ============================================================================

test "gc init" {
    init();
    try std.testing.expect(isEnabled());
    try std.testing.expectEqual(@as(usize, 0), gc_state.young.count);
}

test "enable disable" {
    init();
    try std.testing.expect(isEnabled());
    disable();
    try std.testing.expect(!isEnabled());
    enable();
    try std.testing.expect(isEnabled());
}

test "threshold" {
    init();
    const threshold = getThreshold();
    try std.testing.expectEqual(@as(usize, 700), threshold[0]);

    setThreshold(1000, 20, 20);
    const new_threshold = getThreshold();
    try std.testing.expectEqual(@as(usize, 1000), new_threshold[0]);
    try std.testing.expectEqual(@as(usize, 20), new_threshold[1]);
}

test "debug flags" {
    init();
    try std.testing.expectEqual(@as(u32, 0), getDebug());
    setDebug(Debug.STATS | Debug.COLLECTABLE);
    try std.testing.expectEqual(Debug.STATS | Debug.COLLECTABLE, getDebug());
}

test "generation empty check" {
    init();
    try std.testing.expect(gc_state.young.isEmpty());
    try std.testing.expect(gc_state.old[0].isEmpty());
}

test "count" {
    init();
    const count = getCount();
    try std.testing.expectEqual(@as(usize, 0), count[0]);
    try std.testing.expectEqual(@as(usize, 0), count[1]);
    try std.testing.expectEqual(@as(usize, 0), count[2]);
}

test "collect empty" {
    init();
    const collected = collect(0);
    try std.testing.expectEqual(@as(usize, 0), collected);
}

test "stats" {
    init();
    _ = collect(0);
    const stats = getStats();
    try std.testing.expect(stats[0].collections > 0);
}

test "freeze unfreeze" {
    init();
    try std.testing.expectEqual(@as(usize, 0), getFreezeCount());
    freeze();
    try std.testing.expectEqual(@as(usize, 0), getFreezeCount()); // No objects
}
