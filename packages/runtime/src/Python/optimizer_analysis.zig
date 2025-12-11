/// optimizer_analysis - Optimizer Analysis
/// Mirrors cpython/Python/optimizer_analysis.c
///
/// Provides analysis routines for the bytecode optimizer including
/// type inference, escape analysis, and data flow analysis.

const std = @import("std");

// Re-export submodules
pub const type_inference = @import("optimizer_analysis/type_inference.zig");
pub const dataflow = @import("optimizer_analysis/dataflow.zig");
pub const escape = @import("optimizer_analysis/escape.zig");
pub const range = @import("optimizer_analysis/range.zig");
pub const context = @import("optimizer_analysis/context.zig");

// Re-export commonly used types
pub const TypeLattice = type_inference.TypeLattice;
pub const TypeState = type_inference.TypeState;
pub const ConstValue = type_inference.ConstValue;

pub const AbstractValue = dataflow.AbstractValue;
pub const DataFlowState = dataflow.DataFlowState;

pub const EscapeState = escape.EscapeState;
pub const EscapeInfo = escape.EscapeInfo;
pub const EscapeAnalyzer = escape.EscapeAnalyzer;

pub const IntRange = range.IntRange;

pub const AnalysisContext = context.AnalysisContext;
pub const AnalysisWarning = context.AnalysisWarning;
pub const WarningKind = context.WarningKind;

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the optimizer analysis module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test {
    // Run all submodule tests
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(type_inference);
    std.testing.refAllDecls(dataflow);
    std.testing.refAllDecls(escape);
    std.testing.refAllDecls(range);
}
