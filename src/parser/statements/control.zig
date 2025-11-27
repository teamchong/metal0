/// Control flow statement parsing (if, for, while)
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const misc = @import("misc.zig");

pub fn parseIf(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.If);
    var condition_expr = try self.parseExpression();
    errdefer condition_expr.deinit(self.allocator);
    _ = try self.expect(.Colon);

    // Check if this is a one-liner if (if x: statement)
    var if_body: []ast.Node = undefined;
    if (self.peek()) |next_tok| {
        const is_oneliner = next_tok.type == .Pass or
            next_tok.type == .Ellipsis or
            next_tok.type == .Return or
            next_tok.type == .Break or
            next_tok.type == .Continue or
            next_tok.type == .Raise or
            next_tok.type == .Class or
            next_tok.type == .Def or
            next_tok.type == .Ident; // for assignments and expressions

        if (is_oneliner) {
            const stmt = try self.parseStatement();
            const body_slice = try self.allocator.alloc(ast.Node, 1);
            body_slice[0] = stmt;
            if_body = body_slice;
        } else {
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);
            if_body = try misc.parseBlock(self);
            _ = try self.expect(.Dedent);
        }
    } else {
        return ParseError.UnexpectedEof;
    }

    // Allocate condition on heap
    const condition_ptr = try self.allocator.create(ast.Node);
    condition_ptr.* = condition_expr;

    // Check for elif/else
    var else_stmts = std.ArrayList(ast.Node){};
    defer else_stmts.deinit(self.allocator);

    while (self.match(.Elif)) {
        var elif_condition = try self.parseExpression();
        errdefer elif_condition.deinit(self.allocator);
        _ = try self.expect(.Colon);

        // Check if this is a one-liner elif
        var elif_body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
                next_tok.type == .Ellipsis or
                next_tok.type == .Return or
                next_tok.type == .Break or
                next_tok.type == .Continue or
                next_tok.type == .Raise or
                next_tok.type == .Class or
                next_tok.type == .Def or
                next_tok.type == .Ident;

            if (is_oneliner) {
                const stmt = try self.parseStatement();
                const body_slice = try self.allocator.alloc(ast.Node, 1);
                body_slice[0] = stmt;
                elif_body = body_slice;
            } else {
                _ = try self.expect(.Newline);
                _ = try self.expect(.Indent);
                elif_body = try misc.parseBlock(self);
                _ = try self.expect(.Dedent);
            }
        } else {
            return ParseError.UnexpectedEof;
        }

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

        // Check if this is a one-liner else
        var else_body: []ast.Node = undefined;
        if (self.peek()) |next_tok| {
            const is_oneliner = next_tok.type == .Pass or
                next_tok.type == .Ellipsis or
                next_tok.type == .Return or
                next_tok.type == .Break or
                next_tok.type == .Continue or
                next_tok.type == .Raise or
                next_tok.type == .Class or
                next_tok.type == .Def or
                next_tok.type == .Ident;

            if (is_oneliner) {
                const stmt = try self.parseStatement();
                const body_slice = try self.allocator.alloc(ast.Node, 1);
                body_slice[0] = stmt;
                else_body = body_slice;
            } else {
                _ = try self.expect(.Newline);
                _ = try self.expect(.Indent);
                else_body = try misc.parseBlock(self);
                _ = try self.expect(.Dedent);
            }
        } else {
            return ParseError.UnexpectedEof;
        }

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

    // Parse iterable - may be a tuple without parens (e.g., 1, 2, 3)
    var first_expr = try self.parseExpression();
    errdefer first_expr.deinit(self.allocator);

    const iter = blk: {
        if (self.check(.Comma)) {
            // Tuple literal: collect comma-separated expressions
            var elts = std.ArrayList(ast.Node){};
            defer elts.deinit(self.allocator);

            try elts.append(self.allocator, first_expr);

            while (self.match(.Comma)) {
                // Check if we hit the colon (trailing comma case)
                if (self.check(.Colon)) break;
                try elts.append(self.allocator, try self.parseExpression());
            }

            break :blk ast.Node{ .tuple = .{ .elts = try elts.toOwnedSlice(self.allocator) } };
        } else {
            break :blk first_expr;
        }
    };

    _ = try self.expect(.Colon);

    // Check if this is a one-liner for (for x in y: statement)
    var body: []ast.Node = undefined;
    if (self.peek()) |next_tok| {
        const is_oneliner = next_tok.type == .Pass or
            next_tok.type == .Ellipsis or
            next_tok.type == .Return or
            next_tok.type == .Break or
            next_tok.type == .Continue or
            next_tok.type == .Raise or
            next_tok.type == .Class or
            next_tok.type == .Def or
            next_tok.type == .Ident;

        if (is_oneliner) {
            const stmt = try self.parseStatement();
            const body_slice = try self.allocator.alloc(ast.Node, 1);
            body_slice[0] = stmt;
            body = body_slice;
        } else {
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);
            body = try misc.parseBlock(self);
            _ = try self.expect(.Dedent);
        }
    } else {
        return ParseError.UnexpectedEof;
    }

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
    var condition_expr = try self.parseExpression();
    errdefer condition_expr.deinit(self.allocator);
    _ = try self.expect(.Colon);

    // Check if this is a one-liner while (while x: statement)
    var body: []ast.Node = undefined;
    if (self.peek()) |next_tok| {
        const is_oneliner = next_tok.type == .Pass or
            next_tok.type == .Ellipsis or
            next_tok.type == .Return or
            next_tok.type == .Break or
            next_tok.type == .Continue or
            next_tok.type == .Raise or
            next_tok.type == .Class or
            next_tok.type == .Def or
            next_tok.type == .Ident;

        if (is_oneliner) {
            const stmt = try self.parseStatement();
            const body_slice = try self.allocator.alloc(ast.Node, 1);
            body_slice[0] = stmt;
            body = body_slice;
        } else {
            _ = try self.expect(.Newline);
            _ = try self.expect(.Indent);
            body = try misc.parseBlock(self);
            _ = try self.expect(.Dedent);
        }
    } else {
        return ParseError.UnexpectedEof;
    }

    const condition_ptr = try self.allocator.create(ast.Node);
    condition_ptr.* = condition_expr;

    return ast.Node{
        .while_stmt = .{
            .condition = condition_ptr,
            .body = body,
        },
    };
}
