/// collector - GC Collection
/// Collection algorithm and object tracking.

const std = @import("std");
const types = @import("types.zig");
const state_mod = @import("state.zig");

pub const GCHead = types.GCHead;
pub const Generation = types.Generation;
pub const Phase = types.Phase;
pub const GCInfo = types.GCInfo;
pub const GCState = state_mod.GCState;

// ============================================================================
// Object Tracking
// ============================================================================

/// Track an object for GC
/// Mirrors: _PyObject_GC_TRACK()
pub fn track(gc_state: *GCState, gc: *GCHead) void {
    if (gc.next() != null) {
        // Already tracked
        return;
    }
    gc_state.young.add(gc);
    gc_state.allocations += 1;

    // Check if we should collect
    maybeCollect(gc_state);
}

/// Untrack an object from GC
/// Mirrors: _PyObject_GC_UNTRACK()
pub fn untrack(gc_state: *GCState, gc: *GCHead) void {
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
fn maybeCollect(gc_state: *GCState) void {
    if (!gc_state.enabled) return;
    if (gc_state.collecting) return;

    if (gc_state.allocations >= gc_state.young.threshold) {
        _ = collect(gc_state, 0);
    }
}

// ============================================================================
// Collection
// ============================================================================

/// Run garbage collection
/// Mirrors: gc.collect()
pub fn collect(gc_state: *GCState, generation: i32) usize {
    if (gc_state.collecting) {
        return 0;
    }

    gc_state.collecting = true;
    defer gc_state.collecting = false;

    const gen: u2 = if (generation < 0)
        selectGeneration(gc_state)
    else
        @intCast(@min(generation, 2));

    // Call pre-collection callbacks
    const info = GCInfo{
        .generation = gen,
        .collected = 0,
        .uncollectable = 0,
    };
    callCallbacks(gc_state, .start, &info);

    // Perform collection
    const collected = collectGeneration(gc_state, gen);

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
    callCallbacks(gc_state, .end, &final_info);

    return collected;
}

/// Select which generation to collect
fn selectGeneration(gc_state: *GCState) u2 {
    // Simple heuristic: if old gen has many objects, collect it
    if (gc_state.old[0].count >= gc_state.old[0].threshold * gc_state.young.threshold) {
        return 1;
    }
    return 0;
}

/// Collect a specific generation using trial deletion algorithm
fn collectGeneration(gc_state: *GCState, gen: u2) usize {
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
        gc.setRefs(1);
        current = gc.next();
    }

    // Phase 2: Subtract internal references (trial deletion)
    current = generation.head.next();
    while (current) |gc| {
        if (gc == &generation.head) break;
        current = gc.next();
    }

    // Phase 3: Move unreachable objects (gc_refs == 0) to unreachable list
    var unreachable = Generation{};
    unreachable.init();

    current = generation.head.next();
    while (current) |gc| {
        if (gc == &generation.head) break;
        const next_gc = gc.next();

        if (gc.getRefs() <= 0) {
            generation.remove(gc);
            unreachable.add(gc);
        }

        current = next_gc;
    }

    // Phase 4: Clear collecting flag on surviving objects
    current = generation.head.next();
    while (current) |gc| {
        if (gc == &generation.head) break;
        gc.setCollecting(false);
        current = gc.next();
    }

    // Phase 5: Delete unreachable objects
    current = unreachable.head.next();
    while (current) |gc| {
        if (gc == &unreachable.head) break;
        const next_gc = gc.next();

        gc.setFinalized(true);
        collected += 1;
        unreachable.remove(gc);

        current = next_gc;
    }

    // Move surviving young objects to old generation
    if (gen == 0 and !generation.isEmpty()) {
        const old = &gc_state.old[gc_state.visited_space];
        generation.moveAll(old);
    }

    generation.collections += 1;
    gc_state.stats.collected[gen] += collected;

    return collected;
}

// ============================================================================
// Callbacks
// ============================================================================

/// Call all registered callbacks
fn callCallbacks(gc_state: *GCState, phase: Phase, info: *const GCInfo) void {
    for (gc_state.callbacks[0..gc_state.callback_count]) |maybe_cb| {
        if (maybe_cb) |cb| {
            cb(phase, info);
        }
    }
}
