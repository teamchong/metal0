/// Miscellaneous statement parsing (return, assert, pass, break, continue, try, decorated, parseBlock)
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

pub fn parseReturn(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Return);

    var value_ptr: ?*ast.Node = null;
    errdefer if (value_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    // Check if there's a return value
    if (self.peek()) |tok| {
        if (tok.type != .Newline) {
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
                    // Check if we're at end of return statement
                    if (self.peek()) |next_tok| {
                        if (next_tok.type == .Newline or next_tok.type == .Eof) break;
                    } else break;

                    var elem = try self.parseExpression();
                    errdefer elem.deinit(self.allocator);
                    try elements.append(self.allocator, elem);

                    // Check for more elements
                    if (!self.match(.Comma)) break;
                }

                // Create tuple from elements - transfer ownership
                value_ptr = try self.allocator.create(ast.Node);
                value_ptr.?.* = ast.Node{
                    .tuple = .{
                        .elts = try elements.toOwnedSlice(self.allocator),
                    },
                };
                elements = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free
            } else {
                value_ptr = try self.allocator.create(ast.Node);
                value_ptr.?.* = first_value;
            }
        }
    }

    _ = self.expect(.Newline) catch {};

    // Success - clear errdefer by returning ownership
    const result_ptr = value_ptr;
    value_ptr = null;

    return ast.Node{
        .return_stmt = .{
            .value = result_ptr,
        },
    };
}

/// Parse assert statement: assert condition or assert condition, message
pub fn parseAssert(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.Assert);

    // Parse the condition
    var condition = try self.parseExpression();
    errdefer condition.deinit(self.allocator);

    var condition_ptr: ?*ast.Node = null;
    errdefer if (condition_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    condition_ptr = try self.allocator.create(ast.Node);
    condition_ptr.?.* = condition;

    var msg_ptr: ?*ast.Node = null;
    errdefer if (msg_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    // Check for optional message after comma
    if (self.match(.Comma)) {
        var msg = try self.parseExpression();
        errdefer msg.deinit(self.allocator);
        msg_ptr = try self.allocator.create(ast.Node);
        msg_ptr.?.* = msg;
    }

    _ = self.expect(.Newline) catch {};

    // Success - transfer ownership
    const final_condition = condition_ptr.?;
    condition_ptr = null;
    const final_msg = msg_ptr;
    msg_ptr = null;

    return ast.Node{
        .assert_stmt = .{
            .condition = final_condition,
            .msg = final_msg,
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
                _ = self.advance(); // consume '('
                if (self.peek()) |inner_tok| {
                    if (inner_tok.type == .Ident) {
                        exc_type = inner_tok.lexeme;
                        _ = self.advance();
                        // Skip any additional types in tuple (for now just use first)
                        while (self.match(.Comma)) {
                            if (self.peek()) |next_type| {
                                if (next_type.type == .Ident) {
                                    _ = self.advance(); // consume additional type
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

    var exc_ptr: ?*ast.Node = null;
    errdefer if (exc_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    var cause_ptr: ?*ast.Node = null;
    errdefer if (cause_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    // Check if there's an exception expression
    if (self.peek()) |tok| {
        if (tok.type != .Newline) {
            var exc = try self.parseExpression();
            errdefer exc.deinit(self.allocator);
            exc_ptr = try self.allocator.create(ast.Node);
            exc_ptr.?.* = exc;

            // Check for "from" clause: raise X from Y
            if (self.peek()) |next_tok| {
                if (next_tok.type == .From) {
                    _ = self.advance(); // consume 'from'
                    var cause = try self.parseExpression();
                    errdefer cause.deinit(self.allocator);
                    cause_ptr = try self.allocator.create(ast.Node);
                    cause_ptr.?.* = cause;
                }
            }
        }
    }

    _ = self.expect(.Newline) catch {};

    // Success - transfer ownership
    const final_exc = exc_ptr;
    exc_ptr = null;
    const final_cause = cause_ptr;
    cause_ptr = null;

    return ast.Node{
        .raise_stmt = .{
            .exc = final_exc,
            .cause = final_cause,
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

    var value_ptr: ?*ast.Node = null;
    errdefer if (value_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    // Check if there's a value expression
    if (self.peek()) |tok| {
        if (tok.type != .Newline) {
            // Parse first value
            var first_value = try self.parseExpression();
            errdefer first_value.deinit(self.allocator);

            // Check if this is a tuple: yield a, b, c
            var value = if (self.check(.Comma)) blk: {
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
                value_list = std.ArrayList(ast.Node){}; // Reset
                break :blk ast.Node{ .tuple = .{ .elts = value_array } };
            } else first_value;
            errdefer value.deinit(self.allocator);

            value_ptr = try self.allocator.create(ast.Node);
            value_ptr.?.* = value;
        }
    }

    _ = self.expect(.Newline) catch {};

    // Success - transfer ownership
    const final_value = value_ptr;
    value_ptr = null;

    return ast.Node{
        .yield_stmt = .{
            .value = final_value,
        },
    };
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
pub fn parseWith(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.With);

    // Parse context expression
    var context_expr = try self.parseExpression();
    errdefer context_expr.deinit(self.allocator);

    var context_ptr: ?*ast.Node = null;
    errdefer if (context_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    context_ptr = try self.allocator.create(ast.Node);
    context_ptr.?.* = context_expr;

    // Check for optional "as variable"
    var optional_vars: ?[]const u8 = null;
    if (self.match(.As)) {
        const var_tok = try self.expect(.Ident);
        optional_vars = var_tok.lexeme;
    }

    // Handle multiple context managers: with ctx1, ctx2, ctx3:
    // For now, just parse and skip additional context managers (use first one)
    while (self.match(.Comma)) {
        var extra_ctx = try self.parseExpression();
        extra_ctx.deinit(self.allocator); // Discard additional context managers

        // Check for optional "as variable" on additional context
        if (self.match(.As)) {
            _ = try self.expect(.Ident); // Skip the variable name
        }
    }

    _ = try self.expect(.Colon);

    // Track body allocation for cleanup
    var body_alloc: ?[]ast.Node = null;
    errdefer if (body_alloc) |b| {
        for (b) |*stmt| stmt.deinit(self.allocator);
        self.allocator.free(b);
    };

    // Check if this is a one-liner with (with x: statement)
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

    // Success - transfer ownership
    const final_context = context_ptr.?;
    context_ptr = null;
    const final_body = body_alloc.?;
    body_alloc = null;

    return ast.Node{
        .with_stmt = .{
            .context_expr = final_context,
            .optional_vars = optional_vars,
            .body = final_body,
        },
    };
}
