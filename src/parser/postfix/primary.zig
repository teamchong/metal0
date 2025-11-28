const std = @import("std");
const ast = @import("ast");
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
            .Yield => return parseYieldExpr(self),
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

/// Strip underscores from numeric literal (Python allows 1_000_000)
fn stripUnderscores(input: []const u8, buf: []u8) []const u8 {
    var out_idx: usize = 0;
    for (input) |c| {
        if (c != '_') {
            if (out_idx < buf.len) {
                buf[out_idx] = c;
                out_idx += 1;
            }
        }
    }
    return buf[0..out_idx];
}

fn parseNumber(self: *Parser) ParseError!ast.Node {
    const num_tok = self.advance().?;
    const lexeme = num_tok.lexeme;

    // Buffer for stripping underscores (max reasonable number length)
    var buf: [64]u8 = undefined;

    // Detect base from prefix
    if (lexeme.len >= 2 and lexeme[0] == '0') {
        const prefix = lexeme[1];
        if (prefix == 'x' or prefix == 'X') {
            const clean = stripUnderscores(lexeme[2..], &buf);
            const int_val = std.fmt.parseInt(i64, clean, 16) catch 0;
            return ast.Node{ .constant = .{ .value = .{ .int = int_val } } };
        } else if (prefix == 'o' or prefix == 'O') {
            const clean = stripUnderscores(lexeme[2..], &buf);
            const int_val = std.fmt.parseInt(i64, clean, 8) catch 0;
            return ast.Node{ .constant = .{ .value = .{ .int = int_val } } };
        } else if (prefix == 'b' or prefix == 'B') {
            const clean = stripUnderscores(lexeme[2..], &buf);
            const int_val = std.fmt.parseInt(i64, clean, 2) catch 0;
            return ast.Node{ .constant = .{ .value = .{ .int = int_val } } };
        }
    }

    // Strip underscores for decimal parsing
    const clean = stripUnderscores(lexeme, &buf);

    // Try to parse as decimal int, fall back to float
    if (std.fmt.parseInt(i64, clean, 10)) |int_val| {
        return ast.Node{ .constant = .{ .value = .{ .int = int_val } } };
    } else |_| {
        const float_val = try std.fmt.parseFloat(f64, clean);
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
    var prev_allocated: ?[]const u8 = null; // Track previously allocated string for cleanup

    // Handle implicit string concatenation: "a" "b" -> "ab"
    // Also check for "a" f"b" which should become an f-string
    while (true) {
        var lookahead: usize = 0;
        while (self.current + lookahead < self.tokens.len and
            self.tokens[self.current + lookahead].type == .Newline)
        {
            lookahead += 1;
        }

        if (self.current + lookahead >= self.tokens.len) break;

        const next_type = self.tokens[self.current + lookahead].type;

        if (next_type == .String or next_type == .RawString) {
            self.skipNewlines();
            const next_str = self.advance().?;
            // Strip 'r' prefix if it's a raw string
            const next_content_raw = if (next_type == .RawString and next_str.lexeme.len > 0 and next_str.lexeme[0] == 'r')
                next_str.lexeme[1..]
            else
                next_str.lexeme;

            const first_content = if (result_str.len >= 2) result_str[0 .. result_str.len - 1] else result_str;
            const second_content = if (next_content_raw.len >= 2) next_content_raw[1..] else next_content_raw;

            const new_len = first_content.len + second_content.len;
            const new_str = try self.allocator.alloc(u8, new_len);
            @memcpy(new_str[0..first_content.len], first_content);
            @memcpy(new_str[first_content.len..], second_content);

            // Free the previous allocated string (if any)
            if (prev_allocated) |prev| {
                self.allocator.free(prev);
            }
            result_str = new_str;
            prev_allocated = new_str;
        } else if (next_type == .FString) {
            // String followed by f-string: "a" f"b{x}" -> becomes f-string
            // Convert current string content to f-string literal part, then delegate
            self.skipNewlines();

            // Strip quotes from current string
            const first_content = if (result_str.len >= 2) result_str[0 .. result_str.len - 1] else result_str;

            // Free any previously allocated string
            if (prev_allocated) |prev| {
                self.allocator.free(prev);
            }

            // Parse the f-string (which handles further concatenation)
            var fstring_node = try parseFString(self);

            // Prepend our string content as a literal part
            if (first_content.len > 0) {
                const old_parts = fstring_node.fstring.parts;
                const new_parts = try self.allocator.alloc(ast.FStringPart, old_parts.len + 1);
                new_parts[0] = .{ .literal = first_content };
                @memcpy(new_parts[1..], old_parts);
                self.allocator.free(old_parts);
                fstring_node.fstring.parts = new_parts;
            }

            return fstring_node;
        } else {
            break;
        }
    }

    // Track the final allocated string for cleanup when parser is deinitialized
    if (prev_allocated) |_| {
        self.allocated_strings.append(self.allocator, result_str) catch {};
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
    // Strip the 'r' prefix
    var result_str = if (str_tok.lexeme.len > 0 and str_tok.lexeme[0] == 'r')
        str_tok.lexeme[1..]
    else
        str_tok.lexeme;
    var prev_allocated: ?[]const u8 = null;

    // Handle implicit string concatenation: r"a" r"b" or r"a" "b" -> "ab"
    while (true) {
        var lookahead: usize = 0;
        while (self.current + lookahead < self.tokens.len and
            self.tokens[self.current + lookahead].type == .Newline)
        {
            lookahead += 1;
        }

        if (self.current + lookahead >= self.tokens.len) break;

        const next_type = self.tokens[self.current + lookahead].type;

        if (next_type == .RawString or next_type == .String) {
            self.skipNewlines();
            const next_str = self.advance().?;
            // Strip 'r' prefix if it's a raw string
            const next_content_raw = if (next_type == .RawString and next_str.lexeme.len > 0 and next_str.lexeme[0] == 'r')
                next_str.lexeme[1..]
            else
                next_str.lexeme;

            // Strip quotes: first_content is everything except trailing quote
            // second_content is everything except leading quote
            const first_content = if (result_str.len >= 2) result_str[0 .. result_str.len - 1] else result_str;
            const second_content = if (next_content_raw.len >= 2) next_content_raw[1..] else next_content_raw;

            const new_len = first_content.len + second_content.len;
            const new_str = try self.allocator.alloc(u8, new_len);
            @memcpy(new_str[0..first_content.len], first_content);
            @memcpy(new_str[first_content.len..], second_content);

            if (prev_allocated) |prev| {
                self.allocator.free(prev);
            }
            result_str = new_str;
            prev_allocated = new_str;
        } else if (next_type == .FString) {
            // Raw string followed by f-string
            self.skipNewlines();
            const first_content = if (result_str.len >= 2) result_str[0 .. result_str.len - 1] else result_str;

            if (prev_allocated) |prev| {
                self.allocator.free(prev);
            }

            var fstring_node = try parseFString(self);

            if (first_content.len > 0) {
                const old_parts = fstring_node.fstring.parts;
                const new_parts = try self.allocator.alloc(ast.FStringPart, old_parts.len + 1);
                new_parts[0] = .{ .literal = first_content };
                @memcpy(new_parts[1..], old_parts);
                self.allocator.free(old_parts);
                fstring_node.fstring.parts = new_parts;
            }

            return fstring_node;
        } else {
            break;
        }
    }

    if (prev_allocated) |_| {
        self.allocated_strings.append(self.allocator, result_str) catch {};
    }

    return ast.Node{ .constant = .{ .value = .{ .string = result_str } } };
}

fn parseFString(self: *Parser) ParseError!ast.Node {
    const fstr_tok = self.advance().?;
    const lexer_parts = fstr_tok.fstring_parts orelse &[_]lexer.FStringPart{};

    // Use ArrayList for dynamic sizing (to handle string concatenation)
    var parts_list = std.ArrayList(ast.FStringPart){};
    errdefer {
        for (parts_list.items) |*part| {
            switch (part.*) {
                .expr => |e| {
                    e.deinit(self.allocator);
                    self.allocator.destroy(e);
                },
                .format_expr => |fe| {
                    fe.expr.deinit(self.allocator);
                    self.allocator.destroy(fe.expr);
                },
                .conv_expr => |ce| {
                    ce.expr.deinit(self.allocator);
                    self.allocator.destroy(ce.expr);
                },
                .literal => {},
            }
        }
        parts_list.deinit(self.allocator);
    }

    // Convert initial f-string parts
    for (lexer_parts) |lexer_part| {
        try parts_list.append(self.allocator, try convertFStringPart(self, lexer_part));
    }

    // Handle implicit string concatenation: f"a" "b" or f"a" f"b"
    while (true) {
        // Skip newlines to find adjacent strings
        var lookahead: usize = 0;
        while (self.current + lookahead < self.tokens.len and
            self.tokens[self.current + lookahead].type == .Newline)
        {
            lookahead += 1;
        }

        if (self.current + lookahead >= self.tokens.len) break;

        const next_type = self.tokens[self.current + lookahead].type;
        if (next_type == .String) {
            // Concatenate regular string as a literal part
            self.skipNewlines();
            const str_tok = self.advance().?;
            // Strip quotes from string
            const content = if (str_tok.lexeme.len >= 2)
                str_tok.lexeme[1 .. str_tok.lexeme.len - 1]
            else
                str_tok.lexeme;
            try parts_list.append(self.allocator, .{ .literal = content });
        } else if (next_type == .FString) {
            // Concatenate another f-string's parts
            self.skipNewlines();
            const next_fstr = self.advance().?;
            const next_parts = next_fstr.fstring_parts orelse &[_]lexer.FStringPart{};
            for (next_parts) |lexer_part| {
                try parts_list.append(self.allocator, try convertFStringPart(self, lexer_part));
            }
        } else if (next_type == .RawString) {
            // Concatenate raw string as literal
            self.skipNewlines();
            const str_tok = self.advance().?;
            // Strip r prefix and quotes
            const stripped = if (str_tok.lexeme.len > 0 and str_tok.lexeme[0] == 'r')
                str_tok.lexeme[1..]
            else
                str_tok.lexeme;
            const content = if (stripped.len >= 2)
                stripped[1 .. stripped.len - 1]
            else
                stripped;
            try parts_list.append(self.allocator, .{ .literal = content });
        } else {
            break;
        }
    }

    const ast_parts = try parts_list.toOwnedSlice(self.allocator);
    parts_list = std.ArrayList(ast.FStringPart){}; // Reset to prevent double-free

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
    defer lexer.freeTokens(self.allocator, expr_tokens);

    var expr_parser = Parser.init(self.allocator, expr_tokens);
    defer expr_parser.deinit();

    var expr_node = try expr_parser.parseExpression();
    errdefer expr_node.deinit(self.allocator);
    return try self.allocNode(expr_node);
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
    var value = try parsePostfix(self);
    errdefer value.deinit(self.allocator);
    return ast.Node{ .await_expr = .{ .value = try self.allocNode(value) } };
}

/// Parse yield expression (used when yield appears inside parentheses or as part of larger expression)
fn parseYieldExpr(self: *Parser) ParseError!ast.Node {
    _ = self.advance(); // consume 'yield'

    // Check for "yield from expr" (PEP 380)
    if (self.match(.From)) {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        return ast.Node{ .yield_from_stmt = .{ .value = try self.allocNode(value) } };
    }

    // Check if there's a value expression - stop at ), ], }, newline, or comma
    const value_ptr: ?*ast.Node = blk: {
        if (self.peek()) |tok| {
            if (tok.type == .Newline or tok.type == .RParen or tok.type == .RBracket or
                tok.type == .RBrace or tok.type == .Comma)
            {
                break :blk null;
            }
        } else {
            break :blk null;
        }

        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        break :blk try self.allocNode(value);
    };

    return ast.Node{ .yield_stmt = .{ .value = value_ptr } };
}

fn parseGroupedOrTuple(self: *Parser) ParseError!ast.Node {
    _ = self.advance();

    // Check for empty tuple ()
    if (self.check(.RParen)) {
        _ = try self.expect(.RParen);
        return ast.Node{ .tuple = .{ .elts = &.{} } };
    }

    var first = try parseTupleElement(self);
    errdefer first.deinit(self.allocator);

    // Check for generator expression: (expr for x in items)
    if (self.check(.For)) {
        const genexp = try parseParenthesizedGenExpr(self, first);
        first = ast.Node{ .pass = {} }; // Ownership transferred
        _ = try self.expect(.RParen);
        return genexp;
    }

    // Check if it's a tuple (has comma) or grouped expression
    if (self.match(.Comma)) {
        var elements = std.ArrayList(ast.Node){};
        errdefer {
            for (elements.items) |*elem| elem.deinit(self.allocator);
            elements.deinit(self.allocator);
        }
        try elements.append(self.allocator, first);

        while (!self.check(.RParen)) {
            var elem = try parseTupleElement(self);
            errdefer elem.deinit(self.allocator);
            try elements.append(self.allocator, elem);
            if (!self.match(.Comma)) break;
        }

        _ = try self.expect(.RParen);

        const result = try elements.toOwnedSlice(self.allocator);
        elements = std.ArrayList(ast.Node){};
        return ast.Node{ .tuple = .{ .elts = result } };
    } else {
        _ = try self.expect(.RParen);
        return first;
    }
}

/// Parse tuple element - handles starred expressions like *args
fn parseTupleElement(self: *Parser) ParseError!ast.Node {
    // Handle *expr (starred expression for unpacking)
    if (self.match(.Star)) {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        return ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
    }
    return self.parseExpression();
}

/// Parse a comprehension target: single name or tuple of names (e.g., x or x, y)
fn parseComprehensionTarget(self: *Parser) ParseError!ast.Node {
    var first = try parsePrimary(self);
    errdefer first.deinit(self.allocator);

    // Check if there are more targets (tuple unpacking)
    if (!self.check(.Comma) or self.check(.In)) {
        return first;
    }

    // It's a tuple target like: x, y in items
    var elts = std.ArrayList(ast.Node){};
    errdefer {
        for (elts.items) |*e| e.deinit(self.allocator);
        elts.deinit(self.allocator);
    }

    try elts.append(self.allocator, first);
    first = ast.Node{ .pass = {} }; // Ownership transferred

    while (self.check(.Comma) and !self.check(.In)) {
        _ = self.advance(); // consume comma
        if (self.check(.In)) break; // trailing comma before 'in'
        var elem = try parsePrimary(self);
        errdefer elem.deinit(self.allocator);
        try elts.append(self.allocator, elem);
    }

    return ast.Node{
        .tuple = .{
            .elts = try elts.toOwnedSlice(self.allocator),
        },
    };
}

/// Parse generator expression inside parentheses: (expr for x in items [if cond])
fn parseParenthesizedGenExpr(self: *Parser, element: ast.Node) ParseError!ast.Node {
    var elt = element;
    errdefer elt.deinit(self.allocator);

    var generators = std.ArrayList(ast.Node.Comprehension){};
    errdefer {
        for (generators.items) |*g| {
            g.target.deinit(self.allocator);
            self.allocator.destroy(g.target);
            g.iter.deinit(self.allocator);
            self.allocator.destroy(g.iter);
            for (g.ifs) |*i| i.deinit(self.allocator);
            self.allocator.free(g.ifs);
        }
        generators.deinit(self.allocator);
    }

    while (self.match(.For)) {
        var target = try parseComprehensionTarget(self);
        errdefer target.deinit(self.allocator);

        _ = try self.expect(.In);

        var iter = try self.parseOrExpr();
        errdefer iter.deinit(self.allocator);

        var ifs = std.ArrayList(ast.Node){};
        errdefer {
            for (ifs.items) |*i| i.deinit(self.allocator);
            ifs.deinit(self.allocator);
        }

        while (self.check(.If) and !self.check(.For)) {
            _ = self.advance();
            var cond = try self.parseOrExpr();
            errdefer cond.deinit(self.allocator);
            try ifs.append(self.allocator, cond);
        }

        const ifs_slice = try ifs.toOwnedSlice(self.allocator);
        ifs = std.ArrayList(ast.Node){};

        try generators.append(self.allocator, ast.Node.Comprehension{
            .target = try self.allocNode(target),
            .iter = try self.allocNode(iter),
            .ifs = ifs_slice,
        });
    }

    const gens = try generators.toOwnedSlice(self.allocator);
    generators = std.ArrayList(ast.Node.Comprehension){};

    return ast.Node{
        .genexp = .{
            .elt = try self.allocNode(elt),
            .generators = gens,
        },
    };
}

fn parseUnaryMinus(self: *Parser) ParseError!ast.Node {
    _ = self.advance();
    var operand = try parsePrimary(self);
    errdefer operand.deinit(self.allocator);
    return ast.Node{ .unaryop = .{ .op = .USub, .operand = try self.allocNode(operand) } };
}

fn parseUnaryPlus(self: *Parser) ParseError!ast.Node {
    _ = self.advance();
    var operand = try parsePrimary(self);
    errdefer operand.deinit(self.allocator);
    return ast.Node{ .unaryop = .{ .op = .UAdd, .operand = try self.allocNode(operand) } };
}

fn parseBitwiseNot(self: *Parser) ParseError!ast.Node {
    _ = self.advance();
    var operand = try parsePrimary(self);
    errdefer operand.deinit(self.allocator);
    return ast.Node{ .unaryop = .{ .op = .Invert, .operand = try self.allocNode(operand) } };
}
