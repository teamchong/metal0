const std = @import("std");
const ast = @import("ast");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse bitwise OR expression
pub fn parseBitOr(self: *Parser) ParseError!ast.Node {
    var left = try parseBitXor(self);
    errdefer left.deinit(self.allocator);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Pipe)) {
            op = .BitOr;
        }

        if (op == null) break;

        var right = try parseBitXor(self);
        errdefer right.deinit(self.allocator);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse bitwise XOR expression
pub fn parseBitXor(self: *Parser) ParseError!ast.Node {
    var left = try parseBitAnd(self);
    errdefer left.deinit(self.allocator);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Caret)) {
            op = .BitXor;
        }

        if (op == null) break;

        var right = try parseBitAnd(self);
        errdefer right.deinit(self.allocator);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse bitwise AND expression
pub fn parseBitAnd(self: *Parser) ParseError!ast.Node {
    var left = try parseShift(self);
    errdefer left.deinit(self.allocator);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Ampersand)) {
            op = .BitAnd;
        }

        if (op == null) break;

        var right = try parseShift(self);
        errdefer right.deinit(self.allocator);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse bitwise shift operators: << and >>
pub fn parseShift(self: *Parser) ParseError!ast.Node {
    var left = try parseAddSub(self);
    errdefer left.deinit(self.allocator);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.LtLt)) {
            op = .LShift;
        } else if (self.match(.GtGt)) {
            op = .RShift;
        }

        if (op == null) break;

        var right = try parseAddSub(self);
        errdefer right.deinit(self.allocator);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse addition and subtraction
pub fn parseAddSub(self: *Parser) ParseError!ast.Node {
    var left = try parseMulDiv(self);
    errdefer left.deinit(self.allocator);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Plus)) {
            op = .Add;
        } else if (self.match(.Minus)) {
            op = .Sub;
        }

        if (op == null) break;

        var right = try parseMulDiv(self);
        errdefer right.deinit(self.allocator);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse multiplication, division, floor division, and modulo
pub fn parseMulDiv(self: *Parser) ParseError!ast.Node {
    var left = try parsePower(self);
    errdefer left.deinit(self.allocator);

    while (true) {
        var op: ?ast.Operator = null;

        if (self.match(.Star)) {
            op = .Mult;
        } else if (self.match(.Slash)) {
            op = .Div;
        } else if (self.match(.DoubleSlash)) {
            op = .FloorDiv;
        } else if (self.match(.Percent)) {
            op = .Mod;
        }

        if (op == null) break;

        var right = try parsePower(self);
        errdefer right.deinit(self.allocator);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        left = ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = op.?,
                .right = right_ptr,
            },
        };
    }

    return left;
}

/// Parse power (exponentiation) - right associative
pub fn parsePower(self: *Parser) ParseError!ast.Node {
    var left = try self.parsePostfix();
    errdefer left.deinit(self.allocator);

    if (self.match(.DoubleStar)) {
        var right = try parsePower(self); // Right associative
        errdefer right.deinit(self.allocator);

        const left_ptr = try self.allocator.create(ast.Node);
        left_ptr.* = left;

        const right_ptr = try self.allocator.create(ast.Node);
        right_ptr.* = right;

        return ast.Node{
            .binop = .{
                .left = left_ptr,
                .op = .Pow,
                .right = right_ptr,
            },
        };
    }

    return left;
}
