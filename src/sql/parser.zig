//! SQL Parser - Recursive Descent Parser
//!
//! Converts tokens from the lexer into an Abstract Syntax Tree (AST).
//! Supports SQLite-style SQL with ? parameter placeholders.

const std = @import("std");
const lexer = @import("lexer");
const ast = @import("ast");

const Token = lexer.Token;
const TokenType = lexer.TokenType;
const Expr = ast.Expr;
const SelectStmt = ast.SelectStmt;
const Statement = ast.Statement;

/// SQL Parser
pub const Parser = struct {
    tokens: []const Token,
    position: usize,
    allocator: std.mem.Allocator,
    param_count: u32, // Track parameter count for ?

    const Self = @This();

    pub fn init(tokens: []const Token, allocator: std.mem.Allocator) Self {
        return Self{
            .tokens = tokens,
            .position = 0,
            .allocator = allocator,
            .param_count = 0,
        };
    }

    /// Get current token
    fn current(self: *const Self) ?Token {
        if (self.position >= self.tokens.len) return null;
        return self.tokens[self.position];
    }

    /// Advance to next token
    fn advance(self: *Self) void {
        if (self.position < self.tokens.len) {
            self.position += 1;
        }
    }

    /// Check if current token matches type
    fn check(self: *const Self, token_type: TokenType) bool {
        const tok = self.current() orelse return false;
        return tok.type == token_type;
    }

    /// Consume token if it matches, otherwise error
    fn expect(self: *Self, token_type: TokenType) !Token {
        const tok = self.current() orelse return error.UnexpectedEOF;
        if (tok.type != token_type) {
            return error.UnexpectedToken;
        }
        self.advance();
        return tok;
    }

    /// Check if current token matches any of the given types
    fn match(self: *Self, types: []const TokenType) bool {
        for (types) |t| {
            if (self.check(t)) {
                self.advance();
                return true;
            }
        }
        return false;
    }

    // ========================================================================
    // Top-level parsing
    // ========================================================================

    /// Parse a complete SQL statement
    pub fn parseStatement(self: *Self) !Statement {
        const tok = self.current() orelse return error.EmptyStatement;

        return switch (tok.type) {
            .SELECT => Statement{ .select = try self.parseSelect() },
            .WITH => Statement{ .select = try self.parseWithSelect() },
            else => error.UnsupportedStatement,
        };
    }

    /// Parse WITH DATA ... SELECT statement
    fn parseWithSelect(self: *Self) !SelectStmt {
        _ = try self.expect(.WITH);
        _ = try self.expect(.DATA);

        // Parse data bindings: (name = 'path', ...)
        _ = try self.expect(.LPAREN);

        var bindings = std.ArrayList(ast.DataBinding){};
        errdefer bindings.deinit(self.allocator);

        while (true) {
            // Parse: name = 'path'
            const name_tok = try self.expect(.IDENTIFIER);
            _ = try self.expect(.EQ);
            const path_tok = try self.expect(.STRING);

            // Remove quotes from path
            const path = if (path_tok.lexeme.len >= 2)
                path_tok.lexeme[1 .. path_tok.lexeme.len - 1]
            else
                path_tok.lexeme;

            try bindings.append(self.allocator, ast.DataBinding{
                .name = name_tok.lexeme,
                .path = path,
            });

            if (!self.match(&[_]TokenType{.COMMA})) break;
        }

        _ = try self.expect(.RPAREN);

        // Now parse the SELECT
        var stmt = try self.parseSelect();
        stmt.with_data = ast.WithData{
            .bindings = try bindings.toOwnedSlice(self.allocator),
        };

        return stmt;
    }

    /// Parse SELECT statement
    fn parseSelect(self: *Self) !SelectStmt {
        _ = try self.expect(.SELECT);

        // DISTINCT clause
        const distinct = self.match(&[_]TokenType{.DISTINCT});

        // SELECT columns
        const columns = try self.parseSelectList();

        // FROM clause
        _ = try self.expect(.FROM);
        const from = try self.parseTableRef();

        // WHERE clause (optional)
        const where_clause = if (self.match(&[_]TokenType{.WHERE}))
            try self.parseExpr()
        else
            null;

        // GROUP BY clause (optional)
        const group_by = if (self.match(&[_]TokenType{.GROUP}))
            try self.parseGroupBy()
        else
            null;

        // ORDER BY clause (optional)
        const order_by = if (self.match(&[_]TokenType{.ORDER}))
            try self.parseOrderBy()
        else
            null;

        // LIMIT clause (optional)
        const limit = if (self.match(&[_]TokenType{.LIMIT}))
            try self.parseLimitValue()
        else
            null;

        // OFFSET clause (optional)
        const offset = if (self.match(&[_]TokenType{.OFFSET}))
            try self.parseLimitValue()
        else
            null;

        // Set operation (UNION/INTERSECT/EXCEPT) - optional
        const set_operation = try self.parseSetOperation();

        return SelectStmt{
            .with_data = null,
            .distinct = distinct,
            .columns = columns,
            .from = from,
            .where = where_clause,
            .group_by = group_by,
            .order_by = order_by,
            .limit = limit,
            .offset = offset,
            .set_operation = set_operation,
        };
    }

    /// Parse set operation (UNION/INTERSECT/EXCEPT) if present
    fn parseSetOperation(self: *Self) anyerror!?ast.SetOperation {
        // Check for set operation keywords
        var op_type: ?ast.SetOperationType = null;

        if (self.match(&[_]TokenType{.UNION})) {
            // Check for ALL keyword
            if (self.match(&[_]TokenType{.ALL})) {
                op_type = .union_all;
            } else {
                op_type = .union_distinct;
            }
        } else if (self.match(&[_]TokenType{.INTERSECT})) {
            op_type = .intersect;
        } else if (self.match(&[_]TokenType{.EXCEPT})) {
            op_type = .except;
        }

        if (op_type) |ot| {
            // Parse the right-hand SELECT statement
            const right = try self.allocator.create(SelectStmt);
            right.* = try self.parseSelect();

            return ast.SetOperation{
                .op_type = ot,
                .right = right,
            };
        }

        return null;
    }

    // ========================================================================
    // SELECT list parsing
    // ========================================================================

    fn parseSelectList(self: *Self) ![]ast.SelectItem {
        var items = std.ArrayList(ast.SelectItem){};
        errdefer items.deinit(self.allocator);

        while (true) {
            try items.append(self.allocator, try self.parseSelectItem());

            if (!self.match(&[_]TokenType{.COMMA})) break;
        }

        return items.toOwnedSlice(self.allocator);
    }

    fn parseSelectItem(self: *Self) !ast.SelectItem {
        // Special case for SELECT *
        if (self.check(.STAR)) {
            self.advance();
            return ast.SelectItem{
                .expr = Expr{
                    .column = .{
                        .table = null,
                        .name = "*",
                    },
                },
                .alias = null,
            };
        }

        const expr = try self.parseExpr();

        // Check for AS alias
        const alias = if (self.match(&[_]TokenType{.AS})) blk: {
            const tok = try self.expect(.IDENTIFIER);
            break :blk tok.lexeme;
        } else null;

        return ast.SelectItem{
            .expr = expr,
            .alias = alias,
        };
    }

    // ========================================================================
    // Expression parsing (operator precedence)
    // ========================================================================

    fn parseExpr(self: *Self) anyerror!Expr {
        return try self.parseOrExpr();
    }

    fn parseOrExpr(self: *Self) anyerror!Expr {
        var left = try self.parseAndExpr();

        while (self.match(&[_]TokenType{.OR})) {
            const right_ptr = try self.allocator.create(Expr);
            right_ptr.* = try self.parseAndExpr();

            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;

            left = Expr{
                .binary = .{
                    .op = .@"or",
                    .left = left_ptr,
                    .right = right_ptr,
                },
            };
        }

        return left;
    }

    fn parseAndExpr(self: *Self) anyerror!Expr {
        var left = try self.parseComparisonExpr();

        while (self.match(&[_]TokenType{.AND})) {
            const right_ptr = try self.allocator.create(Expr);
            right_ptr.* = try self.parseComparisonExpr();

            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;

            left = Expr{
                .binary = .{
                    .op = .@"and",
                    .left = left_ptr,
                    .right = right_ptr,
                },
            };
        }

        return left;
    }

    fn parseComparisonExpr(self: *Self) anyerror!Expr {
        const left = try self.parseAddExpr();

        // Comparison operators
        if (self.match(&[_]TokenType{.EQ})) {
            const right_ptr = try self.allocator.create(Expr);
            right_ptr.* = try self.parseAddExpr();
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;
            return Expr{ .binary = .{ .op = .eq, .left = left_ptr, .right = right_ptr } };
        } else if (self.match(&[_]TokenType{.NE})) {
            const right_ptr = try self.allocator.create(Expr);
            right_ptr.* = try self.parseAddExpr();
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;
            return Expr{ .binary = .{ .op = .ne, .left = left_ptr, .right = right_ptr } };
        } else if (self.match(&[_]TokenType{.LT})) {
            const right_ptr = try self.allocator.create(Expr);
            right_ptr.* = try self.parseAddExpr();
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;
            return Expr{ .binary = .{ .op = .lt, .left = left_ptr, .right = right_ptr } };
        } else if (self.match(&[_]TokenType{.LE})) {
            const right_ptr = try self.allocator.create(Expr);
            right_ptr.* = try self.parseAddExpr();
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;
            return Expr{ .binary = .{ .op = .le, .left = left_ptr, .right = right_ptr } };
        } else if (self.match(&[_]TokenType{.GT})) {
            const right_ptr = try self.allocator.create(Expr);
            right_ptr.* = try self.parseAddExpr();
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;
            return Expr{ .binary = .{ .op = .gt, .left = left_ptr, .right = right_ptr } };
        } else if (self.match(&[_]TokenType{.GE})) {
            const right_ptr = try self.allocator.create(Expr);
            right_ptr.* = try self.parseAddExpr();
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;
            return Expr{ .binary = .{ .op = .ge, .left = left_ptr, .right = right_ptr } };
        }

        // Check for [NOT] IN or [NOT] EXISTS
        const negated = self.match(&[_]TokenType{.NOT});
        if (self.match(&[_]TokenType{.IN})) {
            // Expect opening parenthesis
            if (!self.match(&[_]TokenType{.LPAREN})) {
                return error.ExpectedOpenParen;
            }

            // Create left expression pointer
            const left_ptr = try self.allocator.create(Expr);
            errdefer self.allocator.destroy(left_ptr);
            left_ptr.* = left;

            // Check if it's a subquery (SELECT) or a value list
            if (self.check(.SELECT)) {
                // IN (SELECT ...) - subquery
                const subquery = try self.allocator.create(ast.SelectStmt);
                errdefer self.allocator.destroy(subquery);
                subquery.* = try self.parseSelect();

                // Expect closing parenthesis
                if (!self.match(&[_]TokenType{.RPAREN})) {
                    return error.ExpectedCloseParen;
                }

                return Expr{
                    .in_subquery = .{
                        .expr = left_ptr,
                        .subquery = subquery,
                        .negated = negated,
                    },
                };
            } else {
                // IN (val1, val2, ...) - value list
                var values = std.ArrayList(Expr){};
                errdefer values.deinit(self.allocator);

                // Parse first value
                try values.append(self.allocator, try self.parseExpr());

                // Parse additional values
                while (self.match(&[_]TokenType{.COMMA})) {
                    try values.append(self.allocator, try self.parseExpr());
                }

                // Expect closing parenthesis
                if (!self.match(&[_]TokenType{.RPAREN})) {
                    return error.ExpectedCloseParen;
                }

                return Expr{
                    .in_list = .{
                        .expr = left_ptr,
                        .values = try values.toOwnedSlice(self.allocator),
                        .negated = negated,
                    },
                };
            }
        } else if (negated) {
            // Had NOT but no IN - this is an error (NOT EXISTS is handled in parsePrimary)
            return error.ExpectedIN;
        }

        return left;
    }

    fn parseAddExpr(self: *Self) anyerror!Expr {
        var left = try self.parseMulExpr();

        while (true) {
            if (self.match(&[_]TokenType{.PLUS})) {
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = try self.parseMulExpr();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                left = Expr{ .binary = .{ .op = .add, .left = left_ptr, .right = right_ptr } };
            } else if (self.match(&[_]TokenType{.MINUS})) {
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = try self.parseMulExpr();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                left = Expr{ .binary = .{ .op = .subtract, .left = left_ptr, .right = right_ptr } };
            } else if (self.match(&[_]TokenType{.CONCAT})) {
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = try self.parseMulExpr();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                left = Expr{ .binary = .{ .op = .concat, .left = left_ptr, .right = right_ptr } };
            } else {
                break;
            }
        }

        return left;
    }

    fn parseMulExpr(self: *Self) anyerror!Expr {
        var left = try self.parsePrimary();

        while (true) {
            if (self.match(&[_]TokenType{.STAR})) {
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = try self.parsePrimary();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                left = Expr{ .binary = .{ .op = .multiply, .left = left_ptr, .right = right_ptr } };
            } else if (self.match(&[_]TokenType{.SLASH})) {
                const right_ptr = try self.allocator.create(Expr);
                right_ptr.* = try self.parsePrimary();
                const left_ptr = try self.allocator.create(Expr);
                left_ptr.* = left;
                left = Expr{ .binary = .{ .op = .divide, .left = left_ptr, .right = right_ptr } };
            } else {
                break;
            }
        }

        return left;
    }

    fn parsePrimary(self: *Self) anyerror!Expr {
        const tok = self.current() orelse return error.UnexpectedEOF;

        switch (tok.type) {
            // Numbers
            .NUMBER => {
                self.advance();
                // Try parsing as integer first
                const value = std.fmt.parseInt(i64, tok.lexeme, 10) catch |err| {
                    if (err == error.InvalidCharacter) {
                        // Parse as float
                        const f = try std.fmt.parseFloat(f64, tok.lexeme);
                        return Expr{ .value = ast.Value{ .float = f } };
                    }
                    return err;
                };
                return Expr{ .value = ast.Value{ .integer = value } };
            },

            // Strings
            .STRING => {
                self.advance();
                // Remove quotes
                const unquoted = tok.lexeme[1 .. tok.lexeme.len - 1];
                return Expr{ .value = ast.Value{ .string = unquoted } };
            },

            // Parameters (?)
            .PARAMETER => {
                self.advance();
                const param_idx = self.param_count;
                self.param_count += 1;
                return Expr{ .value = ast.Value{ .parameter = param_idx } };
            },

            // Identifiers (columns, function calls, or method calls)
            .IDENTIFIER => {
                const name = tok.lexeme;
                self.advance();

                // Check for function call
                if (self.check(.LPAREN)) {
                    return try self.parseFunctionCall(name);
                }

                // Check for method call or qualified column: name.something
                if (self.check(.DOT)) {
                    self.advance(); // consume DOT
                    const member_tok = try self.expect(.IDENTIFIER);
                    const member_name = member_tok.lexeme;

                    // Check if it's a method call: name.member()
                    if (self.check(.LPAREN)) {
                        return try self.parseMethodCall(name, member_name);
                    }

                    // Otherwise it's a qualified column reference: table.column
                    return Expr{
                        .column = .{
                            .table = name,
                            .name = member_name,
                        },
                    };
                }

                // Simple column reference
                return Expr{
                    .column = .{
                        .table = null,
                        .name = name,
                    },
                };
            },

            // Aggregate function keywords (COUNT, SUM, AVG, MIN, MAX)
            .COUNT, .SUM, .AVG, .MIN, .MAX => {
                const name = tok.lexeme;
                self.advance();
                return try self.parseFunctionCall(name);
            },

            // Parenthesized expression
            .LPAREN => {
                self.advance();
                const expr = try self.parseExpr();
                _ = try self.expect(.RPAREN);
                return expr;
            },

            // CASE expression
            .CASE => {
                return try self.parseCaseExpr();
            },

            // CAST expression
            .CAST => {
                return try self.parseCastExpr();
            },

            // EXISTS expression
            .EXISTS => {
                self.advance();
                _ = try self.expect(.LPAREN);
                // Parse subquery (SELECT statement)
                const subquery = try self.allocator.create(ast.SelectStmt);
                subquery.* = try self.parseSelect();
                _ = try self.expect(.RPAREN);
                return Expr{
                    .exists = .{
                        .subquery = subquery,
                        .negated = false,
                    },
                };
            },

            // NOT expression (NOT EXISTS, NOT <boolean_expr>)
            .NOT => {
                self.advance();
                // Check for NOT EXISTS
                if (self.match(&[_]TokenType{.EXISTS})) {
                    _ = try self.expect(.LPAREN);
                    const subquery = try self.allocator.create(ast.SelectStmt);
                    subquery.* = try self.parseSelect();
                    _ = try self.expect(.RPAREN);
                    return Expr{
                        .exists = .{
                            .subquery = subquery,
                            .negated = true,
                        },
                    };
                }
                // NOT <expr> - parse as unary NOT with comparison as operand
                const operand = try self.allocator.create(Expr);
                operand.* = try self.parseComparisonExpr();
                return Expr{
                    .unary = .{
                        .op = .not,
                        .operand = operand,
                    },
                };
            },

            else => return error.UnexpectedToken,
        }
    }

    /// Parse CASE expression
    fn parseCaseExpr(self: *Self) !Expr {
        _ = try self.expect(.CASE);

        // Check for simple CASE (CASE expr WHEN ...)
        var operand: ?*Expr = null;
        if (!self.check(.WHEN)) {
            operand = try self.allocator.create(Expr);
            operand.?.* = try self.parseExpr();
        }

        // Parse WHEN clauses
        var when_clauses = std.ArrayList(ast.CaseWhen){};
        errdefer when_clauses.deinit(self.allocator);

        while (self.match(&[_]TokenType{.WHEN})) {
            const condition = try self.parseExpr();
            _ = try self.expect(.THEN);
            const result = try self.parseExpr();

            try when_clauses.append(self.allocator, ast.CaseWhen{
                .condition = condition,
                .result = result,
            });
        }

        // Parse optional ELSE
        var else_result: ?*Expr = null;
        if (self.match(&[_]TokenType{.ELSE})) {
            else_result = try self.allocator.create(Expr);
            else_result.?.* = try self.parseExpr();
        }

        _ = try self.expect(.END);

        return Expr{
            .case_expr = .{
                .operand = operand,
                .when_clauses = try when_clauses.toOwnedSlice(self.allocator),
                .else_result = else_result,
            },
        };
    }

    /// Parse CAST expression: CAST(expr AS type)
    fn parseCastExpr(self: *Self) !Expr {
        _ = try self.expect(.CAST);
        _ = try self.expect(.LPAREN);

        const expr = try self.allocator.create(Expr);
        expr.* = try self.parseExpr();

        _ = try self.expect(.AS);

        // Parse type name (can be compound like VARCHAR(255))
        const type_tok = try self.expect(.IDENTIFIER);
        const target_type = type_tok.lexeme;

        // Handle type with size like VARCHAR(255)
        if (self.check(.LPAREN)) {
            self.advance();
            _ = try self.expect(.NUMBER); // size
            if (self.match(&[_]TokenType{.COMMA})) {
                _ = try self.expect(.NUMBER); // scale for DECIMAL
            }
            _ = try self.expect(.RPAREN);
            // For simplicity, we just keep the base type name
        }

        _ = try self.expect(.RPAREN);

        return Expr{
            .cast = .{
                .expr = expr,
                .target_type = target_type,
            },
        };
    }

    fn parseFunctionCall(self: *Self, name: []const u8) anyerror!Expr {
        _ = try self.expect(.LPAREN);

        // Check for DISTINCT
        const distinct = self.match(&[_]TokenType{.DISTINCT});

        // Parse arguments
        var args = std.ArrayList(Expr){};
        errdefer args.deinit(self.allocator);

        // Check for empty argument list or STAR (for COUNT(*))
        if (!self.check(.RPAREN)) {
            while (true) {
                // Special case: STAR inside function call means "all columns" (e.g., COUNT(*))
                if (self.check(.STAR)) {
                    self.advance();
                    try args.append(self.allocator, Expr{
                        .column = .{
                            .table = null,
                            .name = "*",
                        },
                    });
                } else {
                    try args.append(self.allocator, try self.parseExpr());
                }
                if (!self.match(&[_]TokenType{.COMMA})) break;
            }
        }

        _ = try self.expect(.RPAREN);

        // Check for OVER clause (window function)
        var window: ?*ast.WindowSpec = null;
        if (self.match(&[_]TokenType{.OVER})) {
            window = try self.parseWindowSpec();
        }

        return Expr{
            .call = .{
                .name = name,
                .args = try args.toOwnedSlice(self.allocator),
                .distinct = distinct,
                .window = window,
            },
        };
    }

    /// Parse method call on a table alias (e.g., t.risk_score())
    /// Used for @logic_table computed columns
    /// Supports optional OVER clause for window functions: t.risk_score() OVER (PARTITION BY x)
    fn parseMethodCall(self: *Self, object: []const u8, method: []const u8) anyerror!Expr {
        _ = try self.expect(.LPAREN);

        // Parse arguments
        var args = std.ArrayList(Expr){};
        errdefer args.deinit(self.allocator);

        // Check for empty argument list
        if (!self.check(.RPAREN)) {
            while (true) {
                try args.append(self.allocator, try self.parseExpr());
                if (!self.match(&[_]TokenType{.COMMA})) break;
            }
        }

        _ = try self.expect(.RPAREN);

        // Check for OVER clause (window function)
        var window: ?*ast.WindowSpec = null;
        if (self.match(&[_]TokenType{.OVER})) {
            window = try self.parseWindowSpec();
        }

        return Expr{
            .method_call = .{
                .object = object,
                .method = method,
                .args = try args.toOwnedSlice(self.allocator),
                .over = window,
            },
        };
    }

    /// Parse window specification: OVER([PARTITION BY cols] [ORDER BY cols] [frame])
    fn parseWindowSpec(self: *Self) !*ast.WindowSpec {
        _ = try self.expect(.LPAREN);

        var partition_by: ?[][]const u8 = null;
        var order_by: ?[]ast.OrderBy = null;
        var frame: ?ast.WindowFrame = null;

        // Parse PARTITION BY (optional)
        if (self.match(&[_]TokenType{.PARTITION})) {
            _ = try self.expect(.BY);

            var cols = std.ArrayList([]const u8){};
            errdefer cols.deinit(self.allocator);

            while (true) {
                const col_tok = try self.expect(.IDENTIFIER);
                try cols.append(self.allocator, col_tok.lexeme);
                if (!self.match(&[_]TokenType{.COMMA})) break;
            }

            partition_by = try cols.toOwnedSlice(self.allocator);
        }

        // Parse ORDER BY (optional)
        if (self.match(&[_]TokenType{.ORDER})) {
            _ = try self.expect(.BY);

            var items = std.ArrayList(ast.OrderBy){};
            errdefer items.deinit(self.allocator);

            while (true) {
                const col_tok = try self.expect(.IDENTIFIER);

                const direction = if (self.match(&[_]TokenType{.DESC}))
                    ast.OrderDirection.desc
                else blk: {
                    _ = self.match(&[_]TokenType{.ASC}); // Optional ASC
                    break :blk ast.OrderDirection.asc;
                };

                try items.append(self.allocator, ast.OrderBy{
                    .column = col_tok.lexeme,
                    .direction = direction,
                });

                if (!self.match(&[_]TokenType{.COMMA})) break;
            }

            order_by = try items.toOwnedSlice(self.allocator);
        }

        // Parse frame specification (optional): ROWS/RANGE BETWEEN ... AND ...
        if (self.match(&[_]TokenType{.ROWS}) or self.check(.RANGE)) {
            frame = try self.parseWindowFrame();
        }

        _ = try self.expect(.RPAREN);

        const spec = try self.allocator.create(ast.WindowSpec);
        spec.* = ast.WindowSpec{
            .partition_by = partition_by,
            .order_by = order_by,
            .frame = frame,
        };

        return spec;
    }

    /// Parse window frame: ROWS/RANGE [BETWEEN start AND end | start]
    fn parseWindowFrame(self: *Self) !ast.WindowFrame {
        // Note: ROWS token was already matched in parseWindowSpec when checking for frame
        const frame_type: @TypeOf(@as(ast.WindowFrame, undefined).frame_type) = if (self.check(.RANGE)) blk: {
            self.advance();
            break :blk .range;
        } else .rows;

        // Parse frame bounds
        var start_bound: ast.FrameBound = .unbounded_preceding;
        var start_offset: ?i64 = null;
        var end_bound: ?ast.FrameBound = null;
        var end_offset: ?i64 = null;

        if (self.match(&[_]TokenType{.BETWEEN})) {
            // BETWEEN start AND end
            const start = try self.parseFrameBound();
            start_bound = start.bound;
            start_offset = start.offset;

            _ = try self.expect(.AND);

            const end = try self.parseFrameBound();
            end_bound = end.bound;
            end_offset = end.offset;
        } else {
            // Single bound (start only, end defaults to CURRENT ROW)
            const start = try self.parseFrameBound();
            start_bound = start.bound;
            start_offset = start.offset;
            end_bound = .current_row;
        }

        return ast.WindowFrame{
            .frame_type = frame_type,
            .start_bound = start_bound,
            .start_offset = start_offset,
            .end_bound = end_bound,
            .end_offset = end_offset,
        };
    }

    /// Parse a single frame bound
    fn parseFrameBound(self: *Self) !struct { bound: ast.FrameBound, offset: ?i64 } {
        if (self.match(&[_]TokenType{.UNBOUNDED})) {
            if (self.match(&[_]TokenType{.PRECEDING})) {
                return .{ .bound = .unbounded_preceding, .offset = null };
            } else if (self.match(&[_]TokenType{.FOLLOWING})) {
                return .{ .bound = .unbounded_following, .offset = null };
            }
            return error.UnexpectedToken;
        } else if (self.match(&[_]TokenType{.CURRENT})) {
            // CURRENT ROW (ROW is optional but expected)
            _ = self.match(&[_]TokenType{.IDENTIFIER}); // Skip ROW if present
            return .{ .bound = .current_row, .offset = null };
        } else if (self.check(.NUMBER)) {
            // N PRECEDING or N FOLLOWING
            const num_tok = try self.expect(.NUMBER);
            const offset = try std.fmt.parseInt(i64, num_tok.lexeme, 10);

            if (self.match(&[_]TokenType{.PRECEDING})) {
                return .{ .bound = .preceding, .offset = offset };
            } else if (self.match(&[_]TokenType{.FOLLOWING})) {
                return .{ .bound = .following, .offset = offset };
            }
            return error.UnexpectedToken;
        }

        return error.UnexpectedToken;
    }

    // ========================================================================
    // Clause parsing
    // ========================================================================

    fn parseTableRef(self: *Self) !ast.TableRef {
        // Parse primary table reference first
        var table_ref = try self.parsePrimaryTableRef();

        // Check for JOIN clauses
        while (self.isJoinKeyword()) {
            const join_clause = try self.parseJoinClause();

            // Wrap in join expression
            const left_ptr = try self.allocator.create(ast.TableRef);
            left_ptr.* = table_ref;

            table_ref = ast.TableRef{
                .join = .{
                    .left = left_ptr,
                    .join_clause = join_clause,
                },
            };
        }

        return table_ref;
    }

    /// Check if current token starts a JOIN clause
    fn isJoinKeyword(self: *const Self) bool {
        const tok = self.current() orelse return false;
        return tok.type == .JOIN or
            tok.type == .LEFT or
            tok.type == .RIGHT or
            tok.type == .INNER or
            tok.type == .OUTER or
            tok.type == .FULL or
            tok.type == .CROSS or
            tok.type == .NATURAL;
    }

    /// Parse JOIN clause: [LEFT|RIGHT|INNER|FULL|CROSS] [OUTER] JOIN table ON condition
    fn parseJoinClause(self: *Self) !ast.JoinClause {
        var join_type: ast.JoinType = .inner;

        // Parse join type
        if (self.match(&[_]TokenType{.NATURAL})) {
            join_type = .natural;
            _ = self.match(&[_]TokenType{.JOIN}); // Optional JOIN keyword after NATURAL
        } else if (self.match(&[_]TokenType{.CROSS})) {
            join_type = .cross;
            _ = try self.expect(.JOIN);
        } else if (self.match(&[_]TokenType{.LEFT})) {
            join_type = .left;
            _ = self.match(&[_]TokenType{.OUTER}); // Optional OUTER
            _ = try self.expect(.JOIN);
        } else if (self.match(&[_]TokenType{.RIGHT})) {
            join_type = .right;
            _ = self.match(&[_]TokenType{.OUTER}); // Optional OUTER
            _ = try self.expect(.JOIN);
        } else if (self.match(&[_]TokenType{.FULL})) {
            join_type = .full;
            _ = self.match(&[_]TokenType{.OUTER}); // Optional OUTER
            _ = try self.expect(.JOIN);
        } else if (self.match(&[_]TokenType{.INNER})) {
            join_type = .inner;
            _ = try self.expect(.JOIN);
        } else {
            // Plain JOIN
            _ = try self.expect(.JOIN);
            join_type = .inner;
        }

        // Parse right table
        const right_table = try self.allocator.create(ast.TableRef);
        right_table.* = try self.parsePrimaryTableRef();

        // Parse ON condition or USING clause
        var on_condition: ?Expr = null;
        var using_columns: ?[][]const u8 = null;

        if (join_type != .cross and join_type != .natural) {
            if (self.match(&[_]TokenType{.ON})) {
                on_condition = try self.parseExpr();
            } else if (self.match(&[_]TokenType{.USING})) {
                _ = try self.expect(.LPAREN);
                var cols = std.ArrayList([]const u8){};
                errdefer cols.deinit(self.allocator);

                while (true) {
                    const col_tok = try self.expect(.IDENTIFIER);
                    try cols.append(self.allocator, col_tok.lexeme);
                    if (!self.match(&[_]TokenType{.COMMA})) break;
                }
                _ = try self.expect(.RPAREN);
                using_columns = try cols.toOwnedSlice(self.allocator);
            }
        }

        return ast.JoinClause{
            .join_type = join_type,
            .table = right_table,
            .on_condition = on_condition,
            .using_columns = using_columns,
        };
    }

    /// Parse a primary (non-joined) table reference
    fn parsePrimaryTableRef(self: *Self) !ast.TableRef {
        // Support string literals as file paths (DuckDB-style): FROM 'path/to/file.lance'
        if (self.check(.STRING)) {
            const path_tok = self.current().?;
            self.advance();

            // Check for alias
            const alias = if (self.match(&[_]TokenType{.AS})) blk: {
                const tok = try self.expect(.IDENTIFIER);
                break :blk tok.lexeme;
            } else if (self.check(.IDENTIFIER) and !self.isJoinKeyword()) blk: {
                const tok = self.current().?;
                self.advance();
                break :blk tok.lexeme;
            } else null;

            return ast.TableRef{
                .simple = .{
                    .name = path_tok.lexeme,
                    .alias = alias,
                },
            };
        }

        const name_tok = try self.expect(.IDENTIFIER);

        // Check if this is a table-valued function (e.g., logic_table('path'))
        if (self.check(.LPAREN)) {
            self.advance();

            // Parse function arguments
            var args = std.ArrayList(Expr){};
            errdefer args.deinit(self.allocator);

            while (!self.check(.RPAREN) and !self.check(.EOF)) {
                try args.append(self.allocator, try self.parseExpr());
                if (!self.match(&[_]TokenType{.COMMA})) break;
            }

            _ = try self.expect(.RPAREN);

            // Check for alias
            const alias = if (self.match(&[_]TokenType{.AS})) blk: {
                const tok = try self.expect(.IDENTIFIER);
                break :blk tok.lexeme;
            } else if (self.check(.IDENTIFIER) and !self.isJoinKeyword()) blk: {
                // Alias without AS keyword (but not if it's a JOIN keyword)
                const tok = self.current().?;
                self.advance();
                break :blk tok.lexeme;
            } else null;

            return ast.TableRef{
                .function = .{
                    .func = ast.TableFunction{
                        .name = name_tok.lexeme,
                        .args = try args.toOwnedSlice(self.allocator),
                    },
                    .alias = alias,
                },
            };
        }

        // Simple table reference
        // Check for alias (but not if it's a JOIN keyword)
        const alias = if (self.match(&[_]TokenType{.AS})) blk: {
            const tok = try self.expect(.IDENTIFIER);
            break :blk tok.lexeme;
        } else if (self.check(.IDENTIFIER) and !self.isJoinKeyword()) blk: {
            // Alias without AS keyword
            const tok = self.current().?;
            self.advance();
            break :blk tok.lexeme;
        } else null;

        return ast.TableRef{
            .simple = .{
                .name = name_tok.lexeme,
                .alias = alias,
            },
        };
    }

    fn parseGroupBy(self: *Self) !ast.GroupBy {
        _ = try self.expect(.BY);

        var columns = std.ArrayList([]const u8){};
        errdefer columns.deinit(self.allocator);

        while (true) {
            const tok = try self.expect(.IDENTIFIER);
            try columns.append(self.allocator, tok.lexeme);

            if (!self.match(&[_]TokenType{.COMMA})) break;
        }

        // HAVING clause (optional)
        const having = if (self.match(&[_]TokenType{.HAVING}))
            try self.parseExpr()
        else
            null;

        return ast.GroupBy{
            .columns = try columns.toOwnedSlice(self.allocator),
            .having = having,
        };
    }

    fn parseOrderBy(self: *Self) ![]ast.OrderBy {
        _ = try self.expect(.BY);

        var items = std.ArrayList(ast.OrderBy){};
        errdefer items.deinit(self.allocator);

        while (true) {
            const tok = try self.expect(.IDENTIFIER);

            const direction = if (self.match(&[_]TokenType{.DESC}))
                ast.OrderDirection.desc
            else blk: {
                _ = self.match(&[_]TokenType{.ASC}); // Optional ASC
                break :blk ast.OrderDirection.asc;
            };

            try items.append(self.allocator, ast.OrderBy{
                .column = tok.lexeme,
                .direction = direction,
            });

            if (!self.match(&[_]TokenType{.COMMA})) break;
        }

        return items.toOwnedSlice(self.allocator);
    }

    fn parseLimitValue(self: *Self) !u32 {
        const tok = try self.expect(.NUMBER);
        return try std.fmt.parseInt(u32, tok.lexeme, 10);
    }
};

