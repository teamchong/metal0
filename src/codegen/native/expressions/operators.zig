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

    try self.output.appendSlice(self.allocator, "(");
    try genExpr(self, binop.left.*);

    const op_str = switch (binop.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .Div => " / ",
        .FloorDiv => " / ", // Zig doesn't distinguish
        else => " ? ",
    };
    try self.output.appendSlice(self.allocator, op_str);

    try genExpr(self, binop.right.*);
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
    try genExpr(self, unaryop.operand.*);
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
        } else {
            // Regular comparisons for non-strings
            try genExpr(self, compare.left.*);
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
            try genExpr(self, compare.comparators[i]);
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
