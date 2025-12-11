/// gc_gil - GC with GIL
/// Mirrors cpython/Python/gc_gil.c (and gc.c)
///
/// Cyclic garbage collector for standard (GIL-based) Python builds.
/// Uses reference counting with cycle detection via mark-sweep.

// Re-export submodules
pub const types = @import("gc_gil/types.zig");
pub const generation = @import("gc_gil/generation.zig");
pub const runtime_state = @import("gc_gil/runtime_state.zig");
pub const api = @import("gc_gil/api.zig");
pub const module = @import("gc_gil/module.zig");

// Re-export commonly used types
pub const GCThresholds = types.GCThresholds;
pub const GCFlags = types.GCFlags;
pub const GCHead = types.GCHead;
pub const CollectResult = types.CollectResult;
pub const GCStats = types.GCStats;
pub const GCDebugFlags = types.GCDebugFlags;

pub const GCGeneration = generation.GCGeneration;

pub const GCRuntimeState = runtime_state.GCRuntimeState;

// Re-export public API
pub const collect = api.collect;
pub const enable = api.enable;
pub const disable = api.disable;
pub const isEnabled = api.isEnabled;
pub const getThreshold = api.getThreshold;
pub const setThreshold = api.setThreshold;
pub const getCount = api.getCount;

// Re-export module functions
pub const init = module.init;
pub const getGCState = module.getGCState;
pub const setGCState = module.setGCState;
pub const reset = module.reset;

// Tests are distributed across submodules
test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
