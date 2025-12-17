//! List, dict, and generator comprehension code generation
//!
//! This module was split into multiple files for maintainability:
//! - comp_utils.zig: Shared helpers and type maps
//! - comp_conditions.zig: Condition generation functions (truthiness conversion)
//! - comp_expr_subs.zig: Expression with variable substitutions
//! - comp_list.zig: List comprehension (SIMD, parallel, Metal, scalar)
//! - comp_dict.zig: Dict comprehension
//! - comp_genexp.zig: Generator expression
//!
//! MIGRATION STATUS: Prepared for ZigBuilder - imports added

// Re-export public functions from split modules
pub const genListComp = @import("comp_list.zig").genListComp;
pub const genDictComp = @import("comp_dict.zig").genDictComp;
pub const genGenExp = @import("comp_genexp.zig").genGenExp;

// Re-export utilities for use by other modules
pub const genComprehensionCondition = @import("comp_conditions.zig").genComprehensionCondition;
pub const genComprehensionConditionNoSubs = @import("comp_conditions.zig").genComprehensionConditionNoSubs;
pub const emitForLoopTarget = @import("comp_conditions.zig").emitForLoopTarget;
pub const genExprWithSubs = @import("comp_expr_subs.zig").genExprWithSubs;

// Re-export utility types and maps
pub const IntReturningBuiltins = @import("comp_utils.zig").IntReturningBuiltins;
pub const BoolReturningBuiltins = @import("comp_utils.zig").BoolReturningBuiltins;
pub const StringReturningMethods = @import("comp_utils.zig").StringReturningMethods;
pub const isIntExpr = @import("comp_utils.zig").isIntExpr;
pub const isBoolExpr = @import("comp_utils.zig").isBoolExpr;
pub const getGenExpElementType = @import("comp_utils.zig").getGenExpElementType;
pub const isStringReturningMethod = @import("comp_utils.zig").isStringReturningMethod;
pub const nativeTypeToZigStr = @import("comp_utils.zig").nativeTypeToZigStr;
