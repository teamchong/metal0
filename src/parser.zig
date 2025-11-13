const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");

pub const ParseError = error{
    UnexpectedEof,
    UnexpectedToken,
    UnexpectedCharacter,
    OutOfMemory,
    InvalidCharacter,
    Overflow,
};

pub const Parser = struct {
    tokens: []const lexer.Token,
    current: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []const lexer.Token) Parser {
        return Parser{
            .tokens = tokens,
            .current = 0,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) ParseError!ast.Node {
        var statements = std.ArrayList(ast.Node){};
        defer statements.deinit(self.allocator);

        // Skip leading newlines
        while (self.match(.Newline)) {}

        while (!self.isAtEnd()) {
            if (self.match(.Newline)) continue;
            const stmt = try self.parseStatement();
            try statements.append(self.allocator, stmt);
        }

        return ast.Node{
            .module = .{
                .body = try statements.toOwnedSlice(self.allocator),
            },
        };
    }

    // ===== Utility Methods =====

    fn peek(self: *Parser) ?lexer.Token {
        if (self.current >= self.tokens.len) return null;
        return self.tokens[self.current];
    }

    fn peekType(self: *Parser) ?lexer.TokenType {
        if (self.peek()) |tok| return tok.type;
        return null;
    }

    fn advance(self: *Parser) ?lexer.Token {
        if (self.current >= self.tokens.len) return null;
        const tok = self.tokens[self.current];
        self.current += 1;
        return tok;
    }

    fn expect(self: *Parser, token_type: lexer.TokenType) !lexer.Token {
        const tok = self.peek() orelse return error.UnexpectedEof;
        if (tok.type != token_type) {
            std.debug.print("Expected {s}, got {s} at line {d}:{d}\n", .{
                @tagName(token_type),
                @tagName(tok.type),
                tok.line,
                tok.column,
            });
            return error.UnexpectedToken;
        }
        return self.advance().?;
    }

    fn match(self: *Parser, token_type: lexer.TokenType) bool {
        if (self.peek()) |tok| {
            if (tok.type == token_type) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    fn matchAny(self: *Parser, types: []const lexer.TokenType) bool {
        for (types) |t| {
            if (self.match(t)) return true;
        }
        return false;
    }

    fn isAtEnd(self: *Parser) bool {
        if (self.peek()) |tok| {
            return tok.type == .Eof;
        }
        return true;
    }

    fn skipNewlines(self: *Parser) void {
        while (self.match(.Newline)) {}
    }

    // ===== Statement Parsing =====

    fn parseStatement(self: *Parser) ParseError!ast.Node {
        // Try to determine statement type
        if (self.peek()) |tok| {
            switch (tok.type) {
                .Def => return try self.parseFunctionDef(),
                .Class => return try self.parseClassDef(),
                .If => return try self.parseIf(),
                .For => return try self.parseFor(),
                .While => return try self.parseWhile(),
                .Return => return try self.parseReturn(),
                else => {
                    // Could be assignment or expression statement
                    return try self.parseExprOrAssign();
                },
            }
        }
        return error.UnexpectedEof;
    }

    fn parseExprOrAssign(self: *Parser) ParseError!ast.Node {
        const expr = try self.parseExpression();

        // Check for assignment
        if (self.match(.Eq)) {
            const value = try self.parseExpression();
            _ = self.expect(.Newline) catch {};

            // Allocate nodes on heap
            const value_ptr = try self.allocator.create(ast.Node);
            value_ptr.* = value;

            // For simplicity, wrap expr in array (single target)
            var targets = try self.allocator.alloc(ast.Node, 1);
            targets[0] = expr;

            return ast.Node{
                .assign = .{
                    .targets = targets,
                    .value = value_ptr,
                },
            };
        }

        // Expression statement
        _ = self.expect(.Newline) catch {};

        const expr_ptr = try self.allocator.create(ast.Node);
        expr_ptr.* = expr;

        return ast.Node{
            .expr_stmt = .{
                .value = expr_ptr,
            },
        };
    }

    fn parseFunctionDef(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Def);
        const name_tok = try self.expect(.Ident);
        _ = try self.expect(.LParen);

        var args = std.ArrayList(ast.Arg){};
        defer args.deinit(self.allocator);

        while (!self.match(.RParen)) {
            const arg_name = try self.expect(.Ident);

            // Skip type annotation if present (e.g., : int)
            if (self.match(.Colon)) {
                // Skip the type - just consume tokens until comma or rparen
                while (self.current < self.tokens.len and
                    self.tokens[self.current].type != .Comma and
                    self.tokens[self.current].type != .RParen)
                {
                    self.current += 1;
                }
            }

            try args.append(self.allocator, .{
                .name = arg_name.lexeme,
                .type_annotation = null,
            });

            if (!self.match(.Comma)) {
                _ = try self.expect(.RParen);
                break;
            }
        }

        // Skip return type annotation if present (e.g., -> int)
        if (self.tokens[self.current].type == .Arrow or
            (self.tokens[self.current].type == .Minus and
                self.current + 1 < self.tokens.len and
                self.tokens[self.current + 1].type == .Gt))
        {
            // Skip -> or - >
            if (self.match(.Arrow)) {
                // Single arrow token
            } else {
                _ = self.match(.Minus);
                _ = self.match(.Gt);
            }
            // Skip the return type
            while (self.current < self.tokens.len and
                self.tokens[self.current].type != .Colon)
            {
                self.current += 1;
            }
        }

        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const body = try self.parseBlock();

        _ = try self.expect(.Dedent);

        return ast.Node{
            .function_def = .{
                .name = name_tok.lexeme,
                .args = try args.toOwnedSlice(self.allocator),
                .body = body,
            },
        };
    }

    fn parseClassDef(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Class);
        const name_tok = try self.expect(.Ident);
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const body = try self.parseBlock();

        _ = try self.expect(.Dedent);

        return ast.Node{
            .class_def = .{
                .name = name_tok.lexeme,
                .body = body,
            },
        };
    }

    fn parseIf(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.If);
        const condition_expr = try self.parseExpression();
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const if_body = try self.parseBlock();

        _ = try self.expect(.Dedent);

        // Allocate condition on heap
        const condition_ptr = try self.allocator.create(ast.Node);
        condition_ptr.* = condition_expr;

        // Check for elif/else
        var else_stmts = std.ArrayList(ast.Node){};
        defer else_stmts.deinit(self.allocator);

        while (self.match(.Elif)) {
            const elif_condition = try self.parseExpression();
            _ = try self.expect(.Colon);
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);

            const elif_body = try self.parseBlock();

            _ = try self.expect(.Dedent);

            const elif_condition_ptr = try self.allocator.create(ast.Node);
            elif_condition_ptr.* = elif_condition;

            try else_stmts.append(self.allocator, ast.Node{
                .if_stmt = .{
                    .condition = elif_condition_ptr,
                    .body = elif_body,
                    .else_body = &[_]ast.Node{},
                },
            });
        }

        if (self.match(.Else)) {
            _ = try self.expect(.Colon);
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);

            const else_body = try self.parseBlock();

            _ = try self.expect(.Dedent);

            for (else_body) |stmt| {
                try else_stmts.append(self.allocator, stmt);
            }
        }

        return ast.Node{
            .if_stmt = .{
                .condition = condition_ptr,
                .body = if_body,
                .else_body = try else_stmts.toOwnedSlice(self.allocator),
            },
        };
    }

    fn parseFor(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.For);

        // Parse target (can be single var or tuple like: i, x)
        var targets = std.ArrayList(ast.Node){};
        defer targets.deinit(self.allocator);

        try targets.append(self.allocator, try self.parsePrimary());

        // Check for comma-separated targets (tuple unpacking)
        while (self.match(.Comma)) {
            try targets.append(self.allocator, try self.parsePrimary());
        }

        _ = try self.expect(.In);
        const iter = try self.parseExpression();
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const body = try self.parseBlock();

        _ = try self.expect(.Dedent);

        const target_ptr = try self.allocator.create(ast.Node);
        if (targets.items.len == 1) {
            // Single target
            target_ptr.* = targets.items[0];
        } else {
            // Multiple targets (tuple unpacking) - use list node
            target_ptr.* = ast.Node{
                .list = .{
                    .elts = try targets.toOwnedSlice(self.allocator),
                },
            };
        }

        const iter_ptr = try self.allocator.create(ast.Node);
        iter_ptr.* = iter;

        return ast.Node{
            .for_stmt = .{
                .target = target_ptr,
                .iter = iter_ptr,
                .body = body,
            },
        };
    }

    fn parseWhile(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.While);
        const condition_expr = try self.parseExpression();
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const body = try self.parseBlock();

        _ = try self.expect(.Dedent);

        const condition_ptr = try self.allocator.create(ast.Node);
        condition_ptr.* = condition_expr;

        return ast.Node{
            .while_stmt = .{
                .condition = condition_ptr,
                .body = body,
            },
        };
    }

    fn parseReturn(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Return);

        var value_ptr: ?*ast.Node = null;

        // Check if there's a return value
        if (self.peek()) |tok| {
            if (tok.type != .Newline) {
                const value = try self.parseExpression();
                value_ptr = try self.allocator.create(ast.Node);
                value_ptr.?.* = value;
            }
        }

        _ = self.expect(.Newline) catch {};

        return ast.Node{
            .return_stmt = .{
                .value = value_ptr,
            },
        };
    }

    fn parseBlock(self: *Parser) ParseError![]ast.Node {
        var statements = std.ArrayList(ast.Node){};
        defer statements.deinit(self.allocator);

        while (true) {
            if (self.peek()) |tok| {
                if (tok.type == .Dedent or tok.type == .Eof) break;
            } else break;

            if (self.match(.Newline)) continue;

            const stmt = try self.parseStatement();
            try statements.append(self.allocator, stmt);
        }

        return try statements.toOwnedSlice(self.allocator);
    }

    // ===== Expression Parsing =====

    fn parseExpression(self: *Parser) ParseError!ast.Node {
        return try self.parseOrExpr();
    }

    fn parseOrExpr(self: *Parser) ParseError!ast.Node {
        var left = try self.parseAndExpr();

        while (self.match(.Or)) {
            const right = try self.parseAndExpr();

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

    fn parseAndExpr(self: *Parser) ParseError!ast.Node {
        var left = try self.parseNotExpr();

        while (self.match(.And)) {
            const right = try self.parseNotExpr();

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

    fn parseNotExpr(self: *Parser) ParseError!ast.Node {
        if (self.match(.Not)) {
            const operand = try self.parseNotExpr(); // Recursive for multiple nots

            const operand_ptr = try self.allocator.create(ast.Node);
            operand_ptr.* = operand;

            return ast.Node{
                .unaryop = .{
                    .op = .Not,
                    .operand = operand_ptr,
                },
            };
        }

        return try self.parseComparison();
    }

    fn parseComparison(self: *Parser) ParseError!ast.Node {
        const left = try self.parseBitOr();

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
            }

            if (!found) break;

            const right = try self.parseBitOr();
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

    fn parseBitOr(self: *Parser) ParseError!ast.Node {
        var left = try self.parseBitXor();

        while (true) {
            var op: ?ast.Operator = null;

            if (self.match(.Pipe)) {
                op = .BitOr;
            }

            if (op == null) break;

            const right = try self.parseBitXor();

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

    fn parseBitXor(self: *Parser) ParseError!ast.Node {
        var left = try self.parseBitAnd();

        while (true) {
            var op: ?ast.Operator = null;

            if (self.match(.Caret)) {
                op = .BitXor;
            }

            if (op == null) break;

            const right = try self.parseBitAnd();

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

    fn parseBitAnd(self: *Parser) ParseError!ast.Node {
        var left = try self.parseAddSub();

        while (true) {
            var op: ?ast.Operator = null;

            if (self.match(.Ampersand)) {
                op = .BitAnd;
            }

            if (op == null) break;

            const right = try self.parseAddSub();

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

    fn parseAddSub(self: *Parser) ParseError!ast.Node {
        var left = try self.parseMulDiv();

        while (true) {
            var op: ?ast.Operator = null;

            if (self.match(.Plus)) {
                op = .Add;
            } else if (self.match(.Minus)) {
                op = .Sub;
            }

            if (op == null) break;

            const right = try self.parseMulDiv();

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

    fn parseMulDiv(self: *Parser) ParseError!ast.Node {
        var left = try self.parsePower();

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

            const right = try self.parsePower();

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

    fn parsePower(self: *Parser) ParseError!ast.Node {
        const left = try self.parsePostfix();

        if (self.match(.DoubleStar)) {
            const right = try self.parsePower(); // Right associative

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

    fn parsePostfix(self: *Parser) ParseError!ast.Node {
        var node = try self.parsePrimary();

        while (true) {
            if (self.match(.LParen)) {
                // Function call
                node = try self.parseCall(node);
            } else if (self.match(.LBracket)) {
                // Subscript
                const index = try self.parseExpression();
                _ = try self.expect(.RBracket);

                const node_ptr = try self.allocator.create(ast.Node);
                node_ptr.* = node;

                const index_ptr = try self.allocator.create(ast.Node);
                index_ptr.* = index;

                node = ast.Node{
                    .subscript = .{
                        .value = node_ptr,
                        .slice = index_ptr,
                    },
                };
            } else if (self.match(.Dot)) {
                // Attribute access
                const attr_tok = try self.expect(.Ident);

                const node_ptr = try self.allocator.create(ast.Node);
                node_ptr.* = node;

                node = ast.Node{
                    .attribute = .{
                        .value = node_ptr,
                        .attr = attr_tok.lexeme,
                    },
                };
            } else {
                break;
            }
        }

        return node;
    }

    fn parseCall(self: *Parser, func: ast.Node) !ast.Node {
        var args = std.ArrayList(ast.Node){};
        defer args.deinit(self.allocator);

        while (!self.match(.RParen)) {
            const arg = try self.parseExpression();
            try args.append(self.allocator, arg);

            if (!self.match(.Comma)) {
                _ = try self.expect(.RParen);
                break;
            }
        }

        const func_ptr = try self.allocator.create(ast.Node);
        func_ptr.* = func;

        return ast.Node{
            .call = .{
                .func = func_ptr,
                .args = try args.toOwnedSlice(self.allocator),
            },
        };
    }

    fn parsePrimary(self: *Parser) ParseError!ast.Node {
        if (self.peek()) |tok| {
            switch (tok.type) {
                .Number => {
                    const num_tok = self.advance().?;
                    // Try to parse as int, fall back to float
                    if (std.fmt.parseInt(i64, num_tok.lexeme, 10)) |int_val| {
                        return ast.Node{
                            .constant = .{
                                .value = .{ .int = int_val },
                            },
                        };
                    } else |_| {
                        const float_val = try std.fmt.parseFloat(f64, num_tok.lexeme);
                        return ast.Node{
                            .constant = .{
                                .value = .{ .float = float_val },
                            },
                        };
                    }
                },
                .String => {
                    const str_tok = self.advance().?;
                    return ast.Node{
                        .constant = .{
                            .value = .{ .string = str_tok.lexeme },
                        },
                    };
                },
                .True => {
                    _ = self.advance();
                    return ast.Node{
                        .constant = .{
                            .value = .{ .bool = true },
                        },
                    };
                },
                .False => {
                    _ = self.advance();
                    return ast.Node{
                        .constant = .{
                            .value = .{ .bool = false },
                        },
                    };
                },
                .None => {
                    _ = self.advance();
                    // Represent None as a special constant
                    return ast.Node{
                        .constant = .{
                            .value = .{ .int = 0 }, // Placeholder
                        },
                    };
                },
                .Ident => {
                    const ident_tok = self.advance().?;
                    return ast.Node{
                        .name = .{
                            .id = ident_tok.lexeme,
                        },
                    };
                },
                .LParen => {
                    _ = self.advance();
                    const expr = try self.parseExpression();
                    _ = try self.expect(.RParen);
                    return expr;
                },
                .LBracket => {
                    return try self.parseList();
                },
                .Minus => {
                    // Unary minus (e.g., -10)
                    _ = self.advance();
                    const operand_ptr = try self.allocator.create(ast.Node);
                    operand_ptr.* = try self.parsePrimary();
                    return ast.Node{
                        .unaryop = .{
                            .op = .USub,
                            .operand = operand_ptr,
                        },
                    };
                },
                .Plus => {
                    // Unary plus (e.g., +10)
                    _ = self.advance();
                    const operand_ptr = try self.allocator.create(ast.Node);
                    operand_ptr.* = try self.parsePrimary();
                    return ast.Node{
                        .unaryop = .{
                            .op = .UAdd,
                            .operand = operand_ptr,
                        },
                    };
                },
                else => {
                    std.debug.print("Unexpected token in primary: {s} at line {d}:{d}\n", .{
                        @tagName(tok.type),
                        tok.line,
                        tok.column,
                    });
                    return error.UnexpectedToken;
                },
            }
        }

        return error.UnexpectedEof;
    }

    fn parseList(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.LBracket);

        var elts = std.ArrayList(ast.Node){};
        defer elts.deinit(self.allocator);

        while (!self.match(.RBracket)) {
            const elt = try self.parseExpression();
            try elts.append(self.allocator, elt);

            if (!self.match(.Comma)) {
                _ = try self.expect(.RBracket);
                break;
            }
        }

        return ast.Node{
            .list = .{
                .elts = try elts.toOwnedSlice(self.allocator),
            },
        };
    }
};
