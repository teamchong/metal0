/// Module Initialization and Global State
/// Manages global optimizer instance and module initialization

const state = @import("state.zig");
const Optimizer = state.Optimizer;

var initialized: bool = false;
var global_optimizer: ?*Optimizer = null;

/// Initialize the optimizer module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global optimizer instance
pub fn getOptimizer() ?*Optimizer {
    return global_optimizer;
}

/// Set global optimizer instance
pub fn setOptimizer(opt: *Optimizer) void {
    global_optimizer = opt;
}

/// Reset module state
pub fn reset() void {
    global_optimizer = null;
    initialized = false;
}
