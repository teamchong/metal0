/// Miscellaneous statement parsing (return, assert, pass, break, continue, try, decorated, parseBlock)
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse an expression that can optionally be starred (*expr)
/// Used in implicit tuples like `return 1, *z` or `yield a, *b` or `for x in *a, *b:`
pub fn parseStarredExpr(self: *Parser) ParseError!ast.Node {
    if (self.match(.Star)) {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        return ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
    }
    return self.parseExpression();
}

pub fn parseReturn(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Return);

    // Check if there's a return value
    const value_ptr: ?*ast.Node = if (self.peek()) |tok| blk: {
        if (tok.type == .Newline) break :blk null;

        var first_value = try self.parseExpression();
        errdefer first_value.deinit(self.allocator);

        // Check for comma - if present, this is an implicit tuple: return a, b, c
        if (self.match(.Comma)) {
            var elements = std.ArrayList(ast.Node){};
            errdefer {
                for (elements.items) |*e| e.deinit(self.allocator);
                elements.deinit(self.allocator);
            }

            try elements.append(self.allocator, first_value);

            // Parse remaining elements (can include starred: return 1, *z)
            while (true) {
                if (self.peek()) |next_tok| {
                    if (next_tok.type == .Newline or next_tok.type == .Eof) break;
                } else break;

                var elem = try parseStarredExpr(self);
                errdefer elem.deinit(self.allocator);
                try elements.append(self.allocator, elem);
                if (!self.match(.Comma)) break;
            }

            const elts = try elements.toOwnedSlice(self.allocator);
            elements = std.ArrayList(ast.Node){};
            break :blk try self.allocNode(ast.Node{ .tuple = .{ .elts = elts } });
        } else {
            break :blk try self.allocNode(first_value);
        }
    } else null;

    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);

    return ast.Node{ .return_stmt = .{ .value = value_ptr } };
}

/// Parse assert statement: assert condition or assert condition, message
pub fn parseAssert(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Assert);

    var condition = try self.parseExpression();
    errdefer condition.deinit(self.allocator);

    // Check for optional message after comma
    var msg: ?ast.Node = null;
    if (self.match(.Comma)) {
        msg = try self.parseExpression();
    }
    errdefer if (msg) |*m| m.deinit(self.allocator);

    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);

    return ast.Node{
        .assert_stmt = .{
            .condition = try self.allocNode(condition),
            .msg = try self.allocNodeOpt(msg),
        },
    };
}

pub fn parseBlock(self: *Parser) ParseError![]ast.Node {
    var statements = std.ArrayList(ast.Node){};
    errdefer {
        // Clean up already parsed statements on error
        for (statements.items) |*stmt| {
            stmt.deinit(self.allocator);
        }
        statements.deinit(self.allocator);
    }

    while (true) {
        if (self.peek()) |tok| {
            if (tok.type == .Dedent or tok.type == .Eof) break;
        } else break;

        if (self.match(.Newline)) continue;

        const stmt = try self.parseStatement();
        try statements.append(self.allocator, stmt);
    }

    // Success - transfer ownership
    const result = try statements.toOwnedSlice(self.allocator);
    statements = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free
    return result;
}

