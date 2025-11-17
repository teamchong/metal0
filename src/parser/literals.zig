const std = @import("std");
const ast = @import("../ast.zig");
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
    const first_elt = try self.parseExpression();

    // Check if this is a list comprehension: [x for x in items]
    if (self.check(.For)) {
        return try parseListComp(self, first_elt);
    }

    // Regular list: collect elements
    var elts = std.ArrayList(ast.Node){};
    defer elts.deinit(self.allocator);
    try elts.append(self.allocator, first_elt);

    while (self.match(.Comma)) {
        // Allow trailing comma
        if (self.check(.RBracket)) {
            break;
        }
        const elt = try self.parseExpression();
        try elts.append(self.allocator, elt);
    }

    _ = try self.expect(.RBracket);

    return ast.Node{
        .list = .{
            .elts = try elts.toOwnedSlice(self.allocator),
        },
    };
}

/// Parse list comprehension: [x for x in items if cond] or [x*y for x in range(3) for y in range(3)]
pub fn parseListComp(self: *Parser, elt: ast.Node) ParseError!ast.Node {
    // We've already parsed the element expression
    // Now parse one or more: for <target> in <iter> [if <condition>]

    var generators = std.ArrayList(ast.Node.Comprehension){};
    defer generators.deinit(self.allocator);

    // Parse all "for ... in ..." clauses
    while (self.match(.For)) {
        // Parse target as primary (just a name, not a full expression)
        const target = try self.parsePrimary();
        _ = try self.expect(.In);
        const iter = try self.parseExpression();

        // Parse optional if conditions for this generator
        var ifs = std.ArrayList(ast.Node){};
        defer ifs.deinit(self.allocator);

        while (self.check(.If) and !self.check(.For)) {
            _ = self.advance();
            const cond = try self.parseExpression();
            try ifs.append(self.allocator, cond);
        }

        // Allocate nodes on heap
        const target_ptr = try self.allocator.create(ast.Node);
        target_ptr.* = target;

        const iter_ptr = try self.allocator.create(ast.Node);
        iter_ptr.* = iter;

        try generators.append(self.allocator, ast.Node.Comprehension{
            .target = target_ptr,
            .iter = iter_ptr,
            .ifs = try ifs.toOwnedSlice(self.allocator),
        });
    }

    _ = try self.expect(.RBracket);

    // Allocate element on heap
    const elt_ptr = try self.allocator.create(ast.Node);
    elt_ptr.* = elt;

    return ast.Node{
        .listcomp = .{
            .elt = elt_ptr,
            .generators = try generators.toOwnedSlice(self.allocator),
        },
    };
}

/// Parse dictionary literal: {key: value, ...}
pub fn parseDict(self: *Parser) ParseError!ast.Node {
    _ = try self.expect(.LBrace);

    var keys = std.ArrayList(ast.Node){};
    defer keys.deinit(self.allocator);

    var values = std.ArrayList(ast.Node){};
    defer values.deinit(self.allocator);

    while (!self.match(.RBrace)) {
        const key = try self.parseExpression();
        _ = try self.expect(.Colon);
        const value = try self.parseExpression();

        try keys.append(self.allocator, key);
        try values.append(self.allocator, value);

        if (!self.match(.Comma)) {
            _ = try self.expect(.RBrace);
            break;
        }
    }

    return ast.Node{
        .dict = .{
            .keys = try keys.toOwnedSlice(self.allocator),
            .values = try values.toOwnedSlice(self.allocator),
        },
    };
}
