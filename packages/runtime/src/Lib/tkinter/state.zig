//! Module state management
//!
//! Tracks tkinter module initialization and availability

/// Module initialization state
var initialized: bool = false;

/// Initialize tkinter module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

/// Check if Tk is available
pub fn isTkAvailable() bool {
    return false;
}
