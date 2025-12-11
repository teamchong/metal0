/// module - Module initialization and global state
/// Manages global GC state singleton

const runtime_state = @import("runtime_state.zig");
const GCRuntimeState = runtime_state.GCRuntimeState;

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
