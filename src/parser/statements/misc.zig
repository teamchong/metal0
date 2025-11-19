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
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        // Parse try block body
        const body = try parseBlock(self);

        _ = try self.expect(.Dedent);

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

            _ = try self.expect(.Colon);
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);

            const handler_body = try parseBlock(self);

            _ = try self.expect(.Dedent);

            try handlers.append(self.allocator, ast.Node.ExceptHandler{
                .type = exc_type,
                .name = null, // Not implementing "as e" yet
                .body = handler_body,
            });
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
                .else_body = &[_]ast.Node{}, // Not implementing else block
                .finalbody = finalbody,
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
