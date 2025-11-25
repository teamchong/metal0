const std = @import("std");
const ast = @import("../../ast.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const arithmetic = @import("arithmetic.zig");

/// Parse logical OR expression
pub fn parseOrExpr(self: *Parser) ParseError!ast.Node {
    var left = try parseAndExpr(self);

    while (self.match(.Or)) {
        const right = try parseAndExpr(self);

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

    while (self.match(.And)) {
        const right = try parseNotExpr(self);

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
        const operand = try parseNotExpr(self); // Recursive for multiple nots

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
    const left = try arithmetic.parseBitOr(self);

    // Check for comparison operators
    var ops = std.ArrayList(ast.CompareOp){};
    defer ops.deinit(self.allocator);

    var comparators = std.ArrayList(ast.Node){};
    defer comparators.deinit(self.allocator);

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

        const right = try arithmetic.parseBitOr(self);
        try comparators.append(self.allocator, right);
    }

    if (ops.items.len > 0) {
        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        return ast.Node{
            .compare = .{
                .left = left_ptr,
                .ops = try ops.toOwnedSlice(self.allocator),
                .comparators = try comparators.toOwnedSlice(self.allocator),
            },
        };
    }

    return left;
}
