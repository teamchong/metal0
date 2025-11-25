/// Operator code generation
/// Handles binary ops, unary ops, comparisons, and boolean operations
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;

/// Recursively collect all parts of a string concatenation chain
fn collectConcatParts(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        const left_type = try self.type_inferrer.inferExpr(node.binop.left.*);
        const right_type = try self.type_inferrer.inferExpr(node.binop.right.*);

        // Only flatten if this is string concatenation
        if (left_type == .string or right_type == .string) {
            try collectConcatParts(self, node.binop.left.*, parts);
            try collectConcatParts(self, node.binop.right.*, parts);
            return;
        }
    }

    // Base case: not a string concatenation binop, add to parts
    try parts.append(self.allocator, node);
}

/// Generate binary operations (+, -, *, /, %, //)
pub fn genBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    // Check if this is string concatenation
    if (binop.op == .Add) {
        const left_type = try self.type_inferrer.inferExpr(binop.left.*);
        const right_type = try self.type_inferrer.inferExpr(binop.right.*);

        if (left_type == .string or right_type == .string) {
            // Flatten nested concatenations to avoid intermediate allocations
            var parts = std.ArrayList(ast.Node){};
            defer parts.deinit(self.allocator);

            try collectConcatParts(self, ast.Node{ .binop = binop }, &parts);

            // Get allocator name based on scope
            const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

            // Generate single concat call with all parts
            try self.emit("try std.mem.concat(");
            try self.emit(alloc_name);
            try self.emit(", u8, &[_][]const u8{ ");
            for (parts.items, 0..) |part, i| {
                if (i > 0) try self.emit(", ");
                try genExpr(self, part);
            }
            try self.emit(" })");
            return;
        }
    }

    // Regular numeric operations
    // Special handling for modulo - use @rem for signed integers
    if (binop.op == .Mod) {
        try self.emit("@rem(");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Special handling for floor division
    if (binop.op == .FloorDiv) {
        try self.emit("@divFloor(");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Special handling for power
    if (binop.op == .Pow) {
        try self.emit("std.math.pow(i64, ");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Special handling for division - can throw ZeroDivisionError
    if (binop.op == .Div) {
        // True division (/) - always returns float
        try self.emit("try runtime.divideFloat(");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Special handling for floor division - returns int
    if (binop.op == .FloorDiv) {
        try self.emit("try runtime.divideInt(");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Special handling for modulo - can throw ZeroDivisionError
    if (binop.op == .Mod) {
        try self.emit("try runtime.moduloInt(");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Check for type mismatches between usize and i64
    const left_type = try self.type_inferrer.inferExpr(binop.left.*);
    const right_type = try self.type_inferrer.inferExpr(binop.right.*);

    const left_is_usize = (left_type == .usize);
    const left_is_int = (left_type == .int);
    const right_is_usize = (right_type == .usize);
    const right_is_int = (right_type == .int);

    // If mixing usize and i64, cast to i64 for the operation
    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    try self.emit("(");

    // Cast left operand if needed
    if (left_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    try genExpr(self, binop.left.*);
    if (left_is_usize and needs_cast) {
        try self.emit("))");
    }

    const op_str = switch (binop.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .BitAnd => " & ",
        .BitOr => " | ",
        .BitXor => " ^ ",
        .LShift => " << ",
        .RShift => " >> ",
        else => " ? ",
    };
    try self.emit(op_str);

    // Cast right operand if needed
    if (right_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    try genExpr(self, binop.right.*);
    if (right_is_usize and needs_cast) {
        try self.emit("))");
    }

    try self.emit(")");
}

/// Generate unary operations (not, -, ~)
pub fn genUnaryOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    switch (unaryop.op) {
        .Not => {
            try self.emit("!(");
            try genExpr(self, unaryop.operand.*);
            try self.emit(")");
        },
        .USub => {
            // In Python, -bool converts to int first: -True = -1, -False = 0
            const operand_type = try self.type_inferrer.inferExpr(unaryop.operand.*);
            if (operand_type == .bool) {
                try self.emit("-@as(i64, @intFromBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit("))");
            } else {
                try self.emit("-(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
        },
        .UAdd => {
            // In Python, +bool converts to int: +True = 1, +False = 0
            const operand_type = try self.type_inferrer.inferExpr(unaryop.operand.*);
            if (operand_type == .bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit("))");
            } else {
                // Non-bool: unary plus is a no-op
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
        },
        .Invert => {
            // Bitwise NOT: ~x in Zig
            // Cast to i64 to handle comptime_int literals
            try self.emit("~@as(i64, ");
            try genExpr(self, unaryop.operand.*);
            try self.emit(")");
        },
    }
}

/// Generate comparison operations (==, !=, <, <=, >, >=)
/// Handles Python chained comparisons: 1 < x < 10 becomes (1 < x) and (x < 10)
pub fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
    // Check if we're comparing strings (need std.mem.eql instead of ==)
    const left_type = try self.type_inferrer.inferExpr(compare.left.*);

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

        const right_type = try self.type_inferrer.inferExpr(compare.comparators[i]);

        // For chained comparisons after the first, left side is the previous comparator
        const current_left = if (i == 0) compare.left.* else compare.comparators[i - 1];
        const current_left_type = if (i == 0) left_type else try self.type_inferrer.inferExpr(compare.comparators[i - 1]);

        // Special handling for string comparisons
        // Also handle cases where one side is .unknown (e.g., json.loads) comparing to string
        const left_is_string = (current_left_type == .string);
        const right_is_string = (right_type == .string);
        const either_string = left_is_string or right_is_string;
        const neither_unknown = (current_left_type != .unknown and right_type != .unknown);

        if ((left_is_string and right_is_string) or (either_string and !neither_unknown)) {
            switch (op) {
                .Eq => {
                    try self.emit("std.mem.eql(u8, ");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(")");
                },
                .NotEq => {
                    try self.emit("!std.mem.eql(u8, ");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(")");
                },
                .In => {
                    // String substring check: std.mem.indexOf(u8, haystack, needle) != null
                    try self.emit("(std.mem.indexOf(u8, ");
                    try genExpr(self, compare.comparators[i]); // haystack
                    try self.emit(", ");
                    try genExpr(self, current_left); // needle
                    try self.emit(") != null)");
                },
                .NotIn => {
                    // String substring check (negated)
                    try self.emit("(std.mem.indexOf(u8, ");
                    try genExpr(self, compare.comparators[i]); // haystack
                    try self.emit(", ");
                    try genExpr(self, current_left); // needle
                    try self.emit(") == null)");
                },
                else => {
                    // String comparison operators other than == and != not supported
                    try genExpr(self, current_left);
                    const op_str = switch (op) {
                        .Lt => " < ",
                        .LtEq => " <= ",
                        .Gt => " > ",
                        .GtEq => " >= ",
                        else => " ? ",
                    };
                    try self.emit(op_str);
                    try genExpr(self, compare.comparators[i]);
                },
            }
        }
        // Handle 'in' operator for lists
        else if (op == .In or op == .NotIn) {
            if (right_type == .list) {
                // List membership check: std.mem.indexOfScalar(T, slice, value) != null
                const elem_type = right_type.list.*;
                const type_str = elem_type.toSimpleZigType();

                try self.emit("(std.mem.indexOfScalar(");
                try self.emit(type_str);
                try self.emit(", ");
                try genExpr(self, compare.comparators[i]); // list/slice
                try self.emit(", ");
                try genExpr(self, current_left); // item to search for

                if (op == .In) {
                    try self.emit(") != null)");
                } else {
                    try self.emit(") == null)");
                }
            } else if (right_type == .dict) {
                // Dict key check: dict.contains(key)
                if (op == .In) {
                    try genExpr(self, compare.comparators[i]); // dict
                    try self.emit(".contains(");
                    try genExpr(self, current_left); // key
                    try self.emit(")");
                } else {
                    try self.emit("!");
                    try genExpr(self, compare.comparators[i]); // dict
                    try self.emit(".contains(");
                    try genExpr(self, current_left); // key
                    try self.emit(")");
                }
            } else {
                // Fallback for arrays and unrecognized types
                // Infer element type from the item being searched for

                // String arrays need special handling - can't use indexOfScalar
                // because strings require std.mem.eql for comparison, not ==
                if (current_left_type == .string) {
                    // Generate inline block expression that loops through array
                    try self.emit("(blk: {\n");
                    try self.emit("for (");
                    try genExpr(self, compare.comparators[i]); // array
                    try self.emit(") |__item| {\n");
                    try self.emit("if (std.mem.eql(u8, __item, ");
                    try genExpr(self, current_left); // search string
                    try self.emit(")) break :blk true;\n");
                    try self.emit("}\n");
                    try self.emit("break :blk false;\n");
                    try self.emit("})");

                    // Handle 'not in' by negating the result
                    if (op == .NotIn) {
                        // Wrap in negation
                        const current_output = try self.output.toOwnedSlice(self.allocator);
                        try self.emit("!");
                        try self.emit(current_output);
                    }
                } else {
                    // Integer and float arrays use indexOfScalar
                    const elem_type_str = current_left_type.toSimpleZigType();

                    try self.emit("(std.mem.indexOfScalar(");
                    try self.emit(elem_type_str);
                    try self.emit(", &");
                    try genExpr(self, compare.comparators[i]); // array/container
                    try self.emit(", ");
                    try genExpr(self, current_left); // item to search for
                    if (op == .In) {
                        try self.emit(") != null)");
                    } else {
                        try self.emit(") == null)");
                    }
                }
            }
        }
        // Special handling for None comparisons
        else if (current_left_type == .none or right_type == .none) {
            // None comparisons with mixed types: result is known at compile time
            // but we must reference the non-None variable to avoid "unused" errors
            const cleft_tag = @as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type);
            const right_tag = @as(std.meta.Tag(@TypeOf(right_type)), right_type);
            if (cleft_tag != right_tag) {
                // One is None, other is not - emit block that references the non-None side
                // The None side (?void) is allowed to be unused
                const result = switch (op) {
                    .Eq => "false",
                    .NotEq => "true",
                    else => "false",
                };
                // Reference the non-None variable to mark it as used
                if (current_left_type != .none) {
                    // Left is non-None, reference it
                    try self.emit("(blk: { _ = ");
                    try genExpr(self, current_left);
                    try self.emitFmt("; break :blk {s}; }})", .{result});
                } else {
                    // Right is non-None, reference it
                    try self.emit("(blk: { _ = ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emitFmt("; break :blk {s}; }})", .{result});
                }
            } else {
                // Both are None - compare normally
                try genExpr(self, current_left);
                const op_str = switch (op) {
                    .Eq => " == ",
                    .NotEq => " != ",
                    else => " == ", // Other comparisons default to ==
                };
                try self.emit(op_str);
                try genExpr(self, compare.comparators[i]);
            }
        }
        // Handle 'is' and 'is not' identity operators
        else if (op == .Is or op == .IsNot) {
            // For primitives (int, bool, None), identity is same as equality
            // For objects/slices, compare pointer addresses
            try genExpr(self, current_left);
            if (op == .Is) {
                try self.emit(" == ");
            } else {
                try self.emit(" != ");
            }
            try genExpr(self, compare.comparators[i]);
        } else {
            // Regular comparisons for non-strings
            // Check for type mismatches between usize and i64
            const left_is_usize = (current_left_type == .usize);
            const left_is_int = (current_left_type == .int);
            const right_is_usize = (right_type == .usize);
            const right_is_int = (right_type == .int);

            // If mixing usize and i64, cast to i64 for comparison
            const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

            // Cast left operand if needed
            if (left_is_usize and needs_cast) {
                try self.emit("@as(i64, @intCast(");
            }
            try genExpr(self, current_left);
            if (left_is_usize and needs_cast) {
                try self.emit("))");
            }

            const op_str = switch (op) {
                .Eq => " == ",
                .NotEq => " != ",
                .Lt => " < ",
                .LtEq => " <= ",
                .Gt => " > ",
                .GtEq => " >= ",
                else => " ? ",
            };
            try self.emit(op_str);

            // Cast right operand if needed
            if (right_is_usize and needs_cast) {
                try self.emit("@as(i64, @intCast(");
            }
            try genExpr(self, compare.comparators[i]);
            if (right_is_usize and needs_cast) {
                try self.emit("))");
            }
        }

        // Close individual comparison paren for chained comparisons
        if (is_chained) {
            try self.emit(")");
        }
    }

    // Close outer paren for chained comparisons
    if (is_chained) {
        try self.emit(")");
    }
}

/// Generate boolean operations (and, or)
pub fn genBoolOp(self: *NativeCodegen, boolop: ast.Node.BoolOp) CodegenError!void {
    const op_str = if (boolop.op == .And) " and " else " or ";

    for (boolop.values, 0..) |value, i| {
        if (i > 0) try self.emit(op_str);
        try genExpr(self, value);
    }
}