pub fn parseTry(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Try);
    _ = try self.expect(.Colon);

    // Track allocations for cleanup on error
    var body_alloc: ?[]ast.Node = null;
    var handlers = std.ArrayList(ast.Node.ExceptHandler){};
    var else_body_alloc: ?[]ast.Node = null;
    var finally_body_alloc: ?[]ast.Node = null;

    errdefer {
        // Clean up body
        if (body_alloc) |b| {
            for (b) |*stmt| stmt.deinit(self.allocator);
            self.allocator.free(b);
        }
        // Clean up handlers
        for (handlers.items) |handler| {
            for (handler.body) |*stmt| stmt.deinit(self.allocator);
            self.allocator.free(handler.body);
        }
        handlers.deinit(self.allocator);
        // Clean up else body
        if (else_body_alloc) |b| {
            for (b) |*stmt| stmt.deinit(self.allocator);
            self.allocator.free(b);
        }
        // Clean up finally body
        if (finally_body_alloc) |b| {
            for (b) |*stmt| stmt.deinit(self.allocator);
            self.allocator.free(b);
        }
    }

    // Parse try block body - check for one-liner (any token that's not Newline)
    if (self.peek()) |next_tok| {
        const is_oneliner = next_tok.type != .Newline;

        if (is_oneliner) {
            const stmt = try self.parseStatement();
            const body_slice = try self.allocator.alloc(ast.Node, 1);
            body_slice[0] = stmt;
            body_alloc = body_slice;
        } else {
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);
            body_alloc = try parseBlock(self);
            _ = try self.expect(.Dedent);
        }
    } else {
        return ParseError.UnexpectedEof;
    }

    while (self.match(.Except)) {
        // Check for except* (PEP 654 ExceptionGroup handling)
        const is_star_except = self.match(.Star);
        _ = is_star_except; // We parse it the same way, just note it's except*

        // Check for exception type: except ValueError: or except (Exception) as e:
        // Also handles dotted types: except click.BadParameter:
        // Python allows any expression (e.g., except 42:) - it will raise TypeError at runtime
        var exc_type: ?[]const u8 = null;
        if (self.peek()) |tok| {
            // Handle non-identifier expressions like numbers (except 42:)
            // These are valid syntax even if they raise TypeError at runtime
            if (tok.type == .Number) {
                exc_type = tok.lexeme;
                _ = self.advance();
            } else if (tok.type == .Ident) {
                // Check for dotted exception type: click.BadParameter
                var type_name = tok.lexeme;
                _ = self.advance();

                // Handle dotted names
                while (self.peek()) |next_tok| {
                    if (next_tok.type == .Dot) {
                        _ = self.advance(); // consume '.'
                        if (self.peek()) |name_tok| {
                            if (name_tok.type == .Ident) {
                                // For now, just use the last part of the dotted name
                                type_name = name_tok.lexeme;
                                _ = self.advance();
                            } else break;
                        } else break;
                    } else break;
                }
                exc_type = type_name;

                // Handle function call: except type(stop_exc) as e:
                // Parse but skip the arguments - we just keep the function name
                if (self.peek()) |next_tok| {
                    if (next_tok.type == .LParen) {
                        _ = self.advance(); // consume '('
                        var paren_depth: usize = 1;
                        while (paren_depth > 0) {
                            if (self.peek()) |inner_tok| {
                                if (inner_tok.type == .LParen) {
                                    paren_depth += 1;
                                } else if (inner_tok.type == .RParen) {
                                    paren_depth -= 1;
                                }
                                _ = self.advance();
                            } else break;
                        }
                    } else if (next_tok.type == .LBracket) {
                        // Handle subscript: except Signals[self.decimal] as e:
                        _ = self.advance(); // consume '['
                        var bracket_depth: usize = 1;
                        while (bracket_depth > 0) {
                            if (self.peek()) |inner_tok| {
                                if (inner_tok.type == .LBracket) {
                                    bracket_depth += 1;
                                } else if (inner_tok.type == .RBracket) {
                                    bracket_depth -= 1;
                                }
                                _ = self.advance();
                            } else break;
                        }
                    }
                }

                // Handle comma-separated exception types without parens: except EOFError, TypeError, ZeroDivisionError:
                while (self.match(.Comma)) {
                    // Skip dotted exception type
                    while (self.peek()) |next_type| {
                        if (next_type.type == .Ident) {
                            _ = self.advance();
                            // Skip dots in the name
                            if (!self.match(.Dot)) break;
                        } else break;
                    }
                }
                // Handle "or" in exception types: except Exception or Exception:
                while (self.match(.Or)) {
                    // Skip dotted exception type
                    while (self.peek()) |next_type| {
                        if (next_type.type == .Ident) {
                            _ = self.advance();
                            // Skip dots in the name
                            if (!self.match(.Dot)) break;
                        } else break;
                    }
                }
            } else if (tok.type == .LParen) {
                // Parenthesized exception type: except (Exception) as e:
                // or except (ValueError, TypeError) as e:
                // or except (OSError, subprocess.SubprocessError) as e:
                _ = self.advance(); // consume '('
                if (self.peek()) |inner_tok| {
                    if (inner_tok.type == .Ident) {
                        exc_type = inner_tok.lexeme;
                        _ = self.advance();
                        // Skip dotted name parts: subprocess.SubprocessError
                        while (self.match(.Dot)) {
                            if (self.peek()) |dot_tok| {
                                if (dot_tok.type == .Ident) {
                                    exc_type = dot_tok.lexeme;
                                    _ = self.advance();
                                }
                            }
                        }
                        // Skip any additional types in tuple (for now just use first)
                        while (self.match(.Comma)) {
                            // Skip dotted exception type or number literal
                            while (self.peek()) |next_type| {
                                if (next_type.type == .Ident) {
                                    _ = self.advance();
                                    // Skip dots in the name
                                    if (!self.match(.Dot)) break;
                                } else if (next_type.type == .Number) {
                                    // Allow number literals like (ValueError, 42)
                                    _ = self.advance();
                                    break;
                                } else break;
                            }
                        }
                    } else if (inner_tok.type == .Number) {
                        // Handle tuple starting with number: except (42,):
                        exc_type = inner_tok.lexeme;
                        _ = self.advance();
                        // Skip any additional elements
                        while (self.match(.Comma)) {
                            if (self.peek()) |next_type| {
                                if (next_type.type == .Ident or next_type.type == .Number) {
                                    _ = self.advance();
                                    while (self.match(.Dot)) {
                                        if (self.check(.Ident)) _ = self.advance();
                                    }
                                }
                            }
                        }
                    }
                }
                _ = try self.expect(.RParen);
            }
        }

        // Check for optional "as variable"
        var exc_name: ?[]const u8 = null;
        if (self.match(.As)) {
            const name_tok = try self.expect(.Ident);
            exc_name = name_tok.lexeme;
        }

        _ = try self.expect(.Colon);

        // Parse except body - check for one-liner
        var handler_body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
                next_tok.type == .Ellipsis or
                next_tok.type == .Return or
                next_tok.type == .Break or
                next_tok.type == .Continue or
                next_tok.type == .Raise or
                next_tok.type == .Assert or
                next_tok.type == .Global or
                next_tok.type == .Nonlocal or
                next_tok.type == .Import or
                next_tok.type == .From or
                next_tok.type == .Del or
                next_tok.type == .Yield or
                next_tok.type == .Number or // for expressions like 1/0
                next_tok.type == .LParen or // for (expr)
                next_tok.type == .LBracket or // for [expr]
                next_tok.type == .LBrace or // for {expr}
                next_tok.type == .String or // for string expressions
                next_tok.type == .FString or // for f-strings
                next_tok.type == .Not or // for not expr
                next_tok.type == .Minus or // for -expr
                next_tok.type == .Plus or // for +expr
                next_tok.type == .Tilde or // for ~expr
                next_tok.type == .Lambda or // for lambda
                next_tok.type == .Await or // for await expr
                next_tok.type == .Star or // for *expr
                next_tok.type == .Ident; // for assignments and expressions

            if (is_oneliner) {
                const stmt = try self.parseStatement();
                const handler_slice = try self.allocator.alloc(ast.Node, 1);
                handler_slice[0] = stmt;
                handler_body = handler_slice;
            } else {
                _ = try self.expect(.Newline);
                _ = try self.expect(.Indent);
                handler_body = try parseBlock(self);
                _ = try self.expect(.Dedent);
            }
        } else {
            return ParseError.UnexpectedEof;
        }

        try handlers.append(self.allocator, ast.Node.ExceptHandler{
            .type = exc_type,
            .name = exc_name,
            .body = handler_body,
        });
    }

    // Parse optional else block (runs if no exception)
    if (self.match(.Else)) {
        _ = try self.expect(.Colon);

        // Check if this is a one-liner else: statement
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type != .Newline;
            if (is_oneliner) {
                const stmt = try self.parseStatement();
                const body_slice = try self.allocator.alloc(ast.Node, 1);
                body_slice[0] = stmt;
                else_body_alloc = body_slice;
            } else {
                _ = try self.expect(.Newline);
                _ = try self.expect(.Indent);
                else_body_alloc = try parseBlock(self);
                _ = try self.expect(.Dedent);
            }
        }
    }

    // Parse optional finally block
    if (self.match(.Finally)) {
        _ = try self.expect(.Colon);

        // Check if this is a one-liner finally: statement
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type != .Newline;
            if (is_oneliner) {
                const stmt = try self.parseStatement();
                const body_slice = try self.allocator.alloc(ast.Node, 1);
                body_slice[0] = stmt;
                finally_body_alloc = body_slice;
            } else {
                _ = try self.expect(.Newline);
                _ = try self.expect(.Indent);
                finally_body_alloc = try parseBlock(self);
                _ = try self.expect(.Dedent);
            }
        }
    }

    // Success - transfer ownership
    const final_body = body_alloc.?;
    body_alloc = null;
    const final_handlers = try handlers.toOwnedSlice(self.allocator);
    handlers = std.ArrayList(ast.Node.ExceptHandler){};
    const final_else: []ast.Node = else_body_alloc orelse try self.allocator.alloc(ast.Node, 0);
    else_body_alloc = null;
    const final_finally: []ast.Node = finally_body_alloc orelse try self.allocator.alloc(ast.Node, 0);
    finally_body_alloc = null;

    return ast.Node{
        .try_stmt = .{
            .body = final_body,
            .handlers = final_handlers,
            .else_body = final_else,
            .finalbody = final_finally,
        },
    };
}

