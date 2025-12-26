/// Comparison operations: ==, !=, <, <=, >, >=, in, not in, is, is not
/// Handles Python chained comparisons: 1 < x < 10 becomes (1 < x) and (x < 10)
/// ALWAYS wraps output in parentheses to prevent Zig chained comparison errors
///
/// REFACTORED: All comparison logic delegated to comparison_dispatch.zig
/// This file now only contains:
/// 1. The genCompare entry point
/// 2. Chained comparison loop logic (emitting "and" between comparisons)
/// 3. Outer parentheses handling
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const comparison_dispatch = @import("comparison_dispatch.zig");

/// Generate comparison operations (==, !=, <, <=, >, >=)
/// Handles Python chained comparisons: 1 < x < 10 becomes (1 < x) and (x < 10)
/// ALWAYS wraps output in parentheses to prevent Zig chained comparison errors
/// when a compare is used as a sub-expression in another compare
pub fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
    // Always wrap comparison in parentheses to make it safe as a sub-expression
    // This prevents: "False is (x is y)" from generating "false == x == y"
    // which Zig rejects as chained comparison
    try self.emit("(");

    // Infer left type once (used for first comparison)
    const left_type = try self.inferExprScoped(compare.left.*);

    // For chained comparisons (more than 1 op), wrap everything in parens
    const is_chained = compare.ops.len > 1;
    if (is_chained) {
        try self.emit("(");
    }

    for (compare.ops, 0..) |op, i| {
        // Add "and" between comparisons for chained comparisons
        if (i > 0) {
            try self.emit(" and ");
        }

        // For chained comparisons, wrap each individual comparison in parens
        if (is_chained) {
            try self.emit("(");
        }

        const right_type = try self.inferExprScoped(compare.comparators[i]);

        // For chained comparisons after the first, left side is the previous comparator
        const current_left = if (i == 0) compare.left.* else compare.comparators[i - 1];
        const current_left_type = if (i == 0) left_type else try self.inferExprScoped(compare.comparators[i - 1]);

        // Delegate ALL comparison logic to the unified dispatcher
        try comparison_dispatch.emitComparison(
            self,
            current_left,
            current_left_type,
            op,
            compare.comparators[i],
            right_type,
        );

        // Close individual comparison paren for chained comparisons
        if (is_chained) {
            try self.emit(")");
        }
    }

    // Close outer paren for chained comparisons
    if (is_chained) {
        try self.emit(")");
    }

    // Close the outer parenthesis opened at the start of genCompare
    try self.emit(")");
}
