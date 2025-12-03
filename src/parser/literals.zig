const std = @import("std");
const ast = @import("ast");
const lexer = @import("../lexer.zig");
const ParseError = @import("../parser.zig").ParseError;
const Parser = @import("../parser.zig").Parser;

/// Parse a comprehension target: single name, subscript, or tuple of names (e.g., x or tgt[0] or x, y)
/// Returns a Name/Subscript node for single target, or a Tuple node for multiple targets
fn parseComprehensionTarget(self: *Parser) ParseError!ast.Node {
    // Parse a target element, which may be starred (*rest)
    var first = try parseCompTarget(self);
    errdefer first.deinit(self.allocator);

    // Check if there are more targets (tuple unpacking)
    if (!self.check(.Comma) or self.check(.In)) {
        return first;
    }

    // It's a tuple target like: x, y in items or x, *rest in items
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
        var elem = try parseCompTarget(self);
        errdefer elem.deinit(self.allocator);
        try elts.append(self.allocator, elem);
    }

    return ast.Node{
        .tuple = .{
            .elts = try elts.toOwnedSlice(self.allocator),
        },
    };
}

/// Parse a single target element, handling starred expressions (*rest)
fn parseCompTarget(self: *Parser) ParseError!ast.Node {
    // Check for starred target: *rest
    if (self.match(.Star)) {
        var value = try self.parsePostfix();
        errdefer value.deinit(self.allocator);
        const value_ptr = try self.allocNode(value);
        return ast.Node{ .starred = .{ .value = value_ptr } };
    }
    return try self.parsePostfix();
}

/// Parse a list literal: [1, 2, 3] or list comprehension: [x for x in items]
pub fn parseList(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.LBracket);

    // Empty list
    if (self.match(.RBracket)) {
        return ast.Node{ .list = .{ .elts = &[_]ast.Node{} } };
    }

    // Parse first element (may be starred: [*items, ...])
    var first_elt = try parseListElement(self);
    errdefer first_elt.deinit(self.allocator);

    // Check if this is a list comprehension: [x for x in items] or [x async for x in items]
    if (self.check(.For) or self.check(.Async)) {
        return try parseListComp(self, first_elt);
    }

    // Regular list: collect elements
    var elts = std.ArrayList(ast.Node){};
    errdefer {
        for (elts.items) |*e| e.deinit(self.allocator);
        elts.deinit(self.allocator);
    }
    try elts.append(self.allocator, first_elt);

    while (self.match(.Comma)) {
        if (self.check(.RBracket)) break;
        var elt = try parseListElement(self);
        errdefer elt.deinit(self.allocator);
        try elts.append(self.allocator, elt);
    }

    _ = try self.expect(.RBracket);

    const result = try elts.toOwnedSlice(self.allocator);
    elts = std.ArrayList(ast.Node){};
    return ast.Node{ .list = .{ .elts = result } };
}

/// Parse list element - handles starred expressions like *args
fn parseListElement(self: *Parser) ParseError!ast.Node {
    if (self.match(.Star)) {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        return ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
    }
    return self.parseExpression();
}

/// Parse list comprehension: [x for x in items if cond] or [x*y for x in range(3) for y in range(3)]
/// Also handles async comprehensions: [x async for x in aiter]
pub fn parseListComp(self: *Parser, elt: ast.Node) ParseError!ast.Node {
    // We've already parsed the element expression
    // Now parse one or more: for <target> in <iter> [if <condition>]
    var element = elt;
    errdefer element.deinit(self.allocator);

    var generators = std.ArrayList(ast.Node.Comprehension){};
    errdefer {
        for (generators.items) |*gen| {
            gen.target.deinit(self.allocator);
            self.allocator.destroy(gen.target);
            gen.iter.deinit(self.allocator);
            self.allocator.destroy(gen.iter);
            for (gen.ifs) |*cond| cond.deinit(self.allocator);
            self.allocator.free(gen.ifs);
        }
        generators.deinit(self.allocator);
    }

    // Parse all "for ... in ..." or "async for ... in ..." clauses
    while (self.check(.For) or self.check(.Async)) {
        // Handle async for
        _ = self.match(.Async);
        if (!self.match(.For)) break;

        // Parse target (name or tuple of names for unpacking)
        var target = try parseComprehensionTarget(self);
        errdefer target.deinit(self.allocator);
        _ = try self.expect(.In);
        // Use parseOrExpr to stop at 'if' keyword (not treat as ternary conditional)
        var iter = try self.parseOrExpr();
        errdefer iter.deinit(self.allocator);

        // Parse optional if conditions for this generator
        var ifs = std.ArrayList(ast.Node){};
        errdefer {
            for (ifs.items) |*i| i.deinit(self.allocator);
            ifs.deinit(self.allocator);
        }

        while (self.check(.If) and !self.check(.For) and !self.check(.Async)) {
            _ = self.advance();
            // Use parseOrExpr so nested 'if' doesn't get consumed as ternary
            var cond = try self.parseOrExpr();
            errdefer cond.deinit(self.allocator);
            try ifs.append(self.allocator, cond);
        }

        const ifs_slice = try ifs.toOwnedSlice(self.allocator);
        ifs = std.ArrayList(ast.Node){}; // Reset

        try generators.append(self.allocator, ast.Node.Comprehension{
            .target = try self.allocNode(target),
            .iter = try self.allocNode(iter),
            .ifs = ifs_slice,
        });
    }

    _ = try self.expect(.RBracket);

    // Success - transfer ownership
    const gens = try generators.toOwnedSlice(self.allocator);
    generators = std.ArrayList(ast.Node.Comprehension){}; // Reset

    return ast.Node{
        .listcomp = .{
            .elt = try self.allocNode(element),
            .generators = gens,
        },
    };
}