pub fn parseRaise(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Raise);

    var exc: ?ast.Node = null;
    var cause: ?ast.Node = null;

    // Check if there's an exception expression
    if (self.peek()) |tok| {
        if (tok.type != .Newline) {
            exc = try self.parseExpression();
            errdefer if (exc) |*e| e.deinit(self.allocator);

            // Check for "from" clause: raise X from Y
            if (self.peek()) |next_tok| {
                if (next_tok.type == .From) {
                    _ = self.advance(); // consume 'from'
                    cause = try self.parseExpression();
                }
            }
        }
    }
    errdefer if (cause) |*c| c.deinit(self.allocator);

    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);

    return ast.Node{
        .raise_stmt = .{
            .exc = try self.allocNodeOpt(exc),
            .cause = try self.allocNodeOpt(cause),
        },
    };
}

pub fn parsePass(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Pass);
    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);
    return ast.Node{ .pass = {} };
}

pub fn parseBreak(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Break);
    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);
    return ast.Node{ .break_stmt = {} };
}

pub fn parseContinue(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Continue);
    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);
    return ast.Node{ .continue_stmt = {} };
}

pub fn parseYield(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Yield);

    // Check for "yield from expr" (PEP 380)
    if (self.match(.From)) {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        // Accept either newline or semicolon as statement terminator
        if (!self.match(.Newline)) _ = self.match(.Semicolon);
        return ast.Node{ .yield_from_stmt = .{ .value = try self.allocNode(value) } };
    }

    // Check if there's a value expression
    const value_ptr: ?*ast.Node = if (self.peek()) |tok| blk: {
        if (tok.type == .Newline) break :blk null;

        var first_value = try self.parseExpression();
        errdefer first_value.deinit(self.allocator);

        // Check if this is a tuple: yield a, b, c
        if (self.check(.Comma)) {
            var value_list = std.ArrayList(ast.Node){};
            errdefer {
                for (value_list.items) |*v| v.deinit(self.allocator);
                value_list.deinit(self.allocator);
            }
            try value_list.append(self.allocator, first_value);

            while (self.match(.Comma)) {
                // Check for trailing comma (next token is statement terminator)
                if (self.check(.Newline) or self.check(.Semicolon) or self.check(.Eof)) {
                    break;
                }
                var val = try parseStarredExpr(self);
                errdefer val.deinit(self.allocator);
                try value_list.append(self.allocator, val);
            }

            const value_array = try value_list.toOwnedSlice(self.allocator);
            value_list = std.ArrayList(ast.Node){};
            break :blk try self.allocNode(ast.Node{ .tuple = .{ .elts = value_array } });
        } else {
            break :blk try self.allocNode(first_value);
        }
    } else null;

    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);

    return ast.Node{ .yield_stmt = .{ .value = value_ptr } };
}

pub fn parseEllipsis(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Ellipsis);
    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);
    return ast.Node{ .ellipsis_literal = {} };
}

pub fn parseDecorated(self: *Parser) ParseError!ast.Node {
    // Parse decorators: @decorator_name or @decorator_func(args)
    var decorators = std.ArrayList(ast.Node){};
    errdefer {
        // Clean up decorators on error
        for (decorators.items) |*d| {
            d.deinit(self.allocator);
        }
        decorators.deinit(self.allocator);
    }

    while (self.match(.At)) {
        // Parse decorator expression (name or call)
        const decorator = try self.parseExpression();
        try decorators.append(self.allocator, decorator);
        _ = try self.expect(.Newline);
    }

    // Parse the decorated function/class
    var decorated_node = try self.parseStatement();

    // Attach decorators to function definition
    if (decorated_node == .function_def) {
        const decorators_slice = try decorators.toOwnedSlice(self.allocator);
        decorators = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free
        decorated_node.function_def.decorators = decorators_slice;
    } else {
        // If not a function, just free the decorators
        for (decorators.items) |*d| {
            d.deinit(self.allocator);
        }
        decorators.deinit(self.allocator);
    }

    return decorated_node;
}

/// Parse global statement: global x, y, z
pub fn parseGlobal(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Global);

    var names = std.ArrayList([]const u8){};
    defer names.deinit(self.allocator);

    // Parse first identifier
    const first_tok = try self.expect(.Ident);
    try names.append(self.allocator, first_tok.lexeme);

    // Parse additional identifiers separated by commas
    while (self.match(.Comma)) {
        const tok = try self.expect(.Ident);
        try names.append(self.allocator, tok.lexeme);
    }

    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);

    return ast.Node{
        .global_stmt = .{
            .names = try names.toOwnedSlice(self.allocator),
        },
    };
}

/// Parse nonlocal statement: nonlocal x, y, z
pub fn parseNonlocal(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Nonlocal);

    var names = std.ArrayList([]const u8){};
    defer names.deinit(self.allocator);

    // Parse first identifier
    const first_tok = try self.expect(.Ident);
    try names.append(self.allocator, first_tok.lexeme);

    // Parse additional identifiers separated by commas
    while (self.match(.Comma)) {
        const tok = try self.expect(.Ident);
        try names.append(self.allocator, tok.lexeme);
    }

    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);

    return ast.Node{
        .nonlocal_stmt = .{
            .names = try names.toOwnedSlice(self.allocator),
        },
    };
}

/// Parse del statement: del x or del x, y or del obj.attr
pub fn parseDel(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Del);

    var targets = std.ArrayList(ast.Node){};
    errdefer {
        for (targets.items) |*t| t.deinit(self.allocator);
        targets.deinit(self.allocator);
    }

    // Parse first target
    var first_target = try self.parseExpression();
    errdefer first_target.deinit(self.allocator);
    try targets.append(self.allocator, first_target);

    // Parse additional targets separated by commas
    // Support trailing comma: `del y,` is valid (single-element tuple)
    while (self.match(.Comma)) {
        // Check for trailing comma (next token is statement terminator)
        if (self.check(.Newline) or self.check(.Semicolon) or self.check(.Eof)) {
            break;
        }
        var target = try self.parseExpression();
        errdefer target.deinit(self.allocator);
        try targets.append(self.allocator, target);
    }

    // Accept either newline or semicolon as statement terminator
    if (!self.match(.Newline)) _ = self.match(.Semicolon);

    // Success - transfer ownership
    const result = try targets.toOwnedSlice(self.allocator);
    targets = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free

    return ast.Node{
        .del_stmt = .{
            .targets = result,
        },
    };
}

