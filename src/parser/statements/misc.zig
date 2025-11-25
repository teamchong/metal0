/// Miscellaneous statement parsing (return, assert, pass, break, continue, try, decorated, parseBlock)
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

pub fn parseReturn(self: *Parser) ParseError!ast.Node {
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

    /// Parse assert statement: assert condition or assert condition, message
pub fn parseAssert(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Assert);

        // Parse the condition
        const condition = try self.parseExpression();
        const condition_ptr = try self.allocator.create(ast.Node);
        condition_ptr.* = condition;

        var msg_ptr: ?*ast.Node = null;

        // Check for optional message after comma
        if (self.match(.Comma)) {
            const msg = try self.parseExpression();
            msg_ptr = try self.allocator.create(ast.Node);
            msg_ptr.?.* = msg;
        }

        _ = self.expect(.Newline) catch {};

        return ast.Node{
            .assert_stmt = .{
                .condition = condition_ptr,
                .msg = msg_ptr,
            },
        };
    }

    pub fn parseBlock(self: *Parser) ParseError![]ast.Node {
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

    pub fn parseTry(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Try);
        _ = try self.expect(.Colon);

        // Parse try block body - check for one-liner
        var body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
                next_tok.type == .Return or
                next_tok.type == .Break or
                next_tok.type == .Continue or
                next_tok.type == .Raise or
                next_tok.type == .Ident; // for assignments and expressions

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

        // Parse except handlers
        var handlers = std.ArrayList(ast.Node.ExceptHandler){};
        defer handlers.deinit(self.allocator);

        while (self.match(.Except)) {
            // Check for exception type: except ValueError:
            var exc_type: ?[]const u8 = null;
            if (self.peek()) |tok| {
                if (tok.type == .Ident) {
                    exc_type = tok.lexeme;
                    _ = self.advance();
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
        var else_body: []ast.Node = &[_]ast.Node{};
        if (self.match(.Else)) {
            _ = try self.expect(.Colon);
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);
            else_body = try parseBlock(self);
            _ = try self.expect(.Dedent);
        }

        // Parse optional finally block
        var finalbody: []ast.Node = &[_]ast.Node{};
        if (self.match(.Finally)) {
            _ = try self.expect(.Colon);
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);
            finalbody = try parseBlock(self);
            _ = try self.expect(.Dedent);
        }

        return ast.Node{
            .try_stmt = .{
                .body = body,
                .handlers = try handlers.toOwnedSlice(self.allocator),
                .else_body = else_body,
                .finalbody = finalbody,
            },
        };
    }

    pub fn parseRaise(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Raise);

        var exc_ptr: ?*ast.Node = null;

        // Check if there's an exception expression
        if (self.peek()) |tok| {
            if (tok.type != .Newline) {
                const exc = try self.parseExpression();
                exc_ptr = try self.allocator.create(ast.Node);
                exc_ptr.?.* = exc;
            }
        }

        _ = self.expect(.Newline) catch {};

        return ast.Node{
            .raise_stmt = .{
                .exc = exc_ptr,
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

    pub fn parseDecorated(self: *Parser) ParseError!ast.Node {
        // Parse decorators: @decorator_name or @decorator_func(args)
        var decorators = std.ArrayList(ast.Node){};

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
            decorated_node.function_def.decorators = decorators_slice;
        } else {
            // If not a function, just free the decorators
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

    /// Parse with statement: with expr as var: body
    pub fn parseWith(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.With);

        // Parse context expression
        const context_expr = try self.parseExpression();
        const context_ptr = try self.allocator.create(ast.Node);
        context_ptr.* = context_expr;

        // Check for optional "as variable"
        var optional_vars: ?[]const u8 = null;
        if (self.match(.As)) {
            const var_tok = try self.expect(.Ident);
            optional_vars = var_tok.lexeme;
        }

        _ = try self.expect(.Colon);

        // Check if this is a one-liner with (with x: statement)
        var body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
                next_tok.type == .Return or
                next_tok.type == .Break or
                next_tok.type == .Continue or
                next_tok.type == .Raise or
                next_tok.type == .Ident; // for assignments and expressions

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

        return ast.Node{
            .with_stmt = .{
                .context_expr = context_ptr,
                .optional_vars = optional_vars,
                .body = body,
            },
        };
    }
