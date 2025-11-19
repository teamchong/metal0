/// Control flow statement parsing (if, for, while)
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const misc = @import("misc.zig");

pub fn parseIf(self: *Parser) ParseError!ast.Node {
        _ = try self.expect(.If);
        const condition_expr = try self.parseExpression();
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);

        const if_body = try misc.parseBlock(self);

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

            const elif_body = try misc.parseBlock(self);

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

            const else_body = try misc.parseBlock(self);

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

        const body = try misc.parseBlock(self);

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

        const body = try misc.parseBlock(self);

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
