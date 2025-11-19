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

            // Generate single concat call with all parts
            try self.output.appendSlice(self.allocator, "try std.mem.concat(allocator, u8, &[_][]const u8{ ");
            for (parts.items, 0..) |part, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, part);
            }
            try self.output.appendSlice(self.allocator, " })");
            return;
        }
    }

    // Regular numeric operations
    // Special handling for modulo - use @rem for signed integers
    if (binop.op == .Mod) {
        try self.output.appendSlice(self.allocator, "@rem(");
        try genExpr(self, binop.left.*);
        try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, binop.right.*);
        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Special handling for floor division
    if (binop.op == .FloorDiv) {
        try self.output.appendSlice(self.allocator, "@divFloor(");
        try genExpr(self, binop.left.*);
        try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, binop.right.*);
        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Special handling for power
    if (binop.op == .Pow) {
        try self.output.appendSlice(self.allocator, "std.math.pow(i64, ");
        try genExpr(self, binop.left.*);
        try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, binop.right.*);
        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Special handling for division - can throw ZeroDivisionError
    if (binop.op == .Div or binop.op == .FloorDiv) {
        try self.output.appendSlice(self.allocator, "try runtime.divideInt(");
        try genExpr(self, binop.left.*);
        try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, binop.right.*);
        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Special handling for modulo - can throw ZeroDivisionError
    if (binop.op == .Mod) {
        try self.output.appendSlice(self.allocator, "try runtime.moduloInt(");
        try genExpr(self, binop.left.*);
        try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, binop.right.*);
        try self.output.appendSlice(self.allocator, ")");
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

    try self.output.appendSlice(self.allocator, "(");

    // Cast left operand if needed
    if (left_is_usize and needs_cast) {
        try self.output.appendSlice(self.allocator, "@as(i64, @intCast(");
    }
    try genExpr(self, binop.left.*);
    if (left_is_usize and needs_cast) {
        try self.output.appendSlice(self.allocator, "))");
    }

    const op_str = switch (binop.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        else => " ? ",
    };
    try self.output.appendSlice(self.allocator, op_str);

    // Cast right operand if needed
    if (right_is_usize and needs_cast) {
        try self.output.appendSlice(self.allocator, "@as(i64, @intCast(");
    }
    try genExpr(self, binop.right.*);
    if (right_is_usize and needs_cast) {
        try self.output.appendSlice(self.allocator, "))");
    }

    try self.output.appendSlice(self.allocator, ")");
}

/// Generate unary operations (not, -)
pub fn genUnaryOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const op_str = switch (unaryop.op) {
        .Not => "!",
        .USub => "-",
        else => "?",
    };
    try self.output.appendSlice(self.allocator, op_str);
    // Wrap operand in parentheses to ensure correct precedence
    // e.g., "not x == 5" becomes "!(x == 5)" not "!x == 5"
    try self.output.appendSlice(self.allocator, "(");
    try genExpr(self, unaryop.operand.*);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate comparison operations (==, !=, <, <=, >, >=)