/// Context manager info for multi-context with statements
const ContextManager = struct {
    expr: ast.Node,
    target: ?*ast.Node, // Target node: name, tuple, list, attribute, etc.
};

/// Parse with statement: with expr as var: body
/// Also supports multiple context managers: with ctx1, ctx2 as var: body
/// Python 3.10+: with (ctx1 as var1, ctx2 as var2):
/// Multiple context managers are transformed into nested with statements.
pub fn parseWith(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.With);

    // Check for parenthesized context managers (Python 3.10+)
    const has_parens = self.match(.LParen);

    // Collect all context managers
    var contexts = std.ArrayList(ContextManager){};
    defer {
        // Free any remaining context expressions on error
        for (contexts.items) |*ctx| {
            ctx.expr.deinit(self.allocator);
        }
        contexts.deinit(self.allocator);
    }

    // Parse first context expression
    const context_expr = try self.parseExpression();
    var optional_target: ?*ast.Node = null;

    // Check for optional "as target"
    if (self.match(.As)) {
        optional_target = try parseAsTarget(self);
    }

    try contexts.append(self.allocator, .{ .expr = context_expr, .target = optional_target });

    // Handle additional context managers
    while (self.match(.Comma)) {
        // Allow trailing comma in parenthesized form
        if (has_parens and self.check(.RParen)) break;

        const next_expr = try self.parseExpression();
        var next_target: ?*ast.Node = null;

        if (self.match(.As)) {
            next_target = try parseAsTarget(self);
        }

        try contexts.append(self.allocator, .{ .expr = next_expr, .target = next_target });
    }

    // Close parenthesis for Python 3.10+ syntax
    if (has_parens) {
        _ = try self.expect(.RParen);
    }

    _ = try self.expect(.Colon);

    // Parse body
    const body = if (self.peek()) |next_tok| blk: {
        const is_oneliner = next_tok.type == .Pass or
            next_tok.type == .Ellipsis or
            next_tok.type == .Return or
            next_tok.type == .Break or
            next_tok.type == .Continue or
            next_tok.type == .Raise or
            next_tok.type == .Assert or
            next_tok.type == .Global or
            next_tok.type == .Nonlocal or
            next_tok.type == .Import or
            next_tok.type == .From or
            next_tok.type == .Del or
            next_tok.type == .Yield or
            next_tok.type == .Ident;

        if (is_oneliner) {
            const stmt = try self.parseStatement();
            const body_slice = try self.allocator.alloc(ast.Node, 1);
            body_slice[0] = stmt;
            break :blk body_slice;
        } else {
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);
            const b = try parseBlock(self);
            _ = try self.expect(.Dedent);
            break :blk b;
        }
    } else return ParseError.UnexpectedEof;

    // Build nested with statements from innermost to outermost
    // with A, B, C: body -> with A: with B: with C: body
    const ctx_slice = contexts.items;
    if (ctx_slice.len == 0) return ParseError.UnexpectedToken;

    // Start with innermost (last) context manager containing the actual body
    var i = ctx_slice.len - 1;
    var current_body = body;

    while (true) {
        const ctx = ctx_slice[i];
        const expr_copy = ctx.expr;

        const with_node = ast.Node{
            .with_stmt = .{
                .context_expr = try self.allocNode(expr_copy),
                .optional_vars = ctx.target,
                .body = current_body,
            },
        };

        if (i == 0) {
            // Clear contexts so defer doesn't double-free (ownership transferred)
            contexts.clearRetainingCapacity();
            return with_node;
        }

        // Wrap in a new body for the outer with
        const body_slice = try self.allocator.alloc(ast.Node, 1);
        body_slice[0] = with_node;
        current_body = body_slice;

        i -= 1;
    }
}

/// Parse a target element, handling starred expressions (*rest)
fn parseTargetElem(self: *Parser) ParseError!ast.Node {
    if (self.match(.Star)) {
        var value = try self.parsePostfix();
        errdefer value.deinit(self.allocator);
        return ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
    }
    return try self.parseExpression();
}

/// Parse "as target" part of with statement, returning the full target node
fn parseAsTarget(self: *Parser) ParseError!?*ast.Node {
    if (self.peek()) |tok| {
        if (tok.type == .Ident) {
            // Could be simple name or attribute access - parse as expression
            const target = try self.parsePostfix();
            return try self.allocNode(target);
        } else if (tok.type == .LParen) {
            // Tuple target: as (a, *b, c)
            _ = self.advance(); // consume (
            var elts = std.ArrayList(ast.Node){};
            errdefer {
                for (elts.items) |*e| e.deinit(self.allocator);
                elts.deinit(self.allocator);
            }

            // Parse first element
            if (!self.check(.RParen)) {
                const first = try parseTargetElem(self);
                try elts.append(self.allocator, first);

                // Parse remaining elements
                while (self.match(.Comma)) {
                    if (self.check(.RParen)) break; // trailing comma
                    const elt = try parseTargetElem(self);
                    try elts.append(self.allocator, elt);
                }
            }

            _ = try self.expect(.RParen);
            const elts_slice = try elts.toOwnedSlice(self.allocator);
            return try self.allocNode(ast.Node{ .tuple = .{ .elts = elts_slice } });
        } else if (tok.type == .LBracket) {
            // List target: as [a, *b, c]
            _ = self.advance(); // consume [
            var elts = std.ArrayList(ast.Node){};
            errdefer {
                for (elts.items) |*e| e.deinit(self.allocator);
                elts.deinit(self.allocator);
            }

            // Parse first element
            if (!self.check(.RBracket)) {
                const first = try parseTargetElem(self);
                try elts.append(self.allocator, first);

                // Parse remaining elements
                while (self.match(.Comma)) {
                    if (self.check(.RBracket)) break; // trailing comma
                    const elt = try parseTargetElem(self);
                    try elts.append(self.allocator, elt);
                }
            }

            _ = try self.expect(.RBracket);
            const elts_slice = try elts.toOwnedSlice(self.allocator);
            return try self.allocNode(ast.Node{ .list = .{ .elts = elts_slice } });
        }
    }
    return null;
}

/// Parse async statement: async def, async for, async with
pub fn parseAsync(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Async);

    // Check what follows async
    if (self.peek()) |tok| {
        switch (tok.type) {
            .Def => {
                // async def - delegate to parseFunctionDef which handles async
                // But we already consumed 'async', so we need a different approach
                return try parseAsyncFunctionDef(self);
            },
            .For => {
                // async for - parse as regular for with is_async=true
                return try parseAsyncFor(self);
            },
            .With => {
                // async with - parse as regular with with is_async=true
                return try parseAsyncWith(self);
            },
            else => {
                std.debug.print("Expected def, for, or with after async, got {s}\n", .{@tagName(tok.type)});
                return error.UnexpectedToken;
            },
        }
    }
    return error.UnexpectedEof;
}

