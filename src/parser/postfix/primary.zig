const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const literals = @import("../literals.zig");
const expressions = @import("../expressions.zig");
const parsePostfix = @import("../postfix.zig").parsePostfix;

/// Parse primary expressions: literals, identifiers, grouped expressions
pub fn parsePrimary(self: *Parser) ParseError!ast.Node {
    if (self.peek()) |tok| {
        switch (tok.type) {
            .Number => return parseNumber(self),
            .ComplexNumber => return parseComplexNumber(self),
            .String => return parseString(self),
            .ByteString => return parseByteString(self),
            .RawString => return parseRawString(self),
            .FString => return parseFString(self),
            .True => return parseTrue(self),
            .False => return parseFalse(self),
            .None => return parseNone(self),
            .Ellipsis => return parseEllipsis(self),
            .Ident => return parseIdent(self),
            .Await => return parseAwait(self),
            .Lambda => return expressions.parseLambda(self),
            .LParen => return parseGroupedOrTuple(self),
            .LBracket => return literals.parseList(self),
            .LBrace => return literals.parseDict(self),
            .Minus => return parseUnaryMinus(self),
            .Plus => return parseUnaryPlus(self),
            .Tilde => return parseBitwiseNot(self),
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

fn parseNumber(self: *Parser) ParseError!ast.Node {
    const num_tok = self.advance().?;
    const lexeme = num_tok.lexeme;

    // Detect base from prefix
    if (lexeme.len >= 2 and lexeme[0] == '0') {
        const prefix = lexeme[1];
        if (prefix == 'x' or prefix == 'X') {
            const int_val = std.fmt.parseInt(i64, lexeme[2..], 16) catch 0;
            return ast.Node{ .constant = .{ .value = .{ .int = int_val } } };
        } else if (prefix == 'o' or prefix == 'O') {
            const int_val = std.fmt.parseInt(i64, lexeme[2..], 8) catch 0;
            return ast.Node{ .constant = .{ .value = .{ .int = int_val } } };
        } else if (prefix == 'b' or prefix == 'B') {
            const int_val = std.fmt.parseInt(i64, lexeme[2..], 2) catch 0;
            return ast.Node{ .constant = .{ .value = .{ .int = int_val } } };
        }
    }

    // Try to parse as decimal int, fall back to float
    if (std.fmt.parseInt(i64, lexeme, 10)) |int_val| {
        return ast.Node{ .constant = .{ .value = .{ .int = int_val } } };
    } else |_| {
        const float_val = try std.fmt.parseFloat(f64, lexeme);
        return ast.Node{ .constant = .{ .value = .{ .float = float_val } } };
    }
}

fn parseComplexNumber(self: *Parser) ParseError!ast.Node {
    const num_tok = self.advance().?;
    const lexeme_without_j = num_tok.lexeme[0 .. num_tok.lexeme.len - 1];
    const float_val = try std.fmt.parseFloat(f64, lexeme_without_j);
    return ast.Node{ .constant = .{ .value = .{ .float = float_val } } };
}

fn parseString(self: *Parser) ParseError!ast.Node {
    const str_tok = self.advance().?;
    var result_str = str_tok.lexeme;

    // Handle implicit string concatenation: "a" "b" -> "ab"
    while (true) {
        var lookahead: usize = 0;
        while (self.current + lookahead < self.tokens.len and
            self.tokens[self.current + lookahead].type == .Newline)
        {
            lookahead += 1;
        }

        if (self.current + lookahead < self.tokens.len and
            self.tokens[self.current + lookahead].type == .String)
        {
            self.skipNewlines();
            const next_str = self.advance().?;
            const first_content = if (result_str.len >= 2) result_str[0 .. result_str.len - 1] else result_str;
            const second_content = if (next_str.lexeme.len >= 2) next_str.lexeme[1..] else next_str.lexeme;

            const new_len = first_content.len + second_content.len;
            const new_str = try self.allocator.alloc(u8, new_len);
            @memcpy(new_str[0..first_content.len], first_content);
            @memcpy(new_str[first_content.len..], second_content);
            result_str = new_str;
        } else {
            break;
        }
    }

    return ast.Node{ .constant = .{ .value = .{ .string = result_str } } };
}

fn parseByteString(self: *Parser) ParseError!ast.Node {
    const str_tok = self.advance().?;
    const stripped = if (str_tok.lexeme.len > 0 and str_tok.lexeme[0] == 'b')
        str_tok.lexeme[1..]
    else
        str_tok.lexeme;
    return ast.Node{ .constant = .{ .value = .{ .string = stripped } } };
}

fn parseRawString(self: *Parser) ParseError!ast.Node {
    const str_tok = self.advance().?;
    const stripped = if (str_tok.lexeme.len > 0 and str_tok.lexeme[0] == 'r')
        str_tok.lexeme[1..]
    else
        str_tok.lexeme;
    return ast.Node{ .constant = .{ .value = .{ .string = stripped } } };
}

fn parseFString(self: *Parser) ParseError!ast.Node {
    const fstr_tok = self.advance().?;
    const lexer_parts = fstr_tok.fstring_parts orelse &[_]lexer.FStringPart{};
    var ast_parts = try self.allocator.alloc(ast.FStringPart, lexer_parts.len);

    for (lexer_parts, 0..) |lexer_part, i| {
        ast_parts[i] = try convertFStringPart(self, lexer_part);
    }

    return ast.Node{ .fstring = .{ .parts = ast_parts } };
}

fn convertFStringPart(self: *Parser, lexer_part: lexer.FStringPart) ParseError!ast.FStringPart {
    switch (lexer_part) {
        .literal => |lit| return .{ .literal = lit },
        .expr => |expr_text| {
            const expr_ptr = try parseEmbeddedExpr(self, expr_text);
            return .{ .expr = expr_ptr };
        },
        .format_expr => |fe| {
            const expr_ptr = try parseEmbeddedExpr(self, fe.expr);
            return .{ .format_expr = .{
                .expr = expr_ptr,
                .format_spec = fe.format_spec,
                .conversion = fe.conversion,
            } };
        },
        .conv_expr => |ce| {
            const expr_ptr = try parseEmbeddedExpr(self, ce.expr);
            return .{ .conv_expr = .{
                .expr = expr_ptr,
                .conversion = ce.conversion,
            } };
        },
    }
}

fn parseEmbeddedExpr(self: *Parser, expr_text: []const u8) ParseError!*ast.Node {
    var expr_lexer = try lexer.Lexer.init(self.allocator, expr_text);
    defer expr_lexer.deinit();

    const expr_tokens = try expr_lexer.tokenize();
    defer self.allocator.free(expr_tokens);

    var expr_parser = Parser.init(self.allocator, expr_tokens);
    const expr_node = try expr_parser.parseExpression();

    const expr_ptr = try self.allocator.create(ast.Node);
    expr_ptr.* = expr_node;
    return expr_ptr;
}

fn parseTrue(self: *Parser) ast.Node {
    _ = self.advance();
    return ast.Node{ .constant = .{ .value = .{ .bool = true } } };
}

fn parseFalse(self: *Parser) ast.Node {
    _ = self.advance();
    return ast.Node{ .constant = .{ .value = .{ .bool = false } } };
}

fn parseNone(self: *Parser) ast.Node {
    _ = self.advance();
    return ast.Node{ .constant = .{ .value = .{ .none = {} } } };
}

fn parseEllipsis(self: *Parser) ast.Node {
    _ = self.advance();
    return ast.Node{ .ellipsis_literal = {} };
}

fn parseIdent(self: *Parser) ast.Node {
    const ident_tok = self.advance().?;
    return ast.Node{ .name = .{ .id = ident_tok.lexeme } };
}

fn parseAwait(self: *Parser) ParseError!ast.Node {
    _ = self.advance();
    const value_ptr = try self.allocator.create(ast.Node);
    value_ptr.* = try parsePostfix(self);
    return ast.Node{ .await_expr = .{ .value = value_ptr } };
}

fn parseGroupedOrTuple(self: *Parser) ParseError!ast.Node {
    _ = self.advance();

    // Check for empty tuple ()
    if (self.check(.RParen)) {
        _ = try self.expect(.RParen);
        return ast.Node{ .tuple = .{ .elts = &.{} } };
    }

    const first = try self.parseExpression();

    // Check if it's a tuple (has comma) or grouped expression
    if (self.match(.Comma)) {
        var elements = std.ArrayList(ast.Node){};
        try elements.append(self.allocator, first);

        while (!self.check(.RParen)) {
            try elements.append(self.allocator, try self.parseExpression());
            if (!self.match(.Comma)) break;
        }

        _ = try self.expect(.RParen);
        return ast.Node{ .tuple = .{ .elts = try elements.toOwnedSlice(self.allocator) } };
    } else {
        _ = try self.expect(.RParen);
        return first;
    }
}

fn parseUnaryMinus(self: *Parser) ParseError!ast.Node {
    _ = self.advance();
    const operand_ptr = try self.allocator.create(ast.Node);
    operand_ptr.* = try parsePrimary(self);
    return ast.Node{ .unaryop = .{ .op = .USub, .operand = operand_ptr } };
}

fn parseUnaryPlus(self: *Parser) ParseError!ast.Node {
    _ = self.advance();
    const operand_ptr = try self.allocator.create(ast.Node);
    operand_ptr.* = try parsePrimary(self);
    return ast.Node{ .unaryop = .{ .op = .UAdd, .operand = operand_ptr } };
}

fn parseBitwiseNot(self: *Parser) ParseError!ast.Node {
    _ = self.advance();
    const operand_ptr = try self.allocator.create(ast.Node);
    operand_ptr.* = try parsePrimary(self);
    return ast.Node{ .unaryop = .{ .op = .Invert, .operand = operand_ptr } };
}