// ============================================================================
// Helper function for parsing SQL strings
// ============================================================================

pub fn parseSQL(sql: []const u8, allocator: std.mem.Allocator) !Statement {
    var lex = lexer.Lexer.init(sql);
    const tokens = try lex.tokenize(allocator);
    defer allocator.free(tokens);

    var parser = Parser.init(tokens, allocator);
    return try parser.parseStatement();
}

// ============================================================================
// Tests
// ============================================================================

test "parse simple SELECT" {
    const sql = "SELECT id FROM users";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    try std.testing.expect(stmt == .select);
    try std.testing.expectEqual(@as(usize, 1), stmt.select.columns.len);
}

test "parse SELECT with WHERE" {
    const sql = "SELECT name FROM users WHERE id = 42";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    try std.testing.expect(stmt == .select);
    try std.testing.expect(stmt.select.where != null);
}

test "parse SELECT with parameter" {
    const sql = "SELECT * FROM users WHERE id = ?";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    try std.testing.expect(stmt == .select);
    try std.testing.expect(stmt.select.where != null);

    // Verify the WHERE clause contains a parameter
    const where = stmt.select.where.?;
    try std.testing.expect(where == .binary);
    const right = where.binary.right.*;
    try std.testing.expect(right == .value);
    try std.testing.expect(right.value == .parameter);
    try std.testing.expectEqual(@as(u32, 0), right.value.parameter);
}

