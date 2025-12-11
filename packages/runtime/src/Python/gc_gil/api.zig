/// api - Public GC API functions
/// High-level interface for garbage collection operations

const runtime_state = @import("runtime_state.zig");
const GCRuntimeState = runtime_state.GCRuntimeState;

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
