const std = @import("std");
const ast = @import("../ast.zig");
const lexer = @import("../lexer.zig");
const ParseError = @import("../parser.zig").ParseError;
const Parser = @import("../parser.zig").Parser;
const literals = @import("literals.zig");
const expressions = @import("expressions.zig");

/// Parse postfix expressions: function calls, subscripts, attribute access
pub fn parsePostfix(self: *Parser) ParseError!ast.Node {
    var node = try parsePrimary(self);

    while (true) {
        if (self.match(.LParen)) {
            // Function call
            node = try parseCall(self, node);
        } else if (self.match(.LBracket)) {
            // Subscript or slice
            const node_ptr = try self.allocator.create(ast.Node);
            node_ptr.* = node;

            // Check if it starts with colon (e.g., [:5] or [::2])
            if (self.check(.Colon)) {
                _ = self.advance();

                // Check for second colon: [::step]
                if (self.check(.Colon)) {
                    _ = self.advance();
                    const step = if (!self.check(.RBracket)) try self.parseExpression() else null;
                    _ = try self.expect(.RBracket);

                    const step_ptr = if (step) |s| blk: {
                        const ptr = try self.allocator.create(ast.Node);
                        ptr.* = s;
                        break :blk ptr;
                    } else null;

                    node = ast.Node{
                        .subscript = .{
                            .value = node_ptr,
                            .slice = .{
                                .slice = .{
                                    .lower = null,
                                    .upper = null,
                                    .step = step_ptr,
                                },
                            },
                        },
                    };
                } else {
                    // [:upper] or [:upper:step]
                    const upper = if (!self.check(.RBracket) and !self.check(.Colon)) try self.parseExpression() else null;

                    // Check for step: [:upper:step]
                    const step = if (self.match(.Colon)) blk: {
                        if (!self.check(.RBracket)) {
                            break :blk try self.parseExpression();
                        } else {
                            break :blk null;
                        }
                    } else null;

                    _ = try self.expect(.RBracket);

                    const upper_ptr = if (upper) |u| blk: {
                        const ptr = try self.allocator.create(ast.Node);
                        ptr.* = u;
                        break :blk ptr;
                    } else null;

                    const step_ptr = if (step) |s| blk: {
                        const ptr = try self.allocator.create(ast.Node);
                        ptr.* = s;
                        break :blk ptr;
                    } else null;

                    node = ast.Node{
                        .subscript = .{
                            .value = node_ptr,
                            .slice = .{
                                .slice = .{
                                    .lower = null,
                                    .upper = upper_ptr,
                                    .step = step_ptr,
                                },
                            },
                        },
                    };
                }
            } else {
                const lower = try self.parseExpression();

                if (self.match(.Colon)) {
                    // Slice: [start:end] or [start:]
                    const upper = if (!self.check(.RBracket) and !self.check(.Colon)) try self.parseExpression() else null;

                    // Check for step: [start:end:step]
                    const step = if (self.match(.Colon)) blk: {
                        if (!self.check(.RBracket)) {
                            break :blk try self.parseExpression();
                        } else {
                            break :blk null;
                        }
                    } else null;

                    _ = try self.expect(.RBracket);

                    const lower_ptr = try self.allocator.create(ast.Node);
                    lower_ptr.* = lower;

                    const upper_ptr = if (upper) |u| blk: {
                        const ptr = try self.allocator.create(ast.Node);
                        ptr.* = u;
                        break :blk ptr;
                    } else null;

                    const step_ptr = if (step) |s| blk: {
                        const ptr = try self.allocator.create(ast.Node);
                        ptr.* = s;
                        break :blk ptr;
                    } else null;

                    node = ast.Node{
                        .subscript = .{
                            .value = node_ptr,
                            .slice = .{
                                .slice = .{
                                    .lower = lower_ptr,
                                    .upper = upper_ptr,
                                    .step = step_ptr,
                                },
                            },
                        },
                    };
                } else if (self.check(.Comma)) {
                    // Multi-element subscript: arr[0, 1, 2] (numpy-style)
                    // Store as tuple of indices
                    var indices = std.ArrayList(ast.Node){};
                    defer indices.deinit(self.allocator);
                    try indices.append(self.allocator, lower);

                    while (self.match(.Comma)) {
                        // Allow trailing comma: [0,]
                        if (self.check(.RBracket)) break;
                        try indices.append(self.allocator, try self.parseExpression());
                    }

                    _ = try self.expect(.RBracket);

                    const index_ptr = try self.allocator.create(ast.Node);
                    index_ptr.* = ast.Node{
                        .tuple = .{ .elts = try indices.toOwnedSlice(self.allocator) },
                    };

                    node = ast.Node{
                        .subscript = .{
                            .value = node_ptr,
                            .slice = .{ .index = index_ptr },
                        },
                    };
                } else {
                    // Simple index: [0]
                    _ = try self.expect(.RBracket);

                    const index_ptr = try self.allocator.create(ast.Node);
                    index_ptr.* = lower;

                    node = ast.Node{
                        .subscript = .{
                            .value = node_ptr,
                            .slice = .{ .index = index_ptr },
                        },
                    };
                }
            }
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

/// Parse function call
pub fn parseCall(self: *Parser, func: ast.Node) !ast.Node {
    var args = std.ArrayList(ast.Node){};
    defer args.deinit(self.allocator);
    var keyword_args = std.ArrayList(ast.Node.KeywordArg){};
    defer keyword_args.deinit(self.allocator);

    while (!self.match(.RParen)) {
        // Check for ** operator for kwargs unpacking: func(**kwargs)
        // Must check DoubleStar before Star since ** starts with *
        if (self.match(.DoubleStar)) {
            const value = try self.parseExpression();
            const value_ptr = try self.allocator.create(ast.Node);
            value_ptr.* = value;

            const double_starred_arg = ast.Node{
                .double_starred = .{
                    .value = value_ptr,
                },
            };
            try args.append(self.allocator, double_starred_arg);
        } else if (self.match(.Star)) {
            // Check for * operator for unpacking: func(*args)
            const value = try self.parseExpression();
            const value_ptr = try self.allocator.create(ast.Node);
            value_ptr.* = value;

            const starred_arg = ast.Node{
                .starred = .{
                    .value = value_ptr,
                },
            };
            try args.append(self.allocator, starred_arg);
        } else {
            // Check if this is a keyword argument (name=value)
            // We need to lookahead: if next token is Ident followed by Eq
            if (self.check(.Ident)) {
                const saved_pos = self.current;
                const name_tok = self.advance().?;

                if (self.check(.Eq)) {
                    // It's a keyword argument
                    _ = self.advance(); // consume =
                    const value = try self.parseExpression();
                    try keyword_args.append(self.allocator, .{
                        .name = name_tok.lexeme,
                        .value = value,
                    });
                } else {
                    // Not a keyword arg, restore position and parse as normal expression
                    self.current = saved_pos;
                    const arg = try self.parseExpression();
                    try args.append(self.allocator, arg);
                }
            } else {
                const arg = try self.parseExpression();
                try args.append(self.allocator, arg);
            }
        }

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
            .keyword_args = try keyword_args.toOwnedSlice(self.allocator),
        },
    };
}

/// Parse primary expressions: literals, identifiers, grouped expressions
pub fn parsePrimary(self: *Parser) ParseError!ast.Node {
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
            .ComplexNumber => {
                const num_tok = self.advance().?;
                // Strip 'j' suffix and parse as float (full complex math later)
                const lexeme_without_j = num_tok.lexeme[0 .. num_tok.lexeme.len - 1];
                const float_val = try std.fmt.parseFloat(f64, lexeme_without_j);
                return ast.Node{
                    .constant = .{
                        .value = .{ .float = float_val },
                    },
                };
            },
            .String => {
                const str_tok = self.advance().?;
                var result_str = str_tok.lexeme;

                // Handle implicit string concatenation: "a" "b" -> "ab"
                // Only skip newlines if followed by another String (don't consume otherwise)
                while (true) {
                    // Peek ahead to check if there's a String after any newlines
                    var lookahead: usize = 0;
                    while (self.current + lookahead < self.tokens.len and
                        self.tokens[self.current + lookahead].type == .Newline)
                    {
                        lookahead += 1;
                    }

                    // Check if there's a String after the newlines
                    if (self.current + lookahead < self.tokens.len and
                        self.tokens[self.current + lookahead].type == .String)
                    {
                        // Now safe to skip newlines and consume the String
                        self.skipNewlines();
                        const next_str = self.advance().?;
                        // Strip quotes before concatenating: "a" + "b" -> "ab" not "a""b"
                        const first_content = if (result_str.len >= 2) result_str[0 .. result_str.len - 1] else result_str;
                        const second_content = if (next_str.lexeme.len >= 2) next_str.lexeme[1..] else next_str.lexeme;

                        // Allocate new string with combined length
                        const new_len = first_content.len + second_content.len;
                        const new_str = try self.allocator.alloc(u8, new_len);
                        @memcpy(new_str[0..first_content.len], first_content);
                        @memcpy(new_str[first_content.len..], second_content);
                        result_str = new_str;
                    } else {
                        break;
                    }
                }

                return ast.Node{
                    .constant = .{
                        .value = .{ .string = result_str },
                    },
                };
            },
            .ByteString => {
                // Byte strings b"..." are treated as regular strings
                // Strip the 'b' prefix from lexeme: b"hello" -> "hello"
                const str_tok = self.advance().?;
                const stripped = if (str_tok.lexeme.len > 0 and str_tok.lexeme[0] == 'b')
                    str_tok.lexeme[1..]
                else
                    str_tok.lexeme;
                return ast.Node{
                    .constant = .{
                        .value = .{ .string = stripped },
                    },
                };
            },
            .RawString => {
                // Raw strings r"..." are treated as regular strings
                // Strip the 'r' prefix from lexeme: r"\n" -> "\n"
                const str_tok = self.advance().?;
                const stripped = if (str_tok.lexeme.len > 0 and str_tok.lexeme[0] == 'r')
                    str_tok.lexeme[1..]
                else
                    str_tok.lexeme;
                return ast.Node{
                    .constant = .{
                        .value = .{ .string = stripped },
                    },
                };
            },
            .FString => {
                const fstr_tok = self.advance().?;
                const lexer_parts = fstr_tok.fstring_parts orelse &[_]lexer.FStringPart{};

                // Convert lexer FStringParts to AST FStringParts
                var ast_parts = try self.allocator.alloc(ast.FStringPart, lexer_parts.len);

                for (lexer_parts, 0..) |lexer_part, i| {
                    switch (lexer_part) {
                        .literal => |lit| {
                            ast_parts[i] = .{ .literal = lit };
                        },
                        .expr => |expr_text| {
                            // Parse the expression text into an AST node
                            var expr_lexer = try lexer.Lexer.init(self.allocator, expr_text);
                            defer expr_lexer.deinit();

                            const expr_tokens = try expr_lexer.tokenize();
                            defer self.allocator.free(expr_tokens);

                            var expr_parser = Parser.init(self.allocator, expr_tokens);
                            const expr_node = try expr_parser.parseExpression();

                            const expr_ptr = try self.allocator.create(ast.Node);
                            expr_ptr.* = expr_node;

                            ast_parts[i] = .{ .expr = expr_ptr };
                        },
                        .format_expr => |fe| {
                            // Parse the expression text into an AST node
                            var expr_lexer = try lexer.Lexer.init(self.allocator, fe.expr);
                            defer expr_lexer.deinit();

                            const expr_tokens = try expr_lexer.tokenize();
                            defer self.allocator.free(expr_tokens);

                            var expr_parser = Parser.init(self.allocator, expr_tokens);
                            const expr_node = try expr_parser.parseExpression();

                            const expr_ptr = try self.allocator.create(ast.Node);
                            expr_ptr.* = expr_node;

                            ast_parts[i] = .{
                                .format_expr = .{
                                    .expr = expr_ptr,
                                    .format_spec = fe.format_spec,
                                    .conversion = fe.conversion,
                                },
                            };
                        },
                        .conv_expr => |ce| {
                            // Parse the expression text into an AST node
                            var expr_lexer = try lexer.Lexer.init(self.allocator, ce.expr);
                            defer expr_lexer.deinit();

                            const expr_tokens = try expr_lexer.tokenize();
                            defer self.allocator.free(expr_tokens);

                            var expr_parser = Parser.init(self.allocator, expr_tokens);
                            const expr_node = try expr_parser.parseExpression();

                            const expr_ptr = try self.allocator.create(ast.Node);
                            expr_ptr.* = expr_node;

                            ast_parts[i] = .{
                                .conv_expr = .{
                                    .expr = expr_ptr,
                                    .conversion = ce.conversion,
                                },
                            };
                        },
                    }
                }

                return ast.Node{
                    .fstring = .{
                        .parts = ast_parts,
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
                // Represent None as none constant
                return ast.Node{
                    .constant = .{
                        .value = .{ .none = {} },
                    },
                };
            },
            .Ellipsis => {
                _ = self.advance();
                return ast.Node{
                    .ellipsis_literal = {},
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
            .Await => {
                _ = self.advance();
                const value_ptr = try self.allocator.create(ast.Node);
                value_ptr.* = try parsePostfix(self);
                return ast.Node{
                    .await_expr = .{
                        .value = value_ptr,
                    },
                };
            },
            .Lambda => {
                return try expressions.parseLambda(self);
            },
            .LParen => {
                _ = self.advance();

                // Check for empty tuple ()
                if (self.check(.RParen)) {
                    _ = try self.expect(.RParen);
                    return ast.Node{ .tuple = .{ .elts = &.{} } };
                }

                const first = try self.parseExpression();

                // Check if it's a tuple (has comma) or grouped expression
                if (self.match(.Comma)) {
                    // It's a tuple: (1, 2, 3)
                    var elements = std.ArrayList(ast.Node){};
                    try elements.append(self.allocator, first);

                    // Parse remaining elements
                    while (!self.check(.RParen)) {
                        try elements.append(self.allocator, try self.parseExpression());
                        if (!self.match(.Comma)) break;
                    }

                    _ = try self.expect(.RParen);
                    return ast.Node{ .tuple = .{ .elts = try elements.toOwnedSlice(self.allocator) } };
                } else {
                    // Just a grouped expression: (x + 1)
                    _ = try self.expect(.RParen);
                    return first;
                }
            },
            .LBracket => {
                return try literals.parseList(self);
            },
            .LBrace => {
                return try literals.parseDict(self);
            },
            .Minus => {
                // Unary minus (e.g., -10)
                _ = self.advance();
                const operand_ptr = try self.allocator.create(ast.Node);
                operand_ptr.* = try parsePrimary(self);
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
                operand_ptr.* = try parsePrimary(self);
                return ast.Node{
                    .unaryop = .{
                        .op = .UAdd,
                        .operand = operand_ptr,
                    },
                };
            },
            .Tilde => {
                // Bitwise NOT (e.g., ~2)
                _ = self.advance();
                const operand_ptr = try self.allocator.create(ast.Node);
                operand_ptr.* = try parsePrimary(self);
                return ast.Node{
                    .unaryop = .{
                        .op = .Invert,
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