test "parse SELECT with multiple parameters" {
    const sql = "SELECT * FROM users WHERE id > ? AND name = ?";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    try std.testing.expect(stmt == .select);
    try std.testing.expect(stmt.select.where != null);

    // Verify there are two parameters with indices 0 and 1
    const where = stmt.select.where.?;
    try std.testing.expect(where == .binary); // AND expression
    try std.testing.expectEqual(ast.BinaryOp.@"and", where.binary.op);

    // Left side: id > ?  (param index 0)
    const left_binary = where.binary.left.*.binary;
    try std.testing.expectEqual(ast.BinaryOp.gt, left_binary.op);
    try std.testing.expectEqual(@as(u32, 0), left_binary.right.*.value.parameter);

    // Right side: name = ?  (param index 1)
    const right_binary = where.binary.right.*.binary;
    try std.testing.expectEqual(ast.BinaryOp.eq, right_binary.op);
    try std.testing.expectEqual(@as(u32, 1), right_binary.right.*.value.parameter);
}

test "parse window function with PARTITION BY" {
    const sql = "SELECT SUM(amount) OVER(PARTITION BY category) FROM transactions";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    try std.testing.expect(stmt == .select);
    try std.testing.expectEqual(@as(usize, 1), stmt.select.columns.len);

    // Verify it's a function call with window spec
    const expr = stmt.select.columns[0].expr;
    try std.testing.expect(expr == .call);
    try std.testing.expectEqualStrings("SUM", expr.call.name);
    try std.testing.expect(expr.call.window != null);

    // Verify PARTITION BY
    const window = expr.call.window.?;
    try std.testing.expect(window.partition_by != null);
    try std.testing.expectEqual(@as(usize, 1), window.partition_by.?.len);
    try std.testing.expectEqualStrings("category", window.partition_by.?[0]);
}

