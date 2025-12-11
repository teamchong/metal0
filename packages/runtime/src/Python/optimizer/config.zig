/// Optimizer Configuration
/// Provides configuration options for the bytecode optimizer

const std = @import("std");

/// Optimizer configuration
pub const OptimizerConfig = struct {
    /// Enable optimization
    enabled: bool = true,
    /// Minimum execution count before optimization
    threshold: u32 = 50,
    /// Maximum trace length
    max_trace_length: u32 = 512,
    /// Enable JIT compilation (if available)
    jit_enabled: bool = false,
    /// Optimization level (0-3)
    level: u8 = 2,
    /// Enable inlining
    inline_enabled: bool = true,
    /// Maximum inline depth
    max_inline_depth: u32 = 5,
    /// Enable constant folding
    const_fold_enabled: bool = true,
    /// Enable dead code elimination
    dce_enabled: bool = true,
};

/// Global optimizer configuration
pub var config: OptimizerConfig = .{};