/// Parse async function definition (async already consumed)
fn parseAsyncFunctionDef(self: *Parser) ParseError!ast.Node {
    const definitions = @import("definitions.zig");
    return definitions.parseFunctionDefInternal(self, true);
}

/// Parse async for loop
fn parseAsyncFor(self: *Parser) ParseError!ast.Node {
    const control = @import("control.zig");
    return control.parseForInternal(self, true);
}

/// Parse async with statement
fn parseAsyncWith(self: *Parser) ParseError!ast.Node {
    // Same as parseWith but for async context (we just parse it the same way)
    return try parseWith(self);
}

/// Parse PEP 695 type alias: type X = SomeType
/// or with type params: type X[T] = list[T]
pub fn parseTypeAlias(self: *Parser) ParseError!ast.Node {
    // Consume "type" soft keyword (it's an Ident)
    _ = try self.expect(.Ident);
    // Get the alias name
    const name_tok = try self.expect(.Ident);

    // Parse optional type parameters: type X[T, U] = ...
    if (self.match(.LBracket)) {
        var bracket_depth: usize = 1;
        while (bracket_depth > 0) {
            if (self.match(.LBracket)) {
                bracket_depth += 1;
            } else if (self.match(.RBracket)) {
                bracket_depth -= 1;
            } else {
                _ = self.advance();
            }
        }
    }

    _ = try self.expect(.Eq);

    // Parse the type expression (we just skip it for now)
    var value = try self.parseExpression();
    errdefer value.deinit(self.allocator);

    _ = self.match(.Newline);

    // Return as a pass statement for now (type aliases are erased at runtime in our codegen)
    _ = name_tok;
    value.deinit(self.allocator);
    return ast.Node{ .pass = {} };
}

/// Parse match statement (PEP 634): match subject:
pub fn parseMatch(self: *Parser) ParseError!ast.Node {
    // Consume "match" soft keyword (it's an Ident)
    _ = try self.expect(.Ident);

    // Parse the subject expression
    var subject = try self.parseExpression();
    // Check for tuple subject: match x, y:  or match x,:
    if (self.check(.Comma)) {
        var elts = std.ArrayList(ast.Node){};
        try elts.append(self.allocator, subject);
        while (self.match(.Comma)) {
            if (self.check(.Colon)) break;
            const next = try self.parseExpression();
            try elts.append(self.allocator, next);
        }
        subject = ast.Node{ .tuple = .{ .elts = try elts.toOwnedSlice(self.allocator) } };
    }
    const subject_ptr = try self.allocNode(subject);
    errdefer self.allocator.destroy(subject_ptr);

    _ = try self.expect(.Colon);
    _ = try self.expect(.Newline);
    _ = try self.expect(.Indent);

    // Parse case clauses
    var cases = std.ArrayList(ast.Node.MatchCase){};
    errdefer {
        for (cases.items) |*c| {
            for (c.body) |*stmt| stmt.deinit(self.allocator);
            self.allocator.free(c.body);
        }
        cases.deinit(self.allocator);
    }

    while (!self.check(.Dedent)) {
        // Each case starts with "case" keyword (which is an Ident)
        if (self.peek()) |tok| {
            if (tok.type == .Ident and std.mem.eql(u8, tok.lexeme, "case")) {
                _ = self.advance(); // consume "case"
            } else {
                break;
            }
        } else {
            break;
        }

        // Parse pattern
        var pattern = try parseMatchPattern(self);

        // Check for top-level or-pattern: case {0: x} | {1: y} | []:
        if (self.check(.Pipe)) {
            var patterns = std.ArrayList(ast.Node.MatchPattern){};
            try patterns.append(self.allocator, pattern);
            while (self.match(.Pipe)) {
                const next = try parseMatchPattern(self);
                try patterns.append(self.allocator, next);
            }
            pattern = ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
        }

        // Check for implicit tuple pattern: case 0, *x:
        if (self.check(.Comma)) {
            var patterns = std.ArrayList(ast.Node.MatchPattern){};
            try patterns.append(self.allocator, pattern);
            while (self.match(.Comma)) {
                // Don't consume if followed by guard or colon
                if (self.check(.If) or self.check(.Colon)) break;
                const next = try parseMatchPattern(self);
                try patterns.append(self.allocator, next);
            }
            pattern = ast.Node.MatchPattern{ .sequence = try patterns.toOwnedSlice(self.allocator) };
        }

        // Check for guard: case x if condition:
        var guard: ?*ast.Node = null;
        if (self.peek()) |tok| {
            if (tok.type == .If) {
                _ = self.advance(); // consume "if"
                const guard_expr = try self.parseExpression();
                guard = try self.allocNode(guard_expr);
            }
        }

        _ = try self.expect(.Colon);

        // Parse case body
        var body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
                next_tok.type == .Ellipsis or
                next_tok.type == .Return or
                next_tok.type == .Break or
                next_tok.type == .Continue or
                next_tok.type == .Raise or
                next_tok.type == .Assert or
                next_tok.type == .Global or
                next_tok.type == .Nonlocal or
                next_tok.type == .Import or
                next_tok.type == .From or
                next_tok.type == .Del or
                next_tok.type == .Yield or
                next_tok.type == .Ident;

            if (is_oneliner) {
                const stmt = try self.parseStatement();
                const body_slice = try self.allocator.alloc(ast.Node, 1);
                body_slice[0] = stmt;
                body = body_slice;
            } else {
                _ = try self.expect(.Newline);
                _ = try self.expect(.Indent);
                body = try parseBlock(self);
                _ = try self.expect(.Dedent);
            }
        } else {
            return ParseError.UnexpectedEof;
        }

        try cases.append(self.allocator, ast.Node.MatchCase{
            .pattern = pattern,
            .guard = guard,
            .body = body,
        });
    }

    _ = try self.expect(.Dedent);

    const cases_slice = try cases.toOwnedSlice(self.allocator);

    return ast.Node{ .match_stmt = .{
        .subject = subject_ptr,
        .cases = cases_slice,
    } };
}

