const std = @import("std");
const ast = @import("ast");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse function call after '(' has been consumed
/// Takes ownership of `func` - cleans it up on error
pub fn parseCall(self: *Parser, func: ast.Node) ParseError!ast.Node {
    // Take ownership of func immediately - we're responsible for cleanup on any error
    var fn_node = func;

    // Immediately allocate func on heap
    var func_ptr: ?*ast.Node = self.allocator.create(ast.Node) catch |err| {
        // Allocation failed - clean up func before returning error
        fn_node.deinit(self.allocator);
        return err;
    };
    func_ptr.?.* = fn_node;
    errdefer if (func_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    var args = std.ArrayList(ast.Node){};
    errdefer {
        for (args.items) |*arg| arg.deinit(self.allocator);
        args.deinit(self.allocator);
    }

    var keyword_args = std.ArrayList(ast.Node.KeywordArg){};
    errdefer {
        for (keyword_args.items) |*kw| kw.value.deinit(self.allocator);
        keyword_args.deinit(self.allocator);
    }

    while (!self.match(.RParen)) {
        // Check for ** operator for kwargs unpacking: func(**kwargs)
        // Must check DoubleStar before Star since ** starts with *
        if (self.match(.DoubleStar)) {
            var arg = try parseDoubleStarArg(self);
            errdefer arg.deinit(self.allocator);
            try args.append(self.allocator, arg);
        } else if (self.match(.Star)) {
            // Check for * operator for unpacking: func(*args)
            var arg = try parseStarArg(self);
            errdefer arg.deinit(self.allocator);
            try args.append(self.allocator, arg);
        } else {
            // Check if this is a keyword argument (name=value)
            try parsePositionalOrKeywordArg(self, &args, &keyword_args);
        }

        if (!self.match(.Comma)) {
            _ = try self.expect(.RParen);
            break;
        }
    }

    // Success - transfer ownership
    const final_func = func_ptr.?;
    func_ptr = null;
    const final_args = try args.toOwnedSlice(self.allocator);
    args = std.ArrayList(ast.Node){}; // Reset
    const final_kwargs = try keyword_args.toOwnedSlice(self.allocator);
    keyword_args = std.ArrayList(ast.Node.KeywordArg){}; // Reset

    return ast.Node{
        .call = .{
            .func = final_func,
            .args = final_args,
            .keyword_args = final_kwargs,
        },
    };
}

/// Parse **kwargs unpacking argument
fn parseDoubleStarArg(self: *Parser) ParseError!ast.Node {
    var value = try self.parseExpression();
    errdefer value.deinit(self.allocator);
    return ast.Node{ .double_starred = .{ .value = try self.allocNode(value) } };
}

/// Parse *args unpacking argument
fn parseStarArg(self: *Parser) ParseError!ast.Node {
    var value = try self.parseExpression();
    errdefer value.deinit(self.allocator);
    return ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
}

/// Parse positional or keyword argument
fn parsePositionalOrKeywordArg(
    self: *Parser,
    args: *std.ArrayList(ast.Node),
    keyword_args: *std.ArrayList(ast.Node.KeywordArg),
) ParseError!void {
    // We need to lookahead: if next token is Ident followed by Eq
    if (self.check(.Ident)) {
        const saved_pos = self.current;
        const name_tok = self.advance().?;

        if (self.check(.Eq)) {
            // It's a keyword argument
            _ = self.advance(); // consume =
            var value = try self.parseExpression();
            errdefer value.deinit(self.allocator);
            try keyword_args.append(self.allocator, .{
                .name = name_tok.lexeme,
                .value = value,
            });
        } else {
            // Not a keyword arg, restore position and parse as normal expression
            self.current = saved_pos;
            var arg = try parseArgWithPossibleGenExpr(self);
            errdefer arg.deinit(self.allocator);
            try args.append(self.allocator, arg);
        }
    } else {
        var arg = try parseArgWithPossibleGenExpr(self);
        errdefer arg.deinit(self.allocator);
        try args.append(self.allocator, arg);
    }
}

/// Parse an argument that might be a generator expression: func(x for x in items)
fn parseArgWithPossibleGenExpr(self: *Parser) ParseError!ast.Node {
    var expr = try self.parseExpression();
    errdefer expr.deinit(self.allocator);

    // Check if this is a generator expression: expr for target in iter
    if (self.check(.For)) {
        return try parseGeneratorExpr(self, expr);
    }

    return expr;
}

/// Parse generator expression after element: (element already parsed) for target in iter [if cond]
fn parseGeneratorExpr(self: *Parser, element: ast.Node) ParseError!ast.Node {
    var elt = element; // Take ownership
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
        // Parse target (name or tuple of names for unpacking)
        var target = try parseComprehensionTarget(self);
        errdefer target.deinit(self.allocator);

        _ = try self.expect(.In);

        // Use parseOrExpr to stop at 'if' keyword (not treat as ternary conditional)
        var iter = try self.parseOrExpr();
        errdefer iter.deinit(self.allocator);

        // Parse optional if conditions
        var ifs = std.ArrayList(ast.Node){};
        errdefer {
            for (ifs.items) |*i| i.deinit(self.allocator);
            ifs.deinit(self.allocator);
        }

        while (self.check(.If) and !self.check(.For)) {
            _ = self.advance();
            // Use parseOrExpr so nested 'if' doesn't get consumed as ternary
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

/// Parse a comprehension target: single name or tuple of names (e.g., x or x, y)
/// Returns a Name node for single target, or a Tuple node for multiple targets
fn parseComprehensionTarget(self: *Parser) ParseError!ast.Node {
    var first = try self.parsePrimary();
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
        var elem = try self.parsePrimary();
        errdefer elem.deinit(self.allocator);
        try elts.append(self.allocator, elem);
    }

    return ast.Node{
        .tuple = .{
            .elts = try elts.toOwnedSlice(self.allocator),
        },
    };
}
