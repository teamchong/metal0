/// _pydecimal.module - Module-level state and initialization
/// Manages global context and module lifecycle

const context = @import("context.zig");

pub const Context = context.Context;

// ============================================================================
// Module State
// ============================================================================

/// Module initialization flag
var initialized: bool = false;

/// Default decimal context
var default_context: ?Context = null;

/// Initialize the _pydecimal module
/// Sets up default context if not already initialized
pub fn init() void {
    if (initialized) return;
    initialized = true;
    default_context = Context{};
}

/// Get the current default context
/// Returns pointer to module-level default context
pub fn getContext() *Context {
    if (default_context == null) {
        default_context = Context{};
    }
    return &default_context.?;
}

/// Set the default context
/// Replaces the current default context with a new one
pub fn setContext(ctx: Context) void {
    default_context = ctx;
}

/// Reset module state
/// Clears initialization flag and context (for testing)
pub fn reset() void {
    default_context = null;
    initialized = false;
}
