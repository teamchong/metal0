/// Module initialization and state management
/// Tracks whether the optimizer symbols module has been initialized

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the optimizer symbols module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}
