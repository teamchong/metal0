/// Module state management
/// Handles module initialization tracking

var initialized: bool = false;

/// Initialize the instruction_sequence module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}