test "parse window function with PARTITION BY and ORDER BY" {
    const sql = "SELECT ROW_NUMBER() OVER(PARTITION BY dept ORDER BY salary DESC) FROM employees";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    try std.testing.expect(stmt == .select);

    const expr = stmt.select.columns[0].expr;
    try std.testing.expect(expr == .call);
    try std.testing.expect(expr.call.window != null);

    const window = expr.call.window.?;
    // PARTITION BY dept
    try std.testing.expect(window.partition_by != null);
    try std.testing.expectEqualStrings("dept", window.partition_by.?[0]);
    // ORDER BY salary DESC
    try std.testing.expect(window.order_by != null);
    try std.testing.expectEqualStrings("salary", window.order_by.?[0].column);
    try std.testing.expectEqual(ast.OrderDirection.desc, window.order_by.?[0].direction);
}

test "parse window function with multiple PARTITION BY columns" {
    const sql = "SELECT AVG(score) OVER(PARTITION BY region, category) FROM sales";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    const expr = stmt.select.columns[0].expr;
    const window = expr.call.window.?;

    try std.testing.expect(window.partition_by != null);
    try std.testing.expectEqual(@as(usize, 2), window.partition_by.?.len);
    try std.testing.expectEqualStrings("region", window.partition_by.?[0]);
    try std.testing.expectEqualStrings("category", window.partition_by.?[1]);
}

