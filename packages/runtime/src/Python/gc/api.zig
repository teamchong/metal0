/// api - GC Public API
/// Public functions for GC control and statistics.

const std = @import("std");
const types = @import("types.zig");
const state_mod = @import("state.zig");
const collector = @import("collector.zig");

pub const GCHead = types.GCHead;
pub const Generation = types.Generation;
pub const Debug = types.Debug;
pub const GCCallback = types.GCCallback;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the GC
/// Mirrors: _PyGC_Init()
pub fn init() void {
    state_mod.gc_state.init();
}

/// Initialize GC state for an interpreter
pub fn initState(state: *state_mod.GCState) void {
    state.init();
}

// ============================================================================
// GC Control
// ============================================================================

/// Enable GC
/// Mirrors: gc.enable()
pub fn enable() void {
    state_mod.gc_state.enabled = true;
}

/// Disable GC
/// Mirrors: gc.disable()
pub fn disable() void {
    state_mod.gc_state.enabled = false;
}

/// Check if GC is enabled
/// Mirrors: gc.isenabled()
pub fn isEnabled() bool {
    return state_mod.gc_state.enabled;
}

/// Set debug flags
/// Mirrors: gc.set_debug()
pub fn setDebug(flags: u32) void {
    state_mod.gc_state.debug = flags;
}

/// Get debug flags
/// Mirrors: gc.get_debug()
pub fn getDebug() u32 {
    return state_mod.gc_state.debug;
}

// ============================================================================
// Threshold Management
// ============================================================================

/// Get collection thresholds
/// Mirrors: gc.get_threshold()
pub fn getThreshold() struct { usize, usize, usize } {
    return .{
        state_mod.gc_state.young.threshold,
        state_mod.gc_state.old[0].threshold,
        state_mod.gc_state.old[1].threshold,
    };
}

/// Set collection thresholds
/// Mirrors: gc.set_threshold()
pub fn setThreshold(threshold0: usize, threshold1: ?usize, threshold2: ?usize) void {
    state_mod.gc_state.young.threshold = threshold0;
    if (threshold1) |t| state_mod.gc_state.old[0].threshold = t;
    if (threshold2) |t| state_mod.gc_state.old[1].threshold = t;
}

// ============================================================================
// Object Tracking
// ============================================================================

/// Track an object for GC
pub fn track(gc: *GCHead) void {
    collector.track(&state_mod.gc_state, gc);
}

/// Untrack an object from GC
pub fn untrack(gc: *GCHead) void {
    collector.untrack(&state_mod.gc_state, gc);
}

/// Check if object is tracked
pub fn isTracked(gc: *const GCHead) bool {
    return collector.isTracked(gc);
}

// ============================================================================
// Collection
// ============================================================================

/// Run garbage collection
/// Mirrors: gc.collect()
pub fn collect(generation: i32) usize {
    return collector.collect(&state_mod.gc_state, generation);
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
            .collections = state_mod.gc_state.stats.collections[0],
            .collected = state_mod.gc_state.stats.collected[0],
            .uncollectable = state_mod.gc_state.stats.uncollectable[0],
        },
        .{
            .collections = state_mod.gc_state.stats.collections[1],
            .collected = state_mod.gc_state.stats.collected[1],
            .uncollectable = state_mod.gc_state.stats.uncollectable[1],
        },
        .{
            .collections = state_mod.gc_state.stats.collections[2],
            .collected = state_mod.gc_state.stats.collected[2],
            .uncollectable = state_mod.gc_state.stats.uncollectable[2],
        },
    };
}

/// Get count of tracked objects
/// Mirrors: gc.get_count()
pub fn getCount() struct { usize, usize, usize } {
    return .{
        state_mod.gc_state.young.count,
        state_mod.gc_state.old[0].count,
        state_mod.gc_state.old[1].count,
    };
}

/// Get all tracked objects
/// Mirrors: gc.get_objects()
pub fn getObjects(allocator: std.mem.Allocator, generation: ?u2) !std.ArrayList(*GCHead) {
    var result = std.ArrayList(*GCHead).init(allocator);

    const gens: []const *Generation = if (generation) |g|
        &[_]*Generation{state_mod.gc_state.getGeneration(g)}
    else
        &[_]*Generation{
            &state_mod.gc_state.young,
            &state_mod.gc_state.old[0],
            &state_mod.gc_state.old[1],
        };

    for (gens) |gen| {
        var current = gen.head.next();
        while (current) |gc| {
            if (gc != &gen.head) {
                try result.append(allocator, gc);
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
    if (state_mod.gc_state.callback_count >= state_mod.gc_state.callbacks.len) {
        return false;
    }
    state_mod.gc_state.callbacks[state_mod.gc_state.callback_count] = callback;
    state_mod.gc_state.callback_count += 1;
    return true;
}

/// Unregister a GC callback
pub fn unregisterCallback(callback: GCCallback) void {
    for (state_mod.gc_state.callbacks[0..state_mod.gc_state.callback_count], 0..) |maybe_cb, i| {
        if (maybe_cb == callback) {
            var j = i;
            while (j < state_mod.gc_state.callback_count - 1) : (j += 1) {
                state_mod.gc_state.callbacks[j] = state_mod.gc_state.callbacks[j + 1];
            }
            state_mod.gc_state.callbacks[state_mod.gc_state.callback_count - 1] = null;
            state_mod.gc_state.callback_count -= 1;
            return;
        }
    }
}

// ============================================================================
// Freeze
// ============================================================================

/// Freeze all tracked objects (move to permanent generation)
/// Mirrors: gc.freeze()
pub fn freeze() void {
    state_mod.gc_state.young.moveAll(&state_mod.gc_state.permanent);
    state_mod.gc_state.old[0].moveAll(&state_mod.gc_state.permanent);
    state_mod.gc_state.old[1].moveAll(&state_mod.gc_state.permanent);
}

/// Unfreeze objects (move back from permanent generation)
/// Mirrors: gc.unfreeze()
pub fn unfreeze() void {
    state_mod.gc_state.permanent.moveAll(&state_mod.gc_state.old[0]);
}

/// Get count of frozen objects
/// Mirrors: gc.get_freeze_count()
pub fn getFreezeCount() usize {
    return state_mod.gc_state.permanent.count;
}

// ============================================================================
// Referrers and Referents
// ============================================================================

/// Get objects that refer to the given objects
/// AOT Limitation: Requires runtime type information
pub fn getReferrers(_: std.mem.Allocator, _: []const *anyopaque) !std.ArrayList(*anyopaque) {
    return error.NotImplemented;
}

/// Get objects that the given object refers to
/// AOT Limitation: Requires tp_traverse callback
pub fn getReferents(_: std.mem.Allocator, _: []const *anyopaque) !std.ArrayList(*anyopaque) {
    return error.NotImplemented;
}

// ============================================================================
// Finalization
// ============================================================================

/// Finalize the GC
pub fn finalize() void {
    _ = collect(2);

    state_mod.gc_state.young.init();
    state_mod.gc_state.old[0].init();
    state_mod.gc_state.old[1].init();
    state_mod.gc_state.permanent.init();
}

// ============================================================================
// Tests
// ============================================================================

test "gc init" {
    init();
    try std.testing.expect(isEnabled());
    try std.testing.expectEqual(@as(usize, 0), state_mod.gc_state.young.count);
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
    try std.testing.expect(state_mod.gc_state.young.isEmpty());
    try std.testing.expect(state_mod.gc_state.old[0].isEmpty());
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
    try std.testing.expectEqual(@as(usize, 0), getFreezeCount());
}
