/// Miscellaneous statement parsing (return, assert, pass, break, continue, try, decorated, parseBlock)
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

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

            // Parse remaining elements
            while (true) {
                if (self.peek()) |next_tok| {
                    if (next_tok.type == .Newline or next_tok.type == .Eof) break;
                } else break;

                var elem = try self.parseExpression();
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

    _ = self.expect(.Newline) catch {};

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

    _ = self.expect(.Newline) catch {};

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

    // Parse try block body - check for one-liner
    if (self.peek()) |next_tok| {
        const is_oneliner = next_tok.type == .Pass or
            next_tok.type == .Ellipsis or
            next_tok.type == .Return or
            next_tok.type == .Break or
            next_tok.type == .Continue or
            next_tok.type == .Raise or
            next_tok.type == .Ident; // for assignments and expressions

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
        // Check for exception type: except ValueError: or except (Exception) as e:
        // Also handles dotted types: except click.BadParameter:
        var exc_type: ?[]const u8 = null;
        if (self.peek()) |tok| {
            if (tok.type == .Ident) {
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
                            // Skip dotted exception type
                            while (self.peek()) |next_type| {
                                if (next_type.type == .Ident) {
                                    _ = self.advance();
                                    // Skip dots in the name
                                    if (!self.match(.Dot)) break;
                                } else break;
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
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);
        else_body_alloc = try parseBlock(self);
        _ = try self.expect(.Dedent);
    }

    // Parse optional finally block
    if (self.match(.Finally)) {
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);
        finally_body_alloc = try parseBlock(self);
        _ = try self.expect(.Dedent);
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

    _ = self.expect(.Newline) catch {};

    return ast.Node{
        .raise_stmt = .{
            .exc = try self.allocNodeOpt(exc),
            .cause = try self.allocNodeOpt(cause),
        },
    };
}

pub fn parsePass(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Pass);
    _ = self.expect(.Newline) catch {};
    return ast.Node{ .pass = {} };
}

pub fn parseBreak(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Break);
    _ = self.expect(.Newline) catch {};
    return ast.Node{ .break_stmt = {} };
}

pub fn parseContinue(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Continue);
    _ = self.expect(.Newline) catch {};
    return ast.Node{ .continue_stmt = {} };
}

pub fn parseYield(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Yield);

    // Check for "yield from expr" (PEP 380)
    if (self.match(.From)) {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        _ = self.expect(.Newline) catch {};
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
                var val = try self.parseExpression();
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

    _ = self.expect(.Newline) catch {};

    return ast.Node{ .yield_stmt = .{ .value = value_ptr } };
}

pub fn parseEllipsis(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Ellipsis);
    _ = self.expect(.Newline) catch {};
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

    _ = self.expect(.Newline) catch {};

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

    _ = self.expect(.Newline) catch {};

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
    while (self.match(.Comma)) {
        var target = try self.parseExpression();
        errdefer target.deinit(self.allocator);
        try targets.append(self.allocator, target);
    }

    _ = self.expect(.Newline) catch {};

    // Success - transfer ownership
    const result = try targets.toOwnedSlice(self.allocator);
    targets = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free

    return ast.Node{
        .del_stmt = .{
            .targets = result,
        },
    };
}

/// Parse with statement: with expr as var: body
/// Also supports multiple context managers: with ctx1, ctx2 as var: body
/// Python 3.10+: with (ctx1 as var1, ctx2 as var2):
pub fn parseWith(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.With);

    // Check for parenthesized context managers (Python 3.10+)
    const has_parens = self.match(.LParen);

    // Parse context expression
    var context_expr = try self.parseExpression();
    errdefer context_expr.deinit(self.allocator);

    // Check for optional "as variable"
    var optional_vars: ?[]const u8 = null;
    if (self.match(.As)) {
        if (self.peek()) |tok| {
            if (tok.type == .Ident) {
                const var_tok = self.advance().?;
                optional_vars = var_tok.lexeme;
            } else if (tok.type == .LParen) {
                // Tuple target: as (a, b)
                _ = self.advance(); // consume (
                _ = try self.parseExpression(); // skip tuple
                _ = try self.expect(.RParen);
            }
        }
    }

    // Handle multiple context managers: with ctx1, ctx2, ctx3:
    // For now, just parse and skip additional context managers (use first one)
    while (self.match(.Comma)) {
        // Allow trailing comma in parenthesized form
        if (has_parens and self.check(.RParen)) break;

        var extra_ctx = try self.parseExpression();
        extra_ctx.deinit(self.allocator); // Discard additional context managers
        if (self.match(.As)) {
            if (self.peek()) |tok| {
                if (tok.type == .Ident) {
                    _ = self.advance(); // Skip the variable name
                } else if (tok.type == .LParen) {
                    _ = self.advance();
                    _ = try self.parseExpression();
                    _ = try self.expect(.RParen);
                }
            }
        }
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

    return ast.Node{
        .with_stmt = .{
            .context_expr = try self.allocNode(context_expr),
            .optional_vars = optional_vars,
            .body = body,
        },
    };
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
    errdefer subject.deinit(self.allocator);

    _ = try self.expect(.Colon);
    _ = try self.expect(.Newline);
    _ = try self.expect(.Indent);

    // Parse case clauses
    var cases = std.ArrayList(ast.Node){};
    errdefer {
        for (cases.items) |*c| c.deinit(self.allocator);
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

        // Parse pattern - we simplify by just skipping tokens until we hit ':'
        // This handles: case x:, case [a, b]:, case {"key": v}:, case Class(x=1):, case _ if cond:
        var paren_depth: usize = 0;
        var bracket_depth: usize = 0;
        var brace_depth: usize = 0;
        while (true) {
            if (self.check(.Colon) and paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) {
                break;
            }
            if (self.match(.LParen)) {
                paren_depth += 1;
            } else if (self.match(.RParen)) {
                if (paren_depth > 0) paren_depth -= 1;
            } else if (self.match(.LBracket)) {
                bracket_depth += 1;
            } else if (self.match(.RBracket)) {
                if (bracket_depth > 0) bracket_depth -= 1;
            } else if (self.match(.LBrace)) {
                brace_depth += 1;
            } else if (self.match(.RBrace)) {
                if (brace_depth > 0) brace_depth -= 1;
            } else {
                _ = self.advance();
            }
            if (self.current >= self.tokens.len) break;
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

        // Store case as a simple if-branch for now (pattern matching is complex to implement fully)
        // We create a pass statement as a placeholder
        for (body) |*stmt| stmt.deinit(self.allocator);
        self.allocator.free(body);
    }

    _ = try self.expect(.Dedent);

    // For now, return the subject as an expression statement (match is complex to fully support)
    subject.deinit(self.allocator);
    return ast.Node{ .pass = {} };
}