/// Parse a match pattern
fn parseMatchPattern(self: *Parser) ParseError!ast.Node.MatchPattern {
    // Check for wildcard pattern: case _ or case _ as name
    if (self.peek()) |tok| {
        if (tok.type == .Ident and std.mem.eql(u8, tok.lexeme, "_")) {
            _ = self.advance();
            // Check for as-pattern: _ as name
            if (self.match(.As)) {
                const name_tok = try self.expect(.Ident);
                const wildcard_pattern = try self.allocator.create(ast.Node.MatchPattern);
                wildcard_pattern.* = .{ .wildcard = {} };
                return ast.Node.MatchPattern{
                    .as_pattern = .{
                        .pattern = wildcard_pattern,
                        .name = name_tok.lexeme,
                    },
                };
            }
            return ast.Node.MatchPattern{ .wildcard = {} };
        }
    }

    // Check for literal patterns: case 1, case "hello", case True, case None
    if (self.peek()) |tok| {
        switch (tok.type) {
            .Star => {
                // Star pattern: *x in sequence/tuple patterns
                _ = self.advance(); // consume *
                if (self.peek()) |name_tok| {
                    if (name_tok.type == .Ident) {
                        const name = name_tok.lexeme;
                        _ = self.advance();
                        // *_ is wildcard, *name captures rest
                        if (std.mem.eql(u8, name, "_")) {
                            return ast.Node.MatchPattern{ .wildcard = {} };
                        }
                        return ast.Node.MatchPattern{ .capture = name };
                    }
                }
                return ast.Node.MatchPattern{ .wildcard = {} };
            },
            .Number, .String, .True, .False, .None, .ComplexNumber => {
                var lit = try self.parsePrimary();
                // Handle complex number literals: case 0 + 0j, case 1 - 1j
                if (self.peek()) |next_tok| {
                    if (next_tok.type == .Plus or next_tok.type == .Minus) {
                        // Check if followed by imaginary number
                        if (self.current + 1 < self.tokens.len) {
                            const after_op = self.tokens[self.current + 1];
                            if (after_op.type == .ComplexNumber) {
                                // Parse as binary expression: 0 + 0j
                                const op = self.advance().?;
                                const right = try self.parsePrimary();
                                const left_ptr = try self.allocNode(lit);
                                const right_ptr = try self.allocNode(right);
                                lit = ast.Node{
                                    .binop = .{
                                        .left = left_ptr,
                                        .op = if (op.type == .Plus) .Add else .Sub,
                                        .right = right_ptr,
                                    },
                                };
                            }
                        }
                    }
                }
                const lit_ptr = try self.allocNode(lit);
                const pattern = ast.Node.MatchPattern{ .literal = lit_ptr };
                // Check for or-pattern: case 1 | 2 | 3
                if (self.check(.Pipe)) {
                    var patterns = std.ArrayList(ast.Node.MatchPattern){};
                    try patterns.append(self.allocator, pattern);
                    while (self.match(.Pipe)) {
                        // Parse just the literal, not full pattern (no recursive or/as)
                        const next_lit = try self.parsePrimary();
                        const next_lit_ptr = try self.allocNode(next_lit);
                        try patterns.append(self.allocator, .{ .literal = next_lit_ptr });
                    }
                    const or_pattern = ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
                    // Check for as-pattern: case 0 | 1 | 2 as z
                    if (self.match(.As)) {
                        const as_name_tok = try self.expect(.Ident);
                        const pattern_ptr = try self.allocator.create(ast.Node.MatchPattern);
                        pattern_ptr.* = or_pattern;
                        return ast.Node.MatchPattern{
                            .as_pattern = .{ .pattern = pattern_ptr, .name = as_name_tok.lexeme },
                        };
                    }
                    return or_pattern;
                }
                return pattern;
            },
            .Minus => {
                // Negative number: case -1
                const expr = try self.parseExpression();
                const expr_ptr = try self.allocNode(expr);
                const pattern = ast.Node.MatchPattern{ .literal = expr_ptr };
                // Check for or-pattern
                if (self.check(.Pipe)) {
                    var patterns = std.ArrayList(ast.Node.MatchPattern){};
                    try patterns.append(self.allocator, pattern);
                    while (self.match(.Pipe)) {
                        const next = try parseMatchPattern(self);
                        try patterns.append(self.allocator, next);
                    }
                    return ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
                }
                return pattern;
            },
            .LBracket => {
                // Sequence pattern: case [a, b, c]
                var seq_pattern = try parseSequencePattern(self);
                // Check for or-pattern: [1, 2] | True
                if (self.check(.Pipe)) {
                    var patterns = std.ArrayList(ast.Node.MatchPattern){};
                    try patterns.append(self.allocator, seq_pattern);
                    while (self.match(.Pipe)) {
                        const next = try parseMatchPattern(self);
                        try patterns.append(self.allocator, next);
                    }
                    seq_pattern = ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
                }
                // Check for as-pattern: [] as z
                if (self.match(.As)) {
                    const as_name_tok = try self.expect(.Ident);
                    const pattern_ptr = try self.allocator.create(ast.Node.MatchPattern);
                    pattern_ptr.* = seq_pattern;
                    return ast.Node.MatchPattern{
                        .as_pattern = .{ .pattern = pattern_ptr, .name = as_name_tok.lexeme },
                    };
                }
                return seq_pattern;
            },
            .LBrace => {
                // Mapping pattern: case {"key": value}
                const map_pattern = try parseMappingPattern(self);
                // Check for or-pattern: {} | []
                if (self.check(.Pipe)) {
                    var patterns = std.ArrayList(ast.Node.MatchPattern){};
                    try patterns.append(self.allocator, map_pattern);
                    while (self.match(.Pipe)) {
                        const next = try parseMatchPattern(self);
                        try patterns.append(self.allocator, next);
                    }
                    return ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
                }
                return map_pattern;
            },
            .LParen => {
                // Could be tuple, grouped pattern, or or-pattern
                _ = self.advance(); // consume '('
                if (self.check(.RParen)) {
                    _ = self.advance();
                    return ast.Node.MatchPattern{ .sequence = &[_]ast.Node.MatchPattern{} };
                }
                var inner = try parseMatchPattern(self);
                // Check for as-pattern inside parens: (0 as z)
                if (self.check(.As)) {
                    _ = self.advance();
                    const as_name_tok = try self.expect(.Ident);
                    const inner_ptr = try self.allocator.create(ast.Node.MatchPattern);
                    inner_ptr.* = inner;
                    inner = ast.Node.MatchPattern{
                        .as_pattern = .{ .pattern = inner_ptr, .name = as_name_tok.lexeme },
                    };
                }
                // Check for or-pattern inside parens: ([1, 2] | False)
                if (self.check(.Pipe)) {
                    var patterns = std.ArrayList(ast.Node.MatchPattern){};
                    try patterns.append(self.allocator, inner);
                    while (self.match(.Pipe)) {
                        const next = try parseMatchPattern(self);
                        try patterns.append(self.allocator, next);
                    }
                    _ = try self.expect(.RParen);
                    const or_pattern = ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
                    // Check for as-pattern after or-pattern in parens
                    if (self.match(.As)) {
                        const as_name_tok = try self.expect(.Ident);
                        const pattern_ptr = try self.allocator.create(ast.Node.MatchPattern);
                        pattern_ptr.* = or_pattern;
                        return ast.Node.MatchPattern{
                            .as_pattern = .{ .pattern = pattern_ptr, .name = as_name_tok.lexeme },
                        };
                    }
                    return or_pattern;
                }
                if (self.check(.Comma)) {
                    // Tuple pattern
                    var patterns = std.ArrayList(ast.Node.MatchPattern){};
                    try patterns.append(self.allocator, inner);
                    while (self.match(.Comma)) {
                        if (self.check(.RParen)) break;
                        const next = try parseMatchPattern(self);
                        try patterns.append(self.allocator, next);
                    }
                    _ = try self.expect(.RParen);
                    var tuple_pattern = ast.Node.MatchPattern{ .sequence = try patterns.toOwnedSlice(self.allocator) };
                    // Check for or-pattern after tuple: (a, b, ...) | (c, d, ...)
                    if (self.check(.Pipe)) {
                        var or_patterns = std.ArrayList(ast.Node.MatchPattern){};
                        try or_patterns.append(self.allocator, tuple_pattern);
                        while (self.match(.Pipe)) {
                            const next = try parseMatchPattern(self);
                            try or_patterns.append(self.allocator, next);
                        }
                        tuple_pattern = ast.Node.MatchPattern{ .or_pattern = try or_patterns.toOwnedSlice(self.allocator) };
                    }
                    // Check for as-pattern: (p, q) as x
                    if (self.match(.As)) {
                        const as_name_tok = try self.expect(.Ident);
                        const pattern_ptr = try self.allocator.create(ast.Node.MatchPattern);
                        pattern_ptr.* = tuple_pattern;
                        return ast.Node.MatchPattern{
                            .as_pattern = .{ .pattern = pattern_ptr, .name = as_name_tok.lexeme },
                        };
                    }
                    return tuple_pattern;
                }
                _ = try self.expect(.RParen);
                // Check for or-pattern after grouped pattern: (0 as y) | (1 as y)
                if (self.check(.Pipe)) {
                    var patterns = std.ArrayList(ast.Node.MatchPattern){};
                    try patterns.append(self.allocator, inner);
                    while (self.match(.Pipe)) {
                        const next = try parseMatchPattern(self);
                        try patterns.append(self.allocator, next);
                    }
                    inner = ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
                }
                // Check for as-pattern after grouped pattern: (0 as w) as z
                if (self.match(.As)) {
                    const as_name_tok = try self.expect(.Ident);
                    const pattern_ptr = try self.allocator.create(ast.Node.MatchPattern);
                    pattern_ptr.* = inner;
                    return ast.Node.MatchPattern{
                        .as_pattern = .{ .pattern = pattern_ptr, .name = as_name_tok.lexeme },
                    };
                }
                return inner;
            },
            .Ident => {
                const name = tok.lexeme;
                _ = self.advance();

                // Check for dotted pattern: case Foo.Bar.x or case Foo.Bar(...)
                if (self.check(.Dot)) {
                    // Start with the name as initial node
                    var node: ast.Node = .{ .name = .{ .id = name } };

                    // Parse remaining dots
                    while (self.match(.Dot)) {
                        const attr_tok = try self.expect(.Ident);
                        const obj_ptr = try self.allocNode(node);
                        node = .{ .attribute = .{ .value = obj_ptr, .attr = attr_tok.lexeme } };
                    }

                    // Check if this is a class pattern: Foo.Bar(...)
                    if (self.check(.LParen)) {
                        const node_ptr = try self.allocNode(node);
                        return parseDottedClassPattern(self, node_ptr);
                    }

                    // Value pattern: case Foo.Bar.x matches against Foo.Bar.x
                    const node_ptr = try self.allocNode(node);
                    const pattern = ast.Node.MatchPattern{ .value = node_ptr };
                    // Check for as-pattern: A.y as z
                    if (self.match(.As)) {
                        const as_name_tok = try self.expect(.Ident);
                        const pattern_ptr = try self.allocator.create(ast.Node.MatchPattern);
                        pattern_ptr.* = pattern;
                        return ast.Node.MatchPattern{
                            .as_pattern = .{
                                .pattern = pattern_ptr,
                                .name = as_name_tok.lexeme,
                            },
                        };
                    }
                    return pattern;
                }

                // Check for class pattern: case Point(x=0) or Point(x, y) as p or Point(x) | Point(y)
                if (self.check(.LParen)) {
                    var class_pattern = try parseClassPattern(self, name);
                    // Check for or-pattern after class pattern: Point(x) | Point(y)
                    if (self.check(.Pipe)) {
                        var patterns = std.ArrayList(ast.Node.MatchPattern){};
                        try patterns.append(self.allocator, class_pattern);
                        while (self.match(.Pipe)) {
                            const next = try parseMatchPattern(self);
                            try patterns.append(self.allocator, next);
                        }
                        class_pattern = ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
                    }
                    // Check for as-pattern after class pattern
                    if (self.match(.As)) {
                        const as_name_tok = try self.expect(.Ident);
                        const pattern_ptr = try self.allocator.create(ast.Node.MatchPattern);
                        pattern_ptr.* = class_pattern;
                        return ast.Node.MatchPattern{
                            .as_pattern = .{ .pattern = pattern_ptr, .name = as_name_tok.lexeme },
                        };
                    }
                    return class_pattern;
                }

                // Check for or pattern: case 1 | 2 | 3
                if (self.check(.Pipe)) {
                    var patterns = std.ArrayList(ast.Node.MatchPattern){};
                    try patterns.append(self.allocator, ast.Node.MatchPattern{ .capture = name });
                    while (self.match(.Pipe)) {
                        const next = try parseMatchPattern(self);
                        try patterns.append(self.allocator, next);
                    }
                    return ast.Node.MatchPattern{ .or_pattern = try patterns.toOwnedSlice(self.allocator) };
                }

                // Simple capture pattern: case x, or case y as v
                const capture = ast.Node.MatchPattern{ .capture = name };
                // Check for as-pattern: y as v
                if (self.match(.As)) {
                    const as_name_tok = try self.expect(.Ident);
                    const pattern_ptr = try self.allocator.create(ast.Node.MatchPattern);
                    pattern_ptr.* = capture;
                    return ast.Node.MatchPattern{
                        .as_pattern = .{ .pattern = pattern_ptr, .name = as_name_tok.lexeme },
                    };
                }
                return capture;
            },
            else => {
                // Skip unknown tokens for now
                _ = self.advance();
                return ast.Node.MatchPattern{ .wildcard = {} };
            },
        }
    }
    return ParseError.UnexpectedEof;
}