test "parse method call expression" {
    const sql = "SELECT t.risk_score() FROM logic_table('fraud.py') AS t";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    try std.testing.expect(stmt == .select);
    try std.testing.expectEqual(@as(usize, 1), stmt.select.columns.len);

    // Verify it's a method call
    const expr = stmt.select.columns[0].expr;
    try std.testing.expect(expr == .method_call);
    try std.testing.expectEqualStrings("t", expr.method_call.object);
    try std.testing.expectEqualStrings("risk_score", expr.method_call.method);
    try std.testing.expectEqual(@as(usize, 0), expr.method_call.args.len);
}

test "parse method call with arguments" {
    const sql = "SELECT t.compute(100, 0.5) FROM table1 AS t";
    const allocator = std.testing.allocator;

    const stmt = try parseSQL(sql, allocator);
    const expr = stmt.select.columns[0].expr;

    try std.testing.expect(expr == .method_call);
    try std.testing.expectEqualStrings("t", expr.method_call.object);
    try std.testing.expectEqualStrings("compute", expr.method_call.method);
    try std.testing.expectEqual(@as(usize, 2), expr.method_call.args.len);

    // Check first argument
    try std.testing.expect(expr.method_call.args[0] == .value);
    try std.testing.expectEqual(@as(i64, 100), expr.method_call.args[0].value.integer);

    // Check second argument
    try std.testing.expect(expr.method_call.args[1] == .value);
    try std.testing.expectEqual(@as(f64, 0.5), expr.method_call.args[1].value.float);
}

