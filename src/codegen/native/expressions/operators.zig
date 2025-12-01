/// Operator code generation - re-exports from specialized modules
/// Handles binary ops, unary ops, comparisons, and boolean operations

// Import specialized modules
const arithmetic = @import("operators/arithmetic.zig");
const comparison = @import("operators/comparison.zig");
const logical = @import("operators/logical.zig");

// Re-export public functions
pub const genBinOp = arithmetic.genBinOp;
pub const genUnaryOp = arithmetic.genUnaryOp;
pub const genCompare = comparison.genCompare;
pub const genBoolOp = logical.genBoolOp;
