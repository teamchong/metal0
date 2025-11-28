const std = @import("std");
const ast = @import("ast");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse subscript/slice expression after '[' has been consumed
/// Takes ownership of `value` - cleans it up on error
pub fn parseSubscript(self: *Parser, value: ast.Node) ParseError!ast.Node {
    const node_ptr = self.allocNode(value) catch |err| {
        var v = value;
        v.deinit(self.allocator);
        return err;
    };

    errdefer {
        node_ptr.deinit(self.allocator);
        self.allocator.destroy(node_ptr);
    }

    // Check if it starts with colon (e.g., [:5] or [::2])
    if (self.check(.Colon)) {
        return parseSliceFromStart(self, node_ptr);
    }

    // Check for ellipsis at start: [...]
    if (self.check(.Ellipsis)) {
        return parseMultiDimFromStart(self, node_ptr);
    }

    // Check for starred expression at start: [*Y] for PEP 646 TypeVarTuple unpacking
    if (self.match(.Star)) {
        var starred_value = try self.parseExpression();
        errdefer starred_value.deinit(self.allocator);
        const starred = ast.Node{ .starred = .{ .value = try self.allocNode(starred_value) } };

        // Check for multi-dim: [*Y, Z]
        if (self.check(.Comma)) {
            return parseMultiSubscript(self, node_ptr, starred);
        }

        // Simple starred subscript: [*Y]
        _ = try self.expect(.RBracket);
        return ast.Node{
            .subscript = .{
                .value = node_ptr,
                .slice = .{ .index = try self.allocNode(starred) },
            },
        };
    }

    var lower = try self.parseExpression();
    errdefer lower.deinit(self.allocator);

    if (self.match(.Colon)) {
        return parseSliceWithLower(self, node_ptr, lower);
    } else if (self.check(.Comma)) {
        return parseMultiSubscript(self, node_ptr, lower);
    } else {
        return parseSimpleIndex(self, node_ptr, lower);
    }
}

/// Parse multi-dim starting with ellipsis: [..., idx]
fn parseMultiDimFromStart(self: *Parser, node_ptr: *ast.Node) ParseError!ast.Node {
    var indices = std.ArrayList(ast.Node){};
    defer indices.deinit(self.allocator);

    // First element is ellipsis
    _ = self.advance();
    try indices.append(self.allocator, ast.Node{ .ellipsis_literal = {} });

    while (self.match(.Comma)) {
        if (self.check(.RBracket)) break;
        try indices.append(self.allocator, try parseMultiDimElement(self));
    }

    _ = try self.expect(.RBracket);

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{ .index = try self.allocNode(ast.Node{
                .tuple = .{ .elts = try indices.toOwnedSlice(self.allocator) },
            }) },
        },
    };
}

/// Parse slice starting with colon: [:end] or [:end:step] or [::step] or [:, idx, ...] (numpy 2D)
fn parseSliceFromStart(self: *Parser, node_ptr: *ast.Node) ParseError!ast.Node {
    _ = self.advance(); // consume first colon

    // Check for second colon: [::step] or [::step, ...]
    if (self.check(.Colon)) {
        _ = self.advance();
        const step = if (!self.check(.RBracket) and !self.check(.Comma)) try self.parseExpression() else null;

        // Check for multi-dim: [::step, ...]
        if (self.check(.Comma)) {
            return parseMultiDimFromSlice(self, node_ptr, ast.Node{
                .slice_expr = .{ .lower = null, .upper = null, .step = try self.allocNodeOpt(step) },
            });
        }

        _ = try self.expect(.RBracket);
        return ast.Node{
            .subscript = .{
                .value = node_ptr,
                .slice = .{ .slice = .{ .lower = null, .upper = null, .step = try self.allocNodeOpt(step) } },
            },
        };
    }

    // [:upper] or [:upper:step] or [:]
    const upper = if (!self.check(.RBracket) and !self.check(.Colon) and !self.check(.Comma)) try self.parseExpression() else null;

    // Check for step: [:upper:step]
    const step = if (self.match(.Colon)) blk: {
        if (!self.check(.RBracket) and !self.check(.Comma)) break :blk try self.parseExpression() else break :blk null;
    } else null;

    // Check for multi-dim: [:upper, ...] or [:upper:step, ...]
    if (self.check(.Comma)) {
        return parseMultiDimFromSlice(self, node_ptr, ast.Node{
            .slice_expr = .{ .lower = null, .upper = try self.allocNodeOpt(upper), .step = try self.allocNodeOpt(step) },
        });
    }

    _ = try self.expect(.RBracket);

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{ .slice = .{
                .lower = null,
                .upper = try self.allocNodeOpt(upper),
                .step = try self.allocNodeOpt(step),
            } },
        },
    };
}