/// Parse a single element of a sequence pattern, handling *rest
fn parseSequencePatternElement(self: *Parser) ParseError!ast.Node.MatchPattern {
    // Handle star pattern: *name or *_
    if (self.match(.Star)) {
        if (self.peek()) |tok| {
            if (tok.type == .Ident) {
                const name = tok.lexeme;
                _ = self.advance();
                // *_ is a wildcard capture, *name captures to name
                if (std.mem.eql(u8, name, "_")) {
                    return ast.Node.MatchPattern{ .wildcard = {} };
                }
                return ast.Node.MatchPattern{ .capture = name };
            }
        }
        return ast.Node.MatchPattern{ .wildcard = {} };
    }
    return parseMatchPattern(self);
}

fn parseSequencePattern(self: *Parser) ParseError!ast.Node.MatchPattern {
    _ = try self.expect(.LBracket);
    var patterns = std.ArrayList(ast.Node.MatchPattern){};
    errdefer patterns.deinit(self.allocator);

    if (!self.check(.RBracket)) {
        const first = try parseSequencePatternElement(self);
        try patterns.append(self.allocator, first);
        while (self.match(.Comma)) {
            if (self.check(.RBracket)) break;
            const next = try parseSequencePatternElement(self);
            try patterns.append(self.allocator, next);
        }
    }
    _ = try self.expect(.RBracket);
    return ast.Node.MatchPattern{ .sequence = try patterns.toOwnedSlice(self.allocator) };
}

