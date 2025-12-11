/// init - Initialization and Finalization
/// Mirrors cpython/Python/errors.c initialization functions
///
/// This module provides initialization and cleanup for the error handling subsystem.

const thread_state_mod = @import("thread_state.zig");
const core_api = @import("core_api.zig");

/// Initialize error handling subsystem
pub fn init() void {
    // Initialize thread state exc_info
    // This happens automatically via getThreadState() on first access
    _ = thread_state_mod.getThreadState();
}

/// Finalize error handling subsystem
pub fn fini() void {
    // Clean up any remaining exceptions
    core_api.clear();
}
