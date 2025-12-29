/// Comparison operations: ==, !=, <, <=, >, >=, in, not in, is, is not
/// Handles Python chained comparisons: 1 < x < 10 becomes (1 < x) and (x < 10)
/// ALWAYS wraps output in parentheses to prevent Zig chained comparison errors
///
/// Uses builder pattern with ZigValue for type-safe code generation.
/// exprToValue uses captureExpr internally for proper builder state management.
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const CompOp = builder_mod.CompOp;

/// Convert Python comparison operator to CompOp
fn cmpOpToCompOp(op: ast.CompareOp) CompOp {
    return switch (op) {
        .Eq => .eq,
        .NotEq => .ne,
        .Lt => .lt,
        .LtEq => .le,
        .Gt => .gt,
        .GtEq => .ge,
        .In => .in_,
        .NotIn => .not_in,
        .Is => .is,
        .IsNot => .is_not,
    };
}

/// Generate comparison operations (==, !=, <, <=, >, >=)
/// Handles Python chained comparisons: 1 < x < 10 becomes (1 < x) and (x < 10)
/// ALWAYS wraps output in parentheses to prevent Zig chained comparison errors
/// when a compare is used as a sub-expression in another compare
pub fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
    const b = try self.getBuilder();

    // Always wrap comparison in parentheses to make it safe as a sub-expression
    try b.emitRaw("(");

    // Convert left operand to ZigValue (uses captureExpr for proper builder state)
    const left_val = try self.exprToValue(compare.left.*);

    // For chained comparisons (more than 1 op), wrap everything in parens
    const is_chained = compare.ops.len > 1;
    if (is_chained) {
        try b.emitRaw("(");
    }

    for (compare.ops, 0..) |op, i| {
        // Add "and" between comparisons for chained comparisons
        if (i > 0) {
            try b.emitRaw(" and ");
        }

        // For chained comparisons, wrap each individual comparison in parens
        if (is_chained) {
            try b.emitRaw("(");
        }

        // Convert right operand to ZigValue
        const right_val = try self.exprToValue(compare.comparators[i]);

        // For chained comparisons after the first, left side is the previous comparator
        const current_left = if (i == 0) left_val else try self.exprToValue(compare.comparators[i - 1]);

        // Convert ast.CmpOp to builder.CompOp
        const comp_op = cmpOpToCompOp(op);

        // Use builder's unified comparison emission
        try b.emitComparison(comp_op, current_left, right_val);

        // Close individual comparison paren for chained comparisons
        if (is_chained) {
            try b.emitRaw(")");
        }
    }

    // Close outer paren for chained comparisons
    if (is_chained) {
        try b.emitRaw(")");
    }

    // Close the outer parenthesis opened at the start of genCompare
    try b.emitRaw(")");

    // Flush builder to output
    try self.flushBuilder();
}
