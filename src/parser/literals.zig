const std = @import("std");
const ast = @import("ast");
const lexer = @import("../lexer.zig");
const ParseError = @import("../parser.zig").ParseError;
const Parser = @import("../parser.zig").Parser;

/// Parse a list literal: [1, 2, 3] or list comprehension: [x for x in items]
pub fn parseList(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.LBracket);

    // Empty list
    if (self.match(.RBracket)) {
        return ast.Node{
            .list = .{
                .elts = &[_]ast.Node{},
            },
        };
    }

    // Parse first element
    var first_elt = try self.parseExpression();
    errdefer first_elt.deinit(self.allocator);

    // Check if this is a list comprehension: [x for x in items]
    if (self.check(.For)) {
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
        // Allow trailing comma
        if (self.check(.RBracket)) {
            break;
        }
        var elt = try self.parseExpression();
        errdefer elt.deinit(self.allocator);
        try elts.append(self.allocator, elt);
    }

    _ = try self.expect(.RBracket);

    // Success - transfer ownership
    const result = try elts.toOwnedSlice(self.allocator);
    elts = std.ArrayList(ast.Node){}; // Reset

    return ast.Node{
        .list = .{
            .elts = result,
        },
    };
}

/// Parse list comprehension: [x for x in items if cond] or [x*y for x in range(3) for y in range(3)]
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

    // Parse all "for ... in ..." clauses
    while (self.match(.For)) {
        // Parse target as primary (just a name, not a full expression)
        var target = try self.parsePrimary();
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

        while (self.check(.If) and !self.check(.For)) {
            _ = self.advance();
            // Use parseOrExpr so nested 'if' doesn't get consumed as ternary
            var cond = try self.parseOrExpr();
            errdefer cond.deinit(self.allocator);
            try ifs.append(self.allocator, cond);
        }

        // Allocate nodes on heap
        const target_ptr = try self.allocator.create(ast.Node);
        target_ptr.* = target;

        const iter_ptr = try self.allocator.create(ast.Node);
        iter_ptr.* = iter;

        const ifs_slice = try ifs.toOwnedSlice(self.allocator);
        ifs = std.ArrayList(ast.Node){}; // Reset

        try generators.append(self.allocator, ast.Node.Comprehension{
            .target = target_ptr,
            .iter = iter_ptr,
            .ifs = ifs_slice,
        });
    }

    _ = try self.expect(.RBracket);

    // Allocate element on heap
    const elt_ptr = try self.allocator.create(ast.Node);
    elt_ptr.* = element;

    // Success - transfer ownership
    const gens = try generators.toOwnedSlice(self.allocator);
    generators = std.ArrayList(ast.Node.Comprehension){}; // Reset

    return ast.Node{
        .listcomp = .{
            .elt = elt_ptr,
            .generators = gens,
        },
    };
}

/// Parse dictionary or set literal: {key: value, ...} or {item, ...}
/// Also handles dict comprehensions
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

        // Check if this is a dict comprehension: {k: v for k in items}
        if (self.check(.For)) {
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
            var elem = try self.parseExpression();
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

    // Parse all "for ... in ..." clauses
    while (self.match(.For)) {
        // Parse target as primary (just a name, not a full expression)
        var target = try self.parsePrimary();
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

        while (self.check(.If) and !self.check(.For)) {
            _ = self.advance();
            // Use parseOrExpr so nested 'if' doesn't get consumed as ternary
            var cond = try self.parseOrExpr();
            errdefer cond.deinit(self.allocator);
            try ifs.append(self.allocator, cond);
        }

        // Allocate nodes on heap
        const target_ptr = try self.allocator.create(ast.Node);
        target_ptr.* = target;

        const iter_ptr = try self.allocator.create(ast.Node);
        iter_ptr.* = iter;

        const ifs_slice = try ifs.toOwnedSlice(self.allocator);
        ifs = std.ArrayList(ast.Node){}; // Reset

        try generators.append(self.allocator, ast.Node.Comprehension{
            .target = target_ptr,
            .iter = iter_ptr,
            .ifs = ifs_slice,
        });
    }

    _ = try self.expect(.RBrace);

    // Allocate key and value on heap
    const key_ptr = try self.allocator.create(ast.Node);
    key_ptr.* = key_node;

    const value_ptr = try self.allocator.create(ast.Node);
    value_ptr.* = value_node;

    // Success - transfer ownership
    const gens = try generators.toOwnedSlice(self.allocator);
    generators = std.ArrayList(ast.Node.Comprehension){}; // Reset

    return ast.Node{
        .dictcomp = .{
            .key = key_ptr,
            .value = value_ptr,
            .generators = gens,
        },
    };
}