test "parse qualified column vs method call" {
    const allocator = std.testing.allocator;

    // Qualified column: table.column (no parentheses)
    const sql1 = "SELECT t.name FROM table1 AS t";
    const stmt1 = try parseSQL(sql1, allocator);
    const expr1 = stmt1.select.columns[0].expr;

    try std.testing.expect(expr1 == .column);
    try std.testing.expectEqualStrings("t", expr1.column.table.?);
    try std.testing.expectEqualStrings("name", expr1.column.name);

    // Method call: table.method() (with parentheses)
    const sql2 = "SELECT t.name() FROM table1 AS t";
    const stmt2 = try parseSQL(sql2, allocator);
    const expr2 = stmt2.select.columns[0].expr;

    try std.testing.expect(expr2 == .method_call);
    try std.testing.expectEqualStrings("t", expr2.method_call.object);
    try std.testing.expectEqualStrings("name", expr2.method_call.method);
}

test "parse method call with OVER clause" {
    const allocator = std.testing.allocator;

    // Method call with window specification
    const sql = "SELECT t.risk_score() OVER (PARTITION BY customer_id ORDER BY created_at DESC) FROM orders AS t";
    var stmt = try parseSQL(sql, allocator);
    defer ast.deinitSelectStmt(&stmt.select, allocator);

    const expr = stmt.select.columns[0].expr;

    try std.testing.expect(expr == .method_call);
    try std.testing.expectEqualStrings("t", expr.method_call.object);
    try std.testing.expectEqualStrings("risk_score", expr.method_call.method);
    try std.testing.expectEqual(@as(usize, 0), expr.method_call.args.len);

    // Verify OVER clause
    try std.testing.expect(expr.method_call.over != null);
    const over = expr.method_call.over.?;

    // Check PARTITION BY
    try std.testing.expect(over.partition_by != null);
    try std.testing.expectEqual(@as(usize, 1), over.partition_by.?.len);
    try std.testing.expectEqualStrings("customer_id", over.partition_by.?[0]);

    // Check ORDER BY
    try std.testing.expect(over.order_by != null);
    try std.testing.expectEqual(@as(usize, 1), over.order_by.?.len);
    try std.testing.expectEqualStrings("created_at", over.order_by.?[0].column);
    try std.testing.expectEqual(ast.OrderDirection.desc, over.order_by.?[0].direction);
}

