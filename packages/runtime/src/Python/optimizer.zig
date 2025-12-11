/// optimizer - Bytecode Optimizer
/// Mirrors cpython/Python/optimizer.c
///
/// The optimizer transforms bytecode to improve performance by analyzing
/// execution traces and generating optimized "micro-ops" (uops).

// Re-export all submodules
pub const config = @import("optimizer/config.zig");
pub const types = @import("optimizer/types.zig");
pub const trace = @import("optimizer/trace.zig");
pub const state = @import("optimizer/state.zig");
pub const passes = @import("optimizer/passes.zig");
pub const module = @import("optimizer/module.zig");

// Re-export commonly used types
pub const OptimizerConfig = config.OptimizerConfig;
pub const MicroOp = types.MicroOp;
pub const UopOpcode = types.UopOpcode;
pub const TypeInfo = types.TypeInfo;
pub const TypeId = types.TypeId;
pub const Guard = types.Guard;
pub const GuardKind = types.GuardKind;
pub const OptimizerStats = types.OptimizerStats;
pub const ExecutionTrace = trace.ExecutionTrace;
pub const Optimizer = state.Optimizer;

// Re-export functions
pub const peepholeOptimize = passes.peepholeOptimize;
pub const inlineFunction = passes.inlineFunction;
pub const init = module.init;
pub const getOptimizer = module.getOptimizer;
pub const setOptimizer = module.setOptimizer;
pub const reset = module.reset;

// Re-export global config
pub const global_config = &config.config;

// Tests
test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("optimizer/tests.zig");
}
