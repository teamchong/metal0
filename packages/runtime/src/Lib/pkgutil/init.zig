/// pkgutil/init.zig - Module initialization
/// Handles module state initialization and reset

/// Module state
var initialized: bool = false;

/// Initialize the pkgutil module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}