test "parse method call without OVER clause" {
    const allocator = std.testing.allocator;

    // Method call without window specification
    const sql = "SELECT t.compute() FROM table1 AS t";
    var stmt = try parseSQL(sql, allocator);
    defer ast.deinitSelectStmt(&stmt.select, allocator);

    const expr = stmt.select.columns[0].expr;

    try std.testing.expect(expr == .method_call);
    try std.testing.expect(expr.method_call.over == null);
}

test "parse UNION" {
    const allocator = std.testing.allocator;

    const sql = "SELECT id FROM users UNION SELECT id FROM admins";
    var stmt = try parseSQL(sql, allocator);
    defer ast.deinitSelectStmt(&stmt.select, allocator);

    // First SELECT
    try std.testing.expectEqual(@as(usize, 1), stmt.select.columns.len);

    // Verify set operation
    try std.testing.expect(stmt.select.set_operation != null);
    const set_op = stmt.select.set_operation.?;
    try std.testing.expectEqual(ast.SetOperationType.union_distinct, set_op.op_type);

    // Verify second SELECT
    try std.testing.expectEqual(@as(usize, 1), set_op.right.columns.len);
}

test "parse UNION ALL" {
    const allocator = std.testing.allocator;

    const sql = "SELECT name FROM employees UNION ALL SELECT name FROM contractors";
    var stmt = try parseSQL(sql, allocator);
    defer ast.deinitSelectStmt(&stmt.select, allocator);

    try std.testing.expect(stmt.select.set_operation != null);
    const set_op = stmt.select.set_operation.?;
    try std.testing.expectEqual(ast.SetOperationType.union_all, set_op.op_type);
}

