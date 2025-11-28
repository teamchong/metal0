/// Control flow statement parsing (if, for, while)
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;
const misc = @import("misc.zig");

pub fn parseIf(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.If);

    // Parse condition and immediately allocate on heap
    var condition_ptr: ?*ast.Node = null;
    errdefer if (condition_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };
    {
        var condition_expr = try self.parseExpression();
        condition_ptr = self.allocator.create(ast.Node) catch |err| {
            condition_expr.deinit(self.allocator);
            return err;
        };
        condition_ptr.?.* = condition_expr;
    }

    _ = try self.expect(.Colon);

    // Track if_body for cleanup
    var if_body: ?[]ast.Node = null;
    errdefer if (if_body) |body| {
        for (body) |*stmt| stmt.deinit(self.allocator);
        self.allocator.free(body);
    };

    // Check if this is a one-liner if (if x: statement)
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
            var stmt = try self.parseStatement();
            const body_slice = self.allocator.alloc(ast.Node, 1) catch |err| {
                stmt.deinit(self.allocator);
                return err;
            };
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

    // Check for elif/else
    var else_stmts = std.ArrayList(ast.Node){};
    errdefer {
        for (else_stmts.items) |*stmt| stmt.deinit(self.allocator);
        else_stmts.deinit(self.allocator);
    }

    while (self.match(.Elif)) {
        // Parse condition and immediately allocate on heap
        var elif_condition_ptr: ?*ast.Node = null;
        errdefer if (elif_condition_ptr) |ptr| {
            ptr.deinit(self.allocator);
            self.allocator.destroy(ptr);
        };
        {
            var elif_condition = try self.parseExpression();
            elif_condition_ptr = self.allocator.create(ast.Node) catch |err| {
                elif_condition.deinit(self.allocator);
                return err;
            };
            elif_condition_ptr.?.* = elif_condition;
        }

        _ = try self.expect(.Colon);

        // Track elif_body for cleanup
        var elif_body: ?[]ast.Node = null;
        errdefer if (elif_body) |body| {
            for (body) |*stmt| stmt.deinit(self.allocator);
            self.allocator.free(body);
        };

        // Check if this is a one-liner elif
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
                var stmt = try self.parseStatement();
                const body_slice = self.allocator.alloc(ast.Node, 1) catch |err| {
                    stmt.deinit(self.allocator);
                    return err;
                };
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

        // Transfer ownership to else_stmts
        try else_stmts.append(self.allocator, ast.Node{
            .if_stmt = .{
                .condition = elif_condition_ptr.?,
                .body = elif_body.?,
                .else_body = &[_]ast.Node{},
            },
        });
        elif_body = null; // Ownership transferred
        elif_condition_ptr = null; // Ownership transferred
    }

    if (self.match(.Else)) {
        _ = try self.expect(.Colon);

        // Track else_body for cleanup
        var else_body: ?[]ast.Node = null;
        errdefer if (else_body) |body| {
            for (body) |*stmt| stmt.deinit(self.allocator);
            self.allocator.free(body);
        };

        // Check if this is a one-liner else
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
                var stmt = try self.parseStatement();
                const body_slice = self.allocator.alloc(ast.Node, 1) catch |err| {
                    stmt.deinit(self.allocator);
                    return err;
                };
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

        // Transfer ownership to else_stmts
        for (else_body.?) |stmt| {
            try else_stmts.append(self.allocator, stmt);
        }
        self.allocator.free(else_body.?); // Free the slice wrapper, items transferred
        else_body = null;
    }

    // Success - transfer ownership
    const final_condition = condition_ptr.?;
    condition_ptr = null;
    const final_if_body = if_body.?;
    if_body = null;
    const final_else_body = try else_stmts.toOwnedSlice(self.allocator);
    else_stmts = std.ArrayList(ast.Node){}; // Reset

    return ast.Node{
        .if_stmt = .{
            .condition = final_condition,
            .body = final_if_body,
            .else_body = final_else_body,
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

    const target_node = if (targets.items.len == 1)
        targets.items[0]
    else
        ast.Node{ .list = .{ .elts = try targets.toOwnedSlice(self.allocator) } };

    // Check for optional else clause (for/else)
    var orelse_body: ?[]ast.Node = null;
    if (self.check(.Else)) {
        _ = self.advance(); // consume 'else'
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);
        orelse_body = try misc.parseBlock(self);
        _ = try self.expect(.Dedent);
    }

    return ast.Node{
        .for_stmt = .{
            .target = try self.allocNode(target_node),
            .iter = try self.allocNode(iter),
            .body = body,
            .orelse_body = orelse_body,
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

    // Check for optional else clause (while/else)
    var orelse_body: ?[]ast.Node = null;
    if (self.check(.Else)) {
        _ = self.advance(); // consume 'else'
        _ = try self.expect(.Colon);
        _ = try self.expect(.Newline);
        _ = try self.expect(.Indent);
        orelse_body = try misc.parseBlock(self);
        _ = try self.expect(.Dedent);
    }

    return ast.Node{
        .while_stmt = .{
            .condition = try self.allocNode(condition_expr),
            .body = body,
            .orelse_body = orelse_body,
        },
    };
}
