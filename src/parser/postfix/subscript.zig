const std = @import("std");
const ast = @import("../../ast.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse subscript/slice expression after '[' has been consumed
pub fn parseSubscript(self: *Parser, value: ast.Node) ParseError!ast.Node {
    const node_ptr = try self.allocator.create(ast.Node);
    node_ptr.* = value;

    // Check if it starts with colon (e.g., [:5] or [::2])
    if (self.check(.Colon)) {
        return parseSliceFromStart(self, node_ptr);
    }

    const lower = try self.parseExpression();

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

        const step_ptr = if (step) |s| blk: {
            const ptr = try self.allocator.create(ast.Node);
            ptr.* = s;
            break :blk ptr;
        } else null;

        return ast.Node{
            .subscript = .{
                .value = node_ptr,
                .slice = .{
                    .slice = .{
                        .lower = null,
                        .upper = null,
                        .step = step_ptr,
                    },
                },
            },
        };
    }

    // [:upper] or [:upper:step]
    const upper = if (!self.check(.RBracket) and !self.check(.Colon)) try self.parseExpression() else null;

    // Check for step: [:upper:step]
    const step = if (self.match(.Colon)) blk: {
        if (!self.check(.RBracket)) {
            break :blk try self.parseExpression();
        } else {
            break :blk null;
        }
    } else null;

    _ = try self.expect(.RBracket);

    const upper_ptr = if (upper) |u| blk: {
        const ptr = try self.allocator.create(ast.Node);
        ptr.* = u;
        break :blk ptr;
    } else null;

    const step_ptr = if (step) |s| blk: {
        const ptr = try self.allocator.create(ast.Node);
        ptr.* = s;
        break :blk ptr;
    } else null;

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{
                .slice = .{
                    .lower = null,
                    .upper = upper_ptr,
                    .step = step_ptr,
                },
            },
        },
    };
}

/// Parse slice with lower bound: [start:] or [start:end] or [start:end:step]
fn parseSliceWithLower(self: *Parser, node_ptr: *ast.Node, lower: ast.Node) ParseError!ast.Node {
    const upper = if (!self.check(.RBracket) and !self.check(.Colon)) try self.parseExpression() else null;

    // Check for step: [start:end:step]
    const step = if (self.match(.Colon)) blk: {
        if (!self.check(.RBracket)) {
            break :blk try self.parseExpression();
        } else {
            break :blk null;
        }
    } else null;

    _ = try self.expect(.RBracket);

    const lower_ptr = try self.allocator.create(ast.Node);
    lower_ptr.* = lower;

    const upper_ptr = if (upper) |u| blk: {
        const ptr = try self.allocator.create(ast.Node);
        ptr.* = u;
        break :blk ptr;
    } else null;

    const step_ptr = if (step) |s| blk: {
        const ptr = try self.allocator.create(ast.Node);
        ptr.* = s;
        break :blk ptr;
    } else null;

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{
                .slice = .{
                    .lower = lower_ptr,
                    .upper = upper_ptr,
                    .step = step_ptr,
                },
            },
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

    const index_ptr = try self.allocator.create(ast.Node);
    index_ptr.* = ast.Node{
        .tuple = .{ .elts = try indices.toOwnedSlice(self.allocator) },
    };

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{ .index = index_ptr },
        },
    };
}

/// Parse simple index: [0]
fn parseSimpleIndex(self: *Parser, node_ptr: *ast.Node, lower: ast.Node) ParseError!ast.Node {
    _ = try self.expect(.RBracket);

    const index_ptr = try self.allocator.create(ast.Node);
    index_ptr.* = lower;

    return ast.Node{
        .subscript = .{
            .value = node_ptr,
            .slice = .{ .index = index_ptr },
        },
    };
}
