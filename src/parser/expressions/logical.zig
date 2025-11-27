const std = @import("std");
const ast = @import("ast");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const arithmetic = @import("arithmetic.zig");

/// Parse logical OR expression
pub fn parseOrExpr(self: *Parser) ParseError!ast.Node {
    var left = try parseAndExpr(self);
    errdefer left.deinit(self.allocator);

    while (self.match(.Or)) {
        var right = try parseAndExpr(self);
        errdefer right.deinit(self.allocator);

        // Create BoolOp node
        var values = try self.allocator.alloc(ast.Node, 2);
        values[0] = left;
        values[1] = right;

        left = ast.Node{
            .boolop = .{
                .op = .Or,
                .values = values,
            },
        };
    }

    return left;
}

/// Parse logical AND expression
pub fn parseAndExpr(self: *Parser) ParseError!ast.Node {
    var left = try parseNotExpr(self);
    errdefer left.deinit(self.allocator);

    while (self.match(.And)) {
        var right = try parseNotExpr(self);
        errdefer right.deinit(self.allocator);

        var values = try self.allocator.alloc(ast.Node, 2);
        values[0] = left;
        values[1] = right;

        left = ast.Node{
            .boolop = .{
                .op = .And,
                .values = values,
            },
        };
    }

    return left;
}

/// Parse logical NOT expression
pub fn parseNotExpr(self: *Parser) ParseError!ast.Node {
    if (self.match(.Not)) {
        var operand = try parseNotExpr(self); // Recursive for multiple nots
        errdefer operand.deinit(self.allocator);

        const operand_ptr = try self.allocator.create(ast.Node);
        operand_ptr.* = operand;

        return ast.Node{
            .unaryop = .{
                .op = .Not,
                .operand = operand_ptr,
            },
        };
    }

    return try parseComparison(self);
}

/// Parse comparison operators: ==, !=, <, >, <=, >=, in, not in
pub fn parseComparison(self: *Parser) ParseError!ast.Node {
    var left = try arithmetic.parseBitOr(self);
    errdefer left.deinit(self.allocator);

    // Check for comparison operators
    var ops = std.ArrayList(ast.CompareOp){};
    errdefer ops.deinit(self.allocator);

    var comparators = std.ArrayList(ast.Node){};
    errdefer {
        for (comparators.items) |*c| c.deinit(self.allocator);
        comparators.deinit(self.allocator);
    }

    while (true) {
        var found = false;

        if (self.match(.EqEq)) {
            try ops.append(self.allocator, .Eq);
            found = true;
        } else if (self.match(.NotEq)) {
            try ops.append(self.allocator, .NotEq);
            found = true;
        } else if (self.match(.LtEq)) {
            try ops.append(self.allocator, .LtEq);
            found = true;
        } else if (self.match(.Lt)) {
            try ops.append(self.allocator, .Lt);
            found = true;
        } else if (self.match(.GtEq)) {
            try ops.append(self.allocator, .GtEq);
            found = true;
        } else if (self.match(.Gt)) {
            try ops.append(self.allocator, .Gt);
            found = true;
        } else if (self.match(.In)) {
            try ops.append(self.allocator, .In);
            found = true;
        } else if (self.match(.Not)) {
            // Check for "not in"
            if (self.match(.In)) {
                try ops.append(self.allocator, .NotIn);
                found = true;
            } else {
                // Put back the Not token - it's not part of comparison
                self.current -= 1;
            }
        } else if (self.match(.Is)) {
            // Check for "is not"
            if (self.match(.Not)) {
                try ops.append(self.allocator, .IsNot);
            } else {
                try ops.append(self.allocator, .Is);
            }
            found = true;
        }

        if (!found) break;

        var right = try arithmetic.parseBitOr(self);
        errdefer right.deinit(self.allocator);
        try comparators.append(self.allocator, right);
    }

    if (ops.items.len > 0) {
        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        // Success - transfer ownership
        const final_ops = try ops.toOwnedSlice(self.allocator);
        ops = std.ArrayList(ast.CompareOp){}; // Reset
        const final_comparators = try comparators.toOwnedSlice(self.allocator);
        comparators = std.ArrayList(ast.Node){}; // Reset

        return ast.Node{
            .compare = .{
                .left = left_ptr,
                .ops = final_ops,
                .comparators = final_comparators,
            },
        };
    }

    return left;
}