/// Parse dictionary or set literal: {key: value, ...} or {item, ...}
/// Also handles dict comprehensions and dict unpacking {**other_dict, ...}
pub fn parseDict(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.LBrace);

    // Empty dict: {}
    if (self.match(.RBrace)) {
        return ast.Node{
            .dict = .{
                .keys = &[_]ast.Node{},
                .values = &[_]ast.Node{},
            },
        };
    }

    // Check for dict unpacking: {**other_dict, ...}
    if (self.check(.DoubleStar)) {
        return try parseDictWithUnpacking(self);
    }

    // Check for set unpacking: {*iterable, ...}
    if (self.check(.Star)) {
        return try parseSetWithUnpacking(self);
    }

    // Parse first element
    var first_elem = try self.parseExpression();
    errdefer first_elem.deinit(self.allocator);

    // Check what follows to determine dict vs set:
    // - Colon → dict literal or dict comprehension
    // - Comma or RBrace → set literal
    if (self.check(.Colon)) {
        // Dict: {key: value, ...} or dict comprehension
        _ = try self.expect(.Colon);
        var first_value = try self.parseExpression();
        errdefer first_value.deinit(self.allocator);

        // Check if this is a dict comprehension: {k: v for k in items} or {k: v async for k in items}
        if (self.check(.For) or self.check(.Async)) {
            return try parseDictComp(self, first_elem, first_value);
        }

        // Regular dict: collect key-value pairs
        var keys = std.ArrayList(ast.Node){};
        errdefer {
            for (keys.items) |*k| k.deinit(self.allocator);
            keys.deinit(self.allocator);
        }

        var values = std.ArrayList(ast.Node){};
        errdefer {
            for (values.items) |*v| v.deinit(self.allocator);
            values.deinit(self.allocator);
        }

        try keys.append(self.allocator, first_elem);
        try values.append(self.allocator, first_value);

        while (self.match(.Comma)) {
            // Allow trailing comma
            if (self.check(.RBrace)) {
                break;
            }

            // Check for dict unpacking: {a: 1, **other}
            if (self.match(.DoubleStar)) {
                var value = try self.parseExpression();
                errdefer value.deinit(self.allocator);
                // None key signals dict unpacking
                try keys.append(self.allocator, ast.Node{ .constant = .{ .value = .{ .none = {} } } });
                try values.append(self.allocator, value);
                continue;
            }

            var key = try self.parseExpression();
            errdefer key.deinit(self.allocator);
            _ = try self.expect(.Colon);
            var value = try self.parseExpression();
            errdefer value.deinit(self.allocator);

            try keys.append(self.allocator, key);
            try values.append(self.allocator, value);
        }

        _ = try self.expect(.RBrace);

        // Success - transfer ownership
        const keys_result = try keys.toOwnedSlice(self.allocator);
        keys = std.ArrayList(ast.Node){}; // Reset
        const values_result = try values.toOwnedSlice(self.allocator);
        values = std.ArrayList(ast.Node){}; // Reset

        return ast.Node{
            .dict = .{
                .keys = keys_result,
                .values = values_result,
            },
        };
    } else {
        // Check for set comprehension: {x for x in items} or {x async for x in items}
        if (self.check(.For) or self.check(.Async)) {
            return try parseSetComp(self, first_elem);
        }

        // Set literal: {item} or {item1, item2, ...}
        var elts = std.ArrayList(ast.Node){};
        errdefer {
            for (elts.items) |*e| e.deinit(self.allocator);
            elts.deinit(self.allocator);
        }

        try elts.append(self.allocator, first_elem);

        while (self.match(.Comma)) {
            // Allow trailing comma
            if (self.check(.RBrace)) {
                break;
            }
            // Handle starred unpacking in set: {a, *b, c}
            var elem = if (self.match(.Star)) blk: {
                var value = try self.parseExpression();
                errdefer value.deinit(self.allocator);
                break :blk ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
            } else try self.parseExpression();
            errdefer elem.deinit(self.allocator);
            try elts.append(self.allocator, elem);
        }

        _ = try self.expect(.RBrace);

        // Success - transfer ownership
        const result = try elts.toOwnedSlice(self.allocator);
        elts = std.ArrayList(ast.Node){}; // Reset

        return ast.Node{
            .set = .{
                .elts = result,
            },
        };
    }
}