test "parse INTERSECT" {
    const allocator = std.testing.allocator;

    const sql = "SELECT id FROM active_users INTERSECT SELECT id FROM premium_users";
    var stmt = try parseSQL(sql, allocator);
    defer ast.deinitSelectStmt(&stmt.select, allocator);

    try std.testing.expect(stmt.select.set_operation != null);
    const set_op = stmt.select.set_operation.?;
    try std.testing.expectEqual(ast.SetOperationType.intersect, set_op.op_type);
}

test "parse EXCEPT" {
    const allocator = std.testing.allocator;

    const sql = "SELECT id FROM all_users EXCEPT SELECT id FROM banned_users";
    var stmt = try parseSQL(sql, allocator);
    defer ast.deinitSelectStmt(&stmt.select, allocator);

    try std.testing.expect(stmt.select.set_operation != null);
    const set_op = stmt.select.set_operation.?;
    try std.testing.expectEqual(ast.SetOperationType.except, set_op.op_type);
}

test "parse chained UNION" {
    const allocator = std.testing.allocator;

    const sql = "SELECT a FROM t1 UNION SELECT b FROM t2 UNION SELECT c FROM t3";
    var stmt = try parseSQL(sql, allocator);
    defer ast.deinitSelectStmt(&stmt.select, allocator);

    // First UNION
    try std.testing.expect(stmt.select.set_operation != null);
    const set_op1 = stmt.select.set_operation.?;
    try std.testing.expectEqual(ast.SetOperationType.union_distinct, set_op1.op_type);

    // Second UNION (chained)
    try std.testing.expect(set_op1.right.set_operation != null);
    const set_op2 = set_op1.right.set_operation.?;
    try std.testing.expectEqual(ast.SetOperationType.union_distinct, set_op2.op_type);
}