/// Parse multi-dim subscript when first element is already a slice
fn parseMultiDimFromSlice(self: *Parser, node_ptr: *ast.Node, first_slice: ast.Node) ParseError!ast.Node {
    var indices = std.ArrayList(ast.Node){};
    defer indices.deinit(self.allocator);
    try indices.append(self.allocator, first_slice);

    while (self.match(.Comma)) {
        if (self.check(.RBracket)) break;
        try indices.append(self.allocator, try parseMultiDimElement(self));
    }

    _ = try self.expect(.RBracket);

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{ .index = try self.allocNode(ast.Node{
                .tuple = .{ .elts = try indices.toOwnedSlice(self.allocator) },
            }) },
        },
    };
}

/// Parse slice with lower bound: [start:] or [start:end] or [start:end:step] or [start:, ...]
fn parseSliceWithLower(self: *Parser, node_ptr: *ast.Node, lower: ast.Node) ParseError!ast.Node {
    const upper = if (!self.check(.RBracket) and !self.check(.Colon) and !self.check(.Comma)) try self.parseExpression() else null;

    // Check for step: [start:end:step]
    const step = if (self.match(.Colon)) blk: {
        if (!self.check(.RBracket) and !self.check(.Comma)) break :blk try self.parseExpression() else break :blk null;
    } else null;

    // Check for multi-dim: [start:, ...] or [start:end, ...] or [start:end:step, ...]
    if (self.check(.Comma)) {
        return parseMultiDimFromSlice(self, node_ptr, ast.Node{
            .slice_expr = .{ .lower = try self.allocNode(lower), .upper = try self.allocNodeOpt(upper), .step = try self.allocNodeOpt(step) },
        });
    }

    _ = try self.expect(.RBracket);

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{ .slice = .{
                .lower = try self.allocNode(lower),
                .upper = try self.allocNodeOpt(upper),
                .step = try self.allocNodeOpt(step),
            } },
        },
    };
}

/// Parse multi-element subscript: arr[0, 1, 2] or arr[0, :] or arr[:42, ..., :24:, 24, 100] (numpy-style)
fn parseMultiSubscript(self: *Parser, node_ptr: *ast.Node, first: ast.Node) ParseError!ast.Node {
    var indices = std.ArrayList(ast.Node){};
    defer indices.deinit(self.allocator);
    try indices.append(self.allocator, first);

    while (self.match(.Comma)) {
        // Allow trailing comma: [0,]
        if (self.check(.RBracket)) break;
        try indices.append(self.allocator, try parseMultiDimElement(self));
    }

    _ = try self.expect(.RBracket);

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{ .index = try self.allocNode(ast.Node{
                .tuple = .{ .elts = try indices.toOwnedSlice(self.allocator) },
            }) },
        },
    };
}

/// Parse a single element in multi-dimensional subscript: can be slice, ellipsis, starred, or expression
fn parseMultiDimElement(self: *Parser) ParseError!ast.Node {
    // Check for ellipsis: [idx, ...]
    if (self.check(.Ellipsis)) {
        _ = self.advance();
        return ast.Node{ .ellipsis_literal = {} };
    }

    // Check for starred expression: [*Y] for PEP 646 TypeVarTuple unpacking
    if (self.match(.Star)) {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        return ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
    }

    // Check for colon-starting slice: [:end] or [:end:step] or [::step] or [:]
    if (self.check(.Colon)) {
        _ = self.advance(); // consume first colon

        // Check for second colon: [::step]
        if (self.check(.Colon)) {
            _ = self.advance();
            const step = if (!self.check(.RBracket) and !self.check(.Comma)) try self.parseExpression() else null;
            return ast.Node{
                .slice_expr = .{ .lower = null, .upper = null, .step = try self.allocNodeOpt(step) },
            };
        }

        // [:upper] or [:upper:step] or [:]
        const upper = if (!self.check(.RBracket) and !self.check(.Colon) and !self.check(.Comma)) try self.parseExpression() else null;

        // Check for step: [:upper:step]
        const step = if (self.match(.Colon)) blk: {
            if (!self.check(.RBracket) and !self.check(.Comma)) break :blk try self.parseExpression() else break :blk null;
        } else null;

        return ast.Node{
            .slice_expr = .{ .lower = null, .upper = try self.allocNodeOpt(upper), .step = try self.allocNodeOpt(step) },
        };
    }

    // Expression, which may be followed by colon to make a slice
    const expr = try self.parseExpression();

    // Check if this becomes a slice: [start:] or [start:end] or [start:end:step]
    if (self.match(.Colon)) {
        const upper = if (!self.check(.RBracket) and !self.check(.Colon) and !self.check(.Comma)) try self.parseExpression() else null;

        const step = if (self.match(.Colon)) blk: {
            if (!self.check(.RBracket) and !self.check(.Comma)) break :blk try self.parseExpression() else break :blk null;
        } else null;

        return ast.Node{
            .slice_expr = .{ .lower = try self.allocNode(expr), .upper = try self.allocNodeOpt(upper), .step = try self.allocNodeOpt(step) },
        };
    }

    return expr;
}

/// Parse simple index: [0]
fn parseSimpleIndex(self: *Parser, node_ptr: *ast.Node, lower: ast.Node) ParseError!ast.Node {
    _ = try self.expect(.RBracket);
    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{ .index = try self.allocNode(lower) },
        },
    };
}