fn parseMappingPattern(self: *Parser) ParseError!ast.Node.MatchPattern {
    _ = try self.expect(.LBrace);
    var entries = std.ArrayList(ast.Node.MappingPatternEntry){};
    errdefer entries.deinit(self.allocator);

    if (!self.check(.RBrace)) {
        // Check for double-star rest pattern: {**rest}
        if (self.match(.DoubleStar)) {
            // **rest pattern - capture remaining keys
            const rest_name = try self.expect(.Ident);
            const rest_pattern = ast.Node.MatchPattern{ .capture = rest_name.lexeme };
            // Use a name node with special marker "**" prefix as key
            const rest_key = ast.Node{ .name = .{ .id = rest_name.lexeme } };
            const rest_key_ptr = try self.allocNode(rest_key);
            try entries.append(self.allocator, .{ .key = rest_key_ptr, .pattern = rest_pattern });
        } else {
            // Parse key: pattern pairs (use parseExpression for negative/complex keys like -0-0j)
            const key = try self.parseExpression();
            const key_ptr = try self.allocNode(key);
            _ = try self.expect(.Colon);
            const value_pattern = try parseMatchPattern(self);
            try entries.append(self.allocator, .{ .key = key_ptr, .pattern = value_pattern });
        }

        while (self.match(.Comma)) {
            if (self.check(.RBrace)) break;
            // Check for double-star rest pattern: {x: 1, **rest}
            if (self.match(.DoubleStar)) {
                const rest_name = try self.expect(.Ident);
                const rest_pattern = ast.Node.MatchPattern{ .capture = rest_name.lexeme };
                const rest_key = ast.Node{ .name = .{ .id = rest_name.lexeme } };
                const rest_key_ptr = try self.allocNode(rest_key);
                try entries.append(self.allocator, .{ .key = rest_key_ptr, .pattern = rest_pattern });
                break; // **rest must be last
            }
            const next_key = try self.parseExpression();
            const next_key_ptr = try self.allocNode(next_key);
            _ = try self.expect(.Colon);
            const next_value_pattern = try parseMatchPattern(self);
            try entries.append(self.allocator, .{ .key = next_key_ptr, .pattern = next_value_pattern });
        }
    }
    _ = try self.expect(.RBrace);
    return ast.Node.MatchPattern{ .mapping = try entries.toOwnedSlice(self.allocator) };
}

/// Parse a class pattern with a dotted class name like Foo.Bar(...)
fn parseDottedClassPattern(self: *Parser, cls_node: *ast.Node) ParseError!ast.Node.MatchPattern {
    _ = try self.expect(.LParen);

    // Skip pattern arguments - just consume until )
    // A more complete implementation would parse the patterns
    var depth: usize = 1;
    while (depth > 0 and self.current < self.tokens.len) {
        if (self.peek()) |tok| {
            if (tok.type == .LParen) depth += 1 else if (tok.type == .RParen) depth -= 1;
            if (depth > 0) _ = self.advance();
        } else break;
    }
    _ = try self.expect(.RParen);

    // For dotted class patterns, treat as value pattern comparing against the class type
    // This is a simplification - full match/case would need isinstance() check
    return ast.Node.MatchPattern{ .value = cls_node };
}

fn parseClassPattern(self: *Parser, cls_name: []const u8) ParseError!ast.Node.MatchPattern {
    _ = try self.expect(.LParen);
    var positional = std.ArrayList(ast.Node.MatchPattern){};
    var keyword = std.ArrayList(ast.Node.KeywordPattern){};
    errdefer {
        positional.deinit(self.allocator);
        keyword.deinit(self.allocator);
    }

    if (!self.check(.RParen)) {
        while (true) {
            // Check if it's keyword pattern: x=0
            if (self.peek()) |tok| {
                if (tok.type == .Ident) {
                    // Look ahead for '='
                    if (self.current + 1 < self.tokens.len and self.tokens[self.current + 1].type == .Eq) {
                        const param_name = tok.lexeme;
                        _ = self.advance(); // consume name
                        _ = self.advance(); // consume '='
                        const pattern = try parseMatchPattern(self);
                        try keyword.append(self.allocator, .{ .name = param_name, .pattern = pattern });
                    } else {
                        // Positional pattern
                        const pattern = try parseMatchPattern(self);
                        try positional.append(self.allocator, pattern);
                    }
                } else {
                    // Positional pattern (non-identifier)
                    const pattern = try parseMatchPattern(self);
                    try positional.append(self.allocator, pattern);
                }
            }
            if (!self.match(.Comma)) break;
            if (self.check(.RParen)) break;
        }
    }
    _ = try self.expect(.RParen);

    return ast.Node.MatchPattern{ .class_pattern = .{
        .cls = cls_name,
        .positional = try positional.toOwnedSlice(self.allocator),
        .keyword = try keyword.toOwnedSlice(self.allocator),
    } };
}