/// Parse dict comprehension: {k: v for k in items if cond} or {k: v for x in range(3) for y in range(3)}
/// Also handles async: {k: v async for k in aiter}
pub fn parseDictComp(self: *Parser, key: ast.Node, value: ast.Node) ParseError!ast.Node {
    // We've already parsed the key and value expressions
    // Now parse one or more: for <target> in <iter> [if <condition>]
    var key_node = key;
    errdefer key_node.deinit(self.allocator);
    var value_node = value;
    errdefer value_node.deinit(self.allocator);

    var generators = std.ArrayList(ast.Node.Comprehension){};
    errdefer {
        for (generators.items) |*gen| {
            gen.target.deinit(self.allocator);
            self.allocator.destroy(gen.target);
            gen.iter.deinit(self.allocator);
            self.allocator.destroy(gen.iter);
            for (gen.ifs) |*cond| cond.deinit(self.allocator);
            self.allocator.free(gen.ifs);
        }
        generators.deinit(self.allocator);
    }

    // Parse all "for ... in ..." or "async for ... in ..." clauses
    while (self.check(.For) or self.check(.Async)) {
        _ = self.match(.Async);
        if (!self.match(.For)) break;

        // Parse target (name or tuple of names for unpacking)
        var target = try parseComprehensionTarget(self);
        errdefer target.deinit(self.allocator);
        _ = try self.expect(.In);
        // Use parseOrExpr to stop at 'if' keyword (not treat as ternary conditional)
        var iter = try self.parseOrExpr();
        errdefer iter.deinit(self.allocator);

        // Parse optional if conditions for this generator
        var ifs = std.ArrayList(ast.Node){};
        errdefer {
            for (ifs.items) |*i| i.deinit(self.allocator);
            ifs.deinit(self.allocator);
        }

        while (self.check(.If) and !self.check(.For) and !self.check(.Async)) {
            _ = self.advance();
            // Use parseOrExpr so nested 'if' doesn't get consumed as ternary
            var cond = try self.parseOrExpr();
            errdefer cond.deinit(self.allocator);
            try ifs.append(self.allocator, cond);
        }

        const ifs_slice = try ifs.toOwnedSlice(self.allocator);
        ifs = std.ArrayList(ast.Node){}; // Reset

        try generators.append(self.allocator, ast.Node.Comprehension{
            .target = try self.allocNode(target),
            .iter = try self.allocNode(iter),
            .ifs = ifs_slice,
        });
    }

    _ = try self.expect(.RBrace);

    // Success - transfer ownership
    const gens = try generators.toOwnedSlice(self.allocator);
    generators = std.ArrayList(ast.Node.Comprehension){}; // Reset

    return ast.Node{
        .dictcomp = .{
            .key = try self.allocNode(key_node),
            .value = try self.allocNode(value_node),
            .generators = gens,
        },
    };
}

