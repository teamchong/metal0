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

// Re-export submodules
pub const types = @import("gc/types.zig");
pub const state = @import("gc/state.zig");
pub const collector = @import("gc/collector.zig");
pub const api = @import("gc/api.zig");

// Re-export types
pub const GCHead = types.GCHead;
pub const Generation = types.Generation;
pub const GCCallback = types.GCCallback;
pub const Phase = types.Phase;
pub const GCInfo = types.GCInfo;
pub const GCStats = types.GCStats;
pub const Debug = types.Debug;

// Re-export state
pub const GCState = state.GCState;

// Re-export API functions
pub const init = api.init;
pub const initState = api.initState;
pub const enable = api.enable;
pub const disable = api.disable;
pub const isEnabled = api.isEnabled;
pub const setDebug = api.setDebug;
pub const getDebug = api.getDebug;
pub const getThreshold = api.getThreshold;
pub const setThreshold = api.setThreshold;
pub const track = api.track;
pub const untrack = api.untrack;
pub const isTracked = api.isTracked;
pub const collect = api.collect;
pub const getStats = api.getStats;
pub const getCount = api.getCount;
pub const getObjects = api.getObjects;
pub const registerCallback = api.registerCallback;
pub const unregisterCallback = api.unregisterCallback;
pub const freeze = api.freeze;
pub const unfreeze = api.unfreeze;
pub const getFreezeCount = api.getFreezeCount;
pub const getReferrers = api.getReferrers;
pub const getReferents = api.getReferents;
pub const finalize = api.finalize;

// ============================================================================
// Tests
// ============================================================================

test {
    _ = types;
    _ = state;
    _ = collector;
    _ = api;
}
