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

/// Parse slice starting with colon: [:end] or [:end:step] or [::step]
fn parseSliceFromStart(self: *Parser, node_ptr: *ast.Node) ParseError!ast.Node {
    _ = self.advance(); // consume first colon

    // Check for second colon: [::step]
    if (self.check(.Colon)) {
        _ = self.advance();
        const step = if (!self.check(.RBracket)) try self.parseExpression() else null;
        _ = try self.expect(.RBracket);

        return ast.Node{
            .subscript = .{
                .value = node_ptr,
                .slice = .{ .slice = .{ .lower = null, .upper = null, .step = try self.allocNodeOpt(step) } },
            },
        };
    }

    // [:upper] or [:upper:step]
    const upper = if (!self.check(.RBracket) and !self.check(.Colon)) try self.parseExpression() else null;

    // Check for step: [:upper:step]
    const step = if (self.match(.Colon)) blk: {
        if (!self.check(.RBracket)) break :blk try self.parseExpression() else break :blk null;
    } else null;

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

/// Parse slice with lower bound: [start:] or [start:end] or [start:end:step]
fn parseSliceWithLower(self: *Parser, node_ptr: *ast.Node, lower: ast.Node) ParseError!ast.Node {
    const upper = if (!self.check(.RBracket) and !self.check(.Colon)) try self.parseExpression() else null;

    // Check for step: [start:end:step]
    const step = if (self.match(.Colon)) blk: {
        if (!self.check(.RBracket)) break :blk try self.parseExpression() else break :blk null;
    } else null;

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

/// Parse multi-element subscript: arr[0, 1, 2] (numpy-style)
fn parseMultiSubscript(self: *Parser, node_ptr: *ast.Node, first: ast.Node) ParseError!ast.Node {
    var indices = std.ArrayList(ast.Node){};
    defer indices.deinit(self.allocator);
    try indices.append(self.allocator, first);

    while (self.match(.Comma)) {
        // Allow trailing comma: [0,]
        if (self.check(.RBracket)) break;
        try indices.append(self.allocator, try self.parseExpression());
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