/// Parse set comprehension: {x for x in items if cond}
/// We use genexp AST node since set comp is equivalent structurally
pub fn parseSetComp(self: *Parser, elt: ast.Node) ParseError!ast.Node {
    // We've already parsed the element expression
    // Now parse one or more: for <target> in <iter> [if <condition>]
    var elt_node = elt;
    errdefer elt_node.deinit(self.allocator);

    var generators = std.ArrayList(ast.Node.Comprehension){};
    errdefer {
        for (generators.items) |*gen| {
            gen.target.deinit(self.allocator);
            self.allocator.destroy(gen.target);
            gen.iter.deinit(self.allocator);
            self.allocator.destroy(gen.iter);
            for (gen.ifs) |*cond| cond.deinit(self.allocator);
            self.allocator.free(gen.ifs);
        }
        generators.deinit(self.allocator);
    }

    // Parse all "for ... in ..." or "async for ... in ..." clauses
    while (self.check(.For) or self.check(.Async)) {
        _ = self.match(.Async);
        if (!self.match(.For)) break;

        // Parse target (name or tuple of names for unpacking)
        var target = try parseComprehensionTarget(self);
        errdefer target.deinit(self.allocator);

        _ = try self.expect(.In);

        // Use parseOrExpr to stop at 'if' keyword (not treat as ternary conditional)
        var iter = try self.parseOrExpr();
        errdefer iter.deinit(self.allocator);

        // Parse any "if" conditions attached to this generator
        var ifs = std.ArrayList(ast.Node){};
        errdefer {
            for (ifs.items) |*cond| cond.deinit(self.allocator);
            ifs.deinit(self.allocator);
        }

        while (self.check(.If) and !self.check(.For) and !self.check(.Async)) {
            _ = self.advance();
            // Use parseOrExpr so nested 'if' doesn't get consumed as ternary
            var cond = try self.parseOrExpr();
            errdefer cond.deinit(self.allocator);
            try ifs.append(self.allocator, cond);
        }

        const ifs_slice = try ifs.toOwnedSlice(self.allocator);
        ifs = std.ArrayList(ast.Node){}; // Reset

        try generators.append(self.allocator, .{
            .target = try self.allocNode(target),
            .iter = try self.allocNode(iter),
            .ifs = ifs_slice,
        });
    }

    _ = try self.expect(.RBrace);

    // Success - transfer ownership
    const gens = try generators.toOwnedSlice(self.allocator);
    generators = std.ArrayList(ast.Node.Comprehension){}; // Reset

    // Use genexp for set comprehension (same structure)
    return ast.Node{
        .genexp = .{
            .elt = try self.allocNode(elt_node),
            .generators = gens,
        },
    };
}

/// Parse dict literal starting with dict unpacking: {**other_dict, key: value, ...}
fn parseDictWithUnpacking(self: *Parser) ParseError!ast.Node {
    var keys = std.ArrayList(ast.Node){};
    errdefer {
        for (keys.items) |*k| k.deinit(self.allocator);
        keys.deinit(self.allocator);
    }

    var values = std.ArrayList(ast.Node){};
    errdefer {
        for (values.items) |*v| v.deinit(self.allocator);
        values.deinit(self.allocator);
    }

    // Parse first **expr
    _ = try self.expect(.DoubleStar);
    var first_value = try self.parseExpression();
    errdefer first_value.deinit(self.allocator);

    // None key signals dict unpacking
    try keys.append(self.allocator, ast.Node{ .constant = .{ .value = .{ .none = {} } } });
    try values.append(self.allocator, first_value);

    while (self.match(.Comma)) {
        // Allow trailing comma
        if (self.check(.RBrace)) {
            break;
        }

        // Check for more dict unpacking
        if (self.match(.DoubleStar)) {
            var value = try self.parseExpression();
            errdefer value.deinit(self.allocator);
            try keys.append(self.allocator, ast.Node{ .constant = .{ .value = .{ .none = {} } } });
            try values.append(self.allocator, value);
            continue;
        }

        // Regular key: value pair
        var key = try self.parseExpression();
        errdefer key.deinit(self.allocator);
        _ = try self.expect(.Colon);
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);

        try keys.append(self.allocator, key);
        try values.append(self.allocator, value);
    }

    _ = try self.expect(.RBrace);

    // Success - transfer ownership
    const keys_result = try keys.toOwnedSlice(self.allocator);
    keys = std.ArrayList(ast.Node){};
    const values_result = try values.toOwnedSlice(self.allocator);
    values = std.ArrayList(ast.Node){};

    return ast.Node{
        .dict = .{
            .keys = keys_result,
            .values = values_result,
        },
    };
}

/// Parse set literal starting with starred unpacking: {*iterable, ...}
fn parseSetWithUnpacking(self: *Parser) ParseError!ast.Node {
    var elts = std.ArrayList(ast.Node){};
    errdefer {
        for (elts.items) |*e| e.deinit(self.allocator);
        elts.deinit(self.allocator);
    }

    // Parse first *expr
    _ = try self.expect(.Star);
    var first_value = try self.parseExpression();
    errdefer first_value.deinit(self.allocator);
    try elts.append(self.allocator, ast.Node{ .starred = .{ .value = try self.allocNode(first_value) } });

    while (self.match(.Comma)) {
        // Allow trailing comma
        if (self.check(.RBrace)) {
            break;
        }

        // Handle more starred expressions
        var elem = if (self.match(.Star)) blk: {
            var value = try self.parseExpression();
            errdefer value.deinit(self.allocator);
            break :blk ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
        } else try self.parseExpression();
        errdefer elem.deinit(self.allocator);
        try elts.append(self.allocator, elem);
    }

    _ = try self.expect(.RBrace);

    // Success - transfer ownership
    const result = try elts.toOwnedSlice(self.allocator);
    elts = std.ArrayList(ast.Node){};

    return ast.Node{
        .set = .{
            .elts = result,
        },
    };
}
