/// _opcode_metadata/state.zig - Module state management
/// Manages initialization and state for the _opcode_metadata module.

var initialized: bool = false;

/// Initialize the _opcode_metadata module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}