pub fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
    // Check if we're comparing strings (need std.mem.eql instead of ==)
    const left_type = try self.type_inferrer.inferExpr(compare.left.*);

    for (compare.ops, 0..) |op, i| {
        const right_type = try self.type_inferrer.inferExpr(compare.comparators[i]);

        // Special handling for string comparisons
        if (left_type == .string and right_type == .string) {
            switch (op) {
                .Eq => {
                    try self.output.appendSlice(self.allocator, "std.mem.eql(u8, ");
                    try genExpr(self, compare.left.*);
                    try self.output.appendSlice(self.allocator, ", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.output.appendSlice(self.allocator, ")");
                },
                .NotEq => {
                    try self.output.appendSlice(self.allocator, "!std.mem.eql(u8, ");
                    try genExpr(self, compare.left.*);
                    try self.output.appendSlice(self.allocator, ", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.output.appendSlice(self.allocator, ")");
                },
                .In => {
                    // String substring check: std.mem.indexOf(u8, haystack, needle) != null
                    try self.output.appendSlice(self.allocator, "(std.mem.indexOf(u8, ");
                    try genExpr(self, compare.comparators[i]); // haystack
                    try self.output.appendSlice(self.allocator, ", ");
                    try genExpr(self, compare.left.*); // needle
                    try self.output.appendSlice(self.allocator, ") != null)");
                },
                .NotIn => {
                    // String substring check (negated)
                    try self.output.appendSlice(self.allocator, "(std.mem.indexOf(u8, ");
                    try genExpr(self, compare.comparators[i]); // haystack
                    try self.output.appendSlice(self.allocator, ", ");
                    try genExpr(self, compare.left.*); // needle
                    try self.output.appendSlice(self.allocator, ") == null)");
                },
                else => {
                    // String comparison operators other than == and != not supported
                    try genExpr(self, compare.left.*);
                    const op_str = switch (op) {
                        .Lt => " < ",
                        .LtEq => " <= ",
                        .Gt => " > ",
                        .GtEq => " >= ",
                        else => " ? ",
                    };
                    try self.output.appendSlice(self.allocator, op_str);
                    try genExpr(self, compare.comparators[i]);
                },
            }
        }
        // Handle 'in' operator for lists
        else if (op == .In or op == .NotIn) {
            if (right_type == .list) {
                // List membership check: std.mem.indexOfScalar(T, slice, value) != null
                const elem_type = right_type.list.*;
                const type_str = switch (elem_type) {
                    .int => "i64",
                    .float => "f64",
                    .string => "[]const u8",
                    else => "i64", // fallback
                };

                if (op == .In) {
                    try self.output.appendSlice(self.allocator, "(std.mem.indexOfScalar(");
                } else {
                    try self.output.appendSlice(self.allocator, "(std.mem.indexOfScalar(");
                }

                try self.output.appendSlice(self.allocator, type_str);
                try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, compare.comparators[i]); // list/slice
                try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, compare.left.*); // item to search for

                if (op == .In) {
                    try self.output.appendSlice(self.allocator, ") != null)");
                } else {
                    try self.output.appendSlice(self.allocator, ") == null)");
                }
            } else if (right_type == .dict) {
                // Dict key check: dict.contains(key)
                if (op == .In) {
                    try genExpr(self, compare.comparators[i]); // dict
                    try self.output.appendSlice(self.allocator, ".contains(");
                    try genExpr(self, compare.left.*); // key
                    try self.output.appendSlice(self.allocator, ")");
                } else {
                    try self.output.appendSlice(self.allocator, "!");
                    try genExpr(self, compare.comparators[i]); // dict
                    try self.output.appendSlice(self.allocator, ".contains(");
                    try genExpr(self, compare.left.*); // key
                    try self.output.appendSlice(self.allocator, ")");
                }
            } else {
                // Fallback for arrays and unrecognized types
                // Infer element type from the item being searched for

                // String arrays need special handling - can't use indexOfScalar
                // because strings require std.mem.eql for comparison, not ==
                if (left_type == .string) {
                    // Generate inline block expression that loops through array
                    try self.output.appendSlice(self.allocator, "(blk: {\n");
                    try self.output.appendSlice(self.allocator, "for (");
                    try genExpr(self, compare.comparators[i]); // array
                    try self.output.appendSlice(self.allocator, ") |__item| {\n");
                    try self.output.appendSlice(self.allocator, "if (std.mem.eql(u8, __item, ");
                    try genExpr(self, compare.left.*); // search string
                    try self.output.appendSlice(self.allocator, ")) break :blk true;\n");
                    try self.output.appendSlice(self.allocator, "}\n");
                    try self.output.appendSlice(self.allocator, "break :blk false;\n");
                    try self.output.appendSlice(self.allocator, "})");

                    // Handle 'not in' by negating the result
                    if (op == .NotIn) {
                        // Wrap in negation
                        const current = try self.output.toOwnedSlice(self.allocator);
                        try self.output.appendSlice(self.allocator, "!");
                        try self.output.appendSlice(self.allocator, current);
                    }
                } else {
                    // Integer and float arrays use indexOfScalar
                    const elem_type_str = switch (left_type) {
                        .int => "i64",
                        .float => "f64",
                        else => "i64", // Default fallback to i64
                    };

                    if (op == .In) {
                        try self.output.appendSlice(self.allocator, "(std.mem.indexOfScalar(");
                    } else {
                        try self.output.appendSlice(self.allocator, "(std.mem.indexOfScalar(");
                    }
                    try self.output.appendSlice(self.allocator, elem_type_str);
                    try self.output.appendSlice(self.allocator, ", &");
                    try genExpr(self, compare.comparators[i]); // array/container
                    try self.output.appendSlice(self.allocator, ", ");
                    try genExpr(self, compare.left.*); // item to search for
                    if (op == .In) {
                        try self.output.appendSlice(self.allocator, ") != null)");
                    } else {
                        try self.output.appendSlice(self.allocator, ") == null)");
                    }
                }
            }
        } else {
            // Regular comparisons for non-strings
            // Check for type mismatches between usize and i64
            const left_is_usize = (left_type == .usize);
            const left_is_int = (left_type == .int);
            const right_is_usize = (right_type == .usize);
            const right_is_int = (right_type == .int);

            // If mixing usize and i64, cast to i64 for comparison
            const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

            // Cast left operand if needed
            if (left_is_usize and needs_cast) {
                try self.output.appendSlice(self.allocator, "@as(i64, @intCast(");
            }
            try genExpr(self, compare.left.*);
            if (left_is_usize and needs_cast) {
                try self.output.appendSlice(self.allocator, "))");
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
            try self.output.appendSlice(self.allocator, op_str);

            // Cast right operand if needed
            if (right_is_usize and needs_cast) {
                try self.output.appendSlice(self.allocator, "@as(i64, @intCast(");
            }
            try genExpr(self, compare.comparators[i]);
            if (right_is_usize and needs_cast) {
                try self.output.appendSlice(self.allocator, "))");
            }
        }
    }
}

/// Generate boolean operations (and, or)
pub fn genBoolOp(self: *NativeCodegen, boolop: ast.Node.BoolOp) CodegenError!void {
    const op_str = if (boolop.op == .And) " and " else " or ";

    for (boolop.values, 0..) |value, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, op_str);
        try genExpr(self, value);
    }
}
