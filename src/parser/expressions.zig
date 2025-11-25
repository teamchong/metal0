const std = @import("std");
const ast = @import("../ast.zig");
const lexer = @import("../lexer.zig");
const ParseError = @import("../parser.zig").ParseError;
const Parser = @import("../parser.zig").Parser;

/// Parse conditional expression (ternary): value if condition else orelse_value
/// This has the lowest precedence among expressions
pub fn parseConditionalExpr(self: *Parser) ParseError!ast.Node {
    // Check for named expression (walrus operator): identifier :=
    // Must be an identifier followed by :=
    if (self.check(.Ident)) {
        const saved_pos = self.current;
        const ident_tok = self.advance().?;

        if (self.check(.ColonEq)) {
            // It's a named expression
            _ = self.advance(); // consume :=
            const value = try parseConditionalExpr(self); // Parse the value expression

            const target_ptr = try self.allocator.create(ast.Node);
            target_ptr.* = ast.Node{ .name = .{ .id = ident_tok.lexeme } };

            const value_ptr = try self.allocator.create(ast.Node);
            value_ptr.* = value;

            return ast.Node{
                .named_expr = .{
                    .target = target_ptr,
                    .value = value_ptr,
                },
            };
        } else {
            // Not a named expression, restore position
            self.current = saved_pos;
        }
    }

    // Parse the left side (which could be the 'body' of an if_expr)
    const left = try parseOrExpr(self);

    // Check for conditional expression: value if condition else orelse_value
    if (self.match(.If)) {
        const condition = try parseOrExpr(self); // Parse the condition
        _ = try self.expect(.Else); // Expect 'else'
        const orelse_value = try parseConditionalExpr(self); // Right-associative: parse recursively

        const body_ptr = try self.allocator.create(ast.Node);
        body_ptr.* = left;

        const test_ptr = try self.allocator.create(ast.Node);
        test_ptr.* = condition;

        const orelse_ptr = try self.allocator.create(ast.Node);
        orelse_ptr.* = orelse_value;

        return ast.Node{
            .if_expr = .{
                .body = body_ptr,
                .condition = test_ptr,
                .orelse_value = orelse_ptr,
            },
        };
    }

    return left;
}

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
    const left = try parseBitOr(self);

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

        const right = try parseBitOr(self);
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

/// Parse bitwise OR expression
pub fn parseBitOr(self: *Parser) ParseError!ast.Node {
    var left = try parseBitXor(self);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Pipe)) {
            op = .BitOr;
        }

        if (op == null) break;

        const right = try parseBitXor(self);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse bitwise XOR expression
pub fn parseBitXor(self: *Parser) ParseError!ast.Node {
    var left = try parseBitAnd(self);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Caret)) {
            op = .BitXor;
        }

        if (op == null) break;

        const right = try parseBitAnd(self);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse bitwise shift operators: << and >>
pub fn parseShift(self: *Parser) ParseError!ast.Node {
    var left = try parseAddSub(self);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.LtLt)) {
            op = .LShift;
        } else if (self.match(.GtGt)) {
            op = .RShift;
        }

        if (op == null) break;

        const right = try parseAddSub(self);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse bitwise AND expression
pub fn parseBitAnd(self: *Parser) ParseError!ast.Node {
    var left = try parseShift(self);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Ampersand)) {
            op = .BitAnd;
        }

        if (op == null) break;

        const right = try parseShift(self);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse addition and subtraction
pub fn parseAddSub(self: *Parser) ParseError!ast.Node {
    var left = try parseMulDiv(self);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Plus)) {
            op = .Add;
        } else if (self.match(.Minus)) {
            op = .Sub;
        }

        if (op == null) break;

        const right = try parseMulDiv(self);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse multiplication, division, floor division, and modulo
pub fn parseMulDiv(self: *Parser) ParseError!ast.Node {
    var left = try parsePower(self);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Star)) {
            op = .Mult;
        } else if (self.match(.Slash)) {
            op = .Div;
        } else if (self.match(.DoubleSlash)) {
            op = .FloorDiv;
        } else if (self.match(.Percent)) {
            op = .Mod;
        }

        if (op == null) break;

        const right = try parsePower(self);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse power (exponentiation) - right associative
pub fn parsePower(self: *Parser) ParseError!ast.Node {
    const left = try self.parsePostfix();

    if (self.match(.DoubleStar)) {
        const right = try parsePower(self); // Right associative

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        return ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = .Pow,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse lambda expression: lambda x, y: x + y
pub fn parseLambda(self: *Parser) ParseError!ast.Node {
    // Consume 'lambda' keyword
    _ = try self.expect(.Lambda);

    // Parse parameters (comma-separated until ':')
    var args = std.ArrayList(ast.Arg){};

    // Lambda can have zero parameters: lambda: 5
    if (!self.check(.Colon)) {
        while (true) {
            if (self.peek()) |tok| {
                if (tok.type == .Ident) {
                    const param_name = self.advance().?.lexeme;

                    // Parse default value if present (e.g., = 0.1)
                    var default_value: ?*ast.Node = null;
                    if (self.match(.Eq)) {
                        const default_expr = try parseOrExpr(self);
                        const default_ptr = try self.allocator.create(ast.Node);
                        default_ptr.* = default_expr;
                        default_value = default_ptr;
                    }

                    try args.append(self.allocator, .{
                        .name = param_name,
                        .type_annotation = null,
                        .default = default_value,
                    });

                    if (self.match(.Comma)) {
                        continue;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            } else {
                return error.UnexpectedEof;
            }
        }
    }

    // Consume ':' separator
    _ = try self.expect(.Colon);

    // Parse body (single expression)
    const body_expr = try parseOrExpr(self);
    const body_ptr = try self.allocator.create(ast.Node);
    body_ptr.* = body_expr;

    return ast.Node{
        .lambda = .{
            .args = try args.toOwnedSlice(self.allocator),
            .body = body_ptr,
        },
    };
}
