/// _pyio.module - Module initialization and state
/// Module lifecycle management

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _pyio module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}
