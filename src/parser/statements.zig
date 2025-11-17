const std = @import("std");
const ast = @import("../ast.zig");
const lexer = @import("../lexer.zig");
const ParseError = @import("../parser.zig").ParseError;
const Parser = @import("../parser.zig").Parser;

pub fn parseExprOrAssign(self: *Parser) ParseError!ast.Node {
        const expr = try self.parseExpression();

        // Check if this is tuple unpacking (comma-separated targets)
        if (self.check(.Comma)) {
            // Parse comma-separated targets: a, b, c
            var targets_list = std.ArrayList(ast.Node){};
            try targets_list.append(self.allocator, expr);

            while (self.match(.Comma)) {
                const target = try self.parseExpression();
                try targets_list.append(self.allocator, target);
            }

            // Now expect assignment
            if (self.match(.Eq)) {
                const value = try self.parseExpression();
                _ = self.expect(.Newline) catch {};

                // Allocate value on heap
                const value_ptr = try self.allocator.create(ast.Node);
                value_ptr.* = value;

                // Create a tuple node for the targets
                const targets_array = try targets_list.toOwnedSlice(self.allocator);
                const target_tuple = try self.allocator.create(ast.Node);
                target_tuple.* = ast.Node{ .tuple = .{ .elts = targets_array } };

                // Wrap the tuple in array (single target)
                var targets = try self.allocator.alloc(ast.Node, 1);
                targets[0] = target_tuple.*;

                return ast.Node{
                    .assign = .{
                        .targets = targets,
                        .value = value_ptr,
                    },
                };
            } else {
                // This is invalid - can't have comma-separated expressions as statement
                return error.UnexpectedToken;
            }
        }

        // Check for augmented assignment (+=, -=, etc.)
        const aug_op = blk: {
            if (self.match(.PlusEq)) break :blk ast.Operator.Add;
            if (self.match(.MinusEq)) break :blk ast.Operator.Sub;
            if (self.match(.StarEq)) break :blk ast.Operator.Mult;
            if (self.match(.SlashEq)) break :blk ast.Operator.Div;
            if (self.match(.DoubleSlashEq)) break :blk ast.Operator.FloorDiv;
            if (self.match(.PercentEq)) break :blk ast.Operator.Mod;
            if (self.match(.StarStarEq)) break :blk ast.Operator.Pow;
            break :blk null;
        };

        if (aug_op) |op| {
            const value = try self.parseExpression();
            _ = self.expect(.Newline) catch {};

            // Allocate nodes on heap
            const target_ptr = try self.allocator.create(ast.Node);
            target_ptr.* = expr;

            const value_ptr = try self.allocator.create(ast.Node);
            value_ptr.* = value;

            return ast.Node{
                .aug_assign = .{
                    .target = target_ptr,
                    .op = op,
                    .value = value_ptr,
                },
            };
        }

        // Check for regular assignment
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

pub fn parseFunctionDef(self: *Parser) ParseError!ast.Node {
        // Check for 'async' keyword
        const is_async = self.match(.Async);

        _ = try self.expect(.Def);
        const name_tok = try self.expect(.Ident);
        _ = try self.expect(.LParen);

        var args = std.ArrayList(ast.Arg){};
        defer args.deinit(self.allocator);

        while (!self.match(.RParen)) {
            const arg_name = try self.expect(.Ident);

            // Parse type annotation if present (e.g., : int, : str)
            var type_annotation: ?[]const u8 = null;
            if (self.match(.Colon)) {
                // Next token should be the type name
                if (self.current < self.tokens.len and self.tokens[self.current].type == .Ident) {
                    type_annotation = self.tokens[self.current].lexeme;
                    self.current += 1;
                }
            }

            try args.append(self.allocator, .{
                .name = arg_name.lexeme,
                .type_annotation = type_annotation,
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

        const body = try parseBlock(self);

        _ = try self.expect(.Dedent);

        return ast.Node{
            .function_def = .{
                .name = name_tok.lexeme,
                .args = try args.toOwnedSlice(self.allocator),
                .body = body,
                .is_async = is_async,
            },
        };
    }

pub fn parseClassDef(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Class);
        const name_tok = try self.expect(.Ident);

        // Parse optional base classes: class Dog(Animal):
        var bases = std.ArrayList([]const u8){};
        defer bases.deinit(self.allocator);

        if (self.match(.LParen)) {
            while (!self.match(.RParen)) {
                const base_tok = try self.expect(.Ident);
                try bases.append(self.allocator, base_tok.lexeme);

                if (!self.match(.Comma)) {
                    _ = try self.expect(.RParen);
                    break;
                }
            }
        }

        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const body = try parseBlock(self);

        _ = try self.expect(.Dedent);

        return ast.Node{
            .class_def = .{
                .name = name_tok.lexeme,
                .bases = try bases.toOwnedSlice(self.allocator),
                .body = body,
            },
        };
    }

pub fn parseIf(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.If);
        const condition_expr = try self.parseExpression();
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const if_body = try parseBlock(self);

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

            const elif_body = try parseBlock(self);

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

            const else_body = try parseBlock(self);

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

pub fn parseFor(self: *Parser) ParseError!ast.Node {
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

        const body = try parseBlock(self);

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

pub fn parseWhile(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.While);
        const condition_expr = try self.parseExpression();
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const body = try parseBlock(self);

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

    /// Parse import statement: import numpy as np
pub fn parseImport(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.Import);

        const module_tok = try self.expect(.Ident);
        const module_name = module_tok.lexeme;

        var asname: ?[]const u8 = null;

        // Check for "as" clause
        if (self.match(.As)) {
            const alias_tok = try self.expect(.Ident);
            asname = alias_tok.lexeme;
        }

        _ = self.expect(.Newline) catch {};

        return ast.Node{
            .import_stmt = .{
                .module = module_name,
                .asname = asname,
            },
        };
    }

    /// Parse from-import: from numpy import array, zeros
pub fn parseImportFrom(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.From);

        const module_tok = try self.expect(.Ident);
        const module_name = module_tok.lexeme;

        _ = try self.expect(.Import);

        var names = std.ArrayList([]const u8){};
        var asnames = std.ArrayList(?[]const u8){};

        // Parse comma-separated names
        while (true) {
            const name_tok = try self.expect(.Ident);
            try names.append(self.allocator, name_tok.lexeme);

            // Check for "as" alias
            if (self.match(.As)) {
                const alias_tok = try self.expect(.Ident);
                try asnames.append(self.allocator, alias_tok.lexeme);
            } else {
                try asnames.append(self.allocator, null);
            }

            if (!self.match(.Comma)) break;
        }

        _ = self.expect(.Newline) catch {};

        return ast.Node{
            .import_from = .{
                .module = module_name,
                .names = try names.toOwnedSlice(self.allocator),
                .asnames = try asnames.toOwnedSlice(self.allocator),
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

    // ===== Expression Parsing =====

