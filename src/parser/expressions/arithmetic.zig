const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse bitwise OR expression
pub fn parseBitOr(self: *Parser) ParseError!ast.Node {
    return self.parseBinOp(parseBitXor, &.{.{ .token = .Pipe, .op = .BitOr }});
}

/// Parse bitwise XOR expression
pub fn parseBitXor(self: *Parser) ParseError!ast.Node {
    return self.parseBinOp(parseBitAnd, &.{.{ .token = .Caret, .op = .BitXor }});
}

/// Parse bitwise AND expression
pub fn parseBitAnd(self: *Parser) ParseError!ast.Node {
    return self.parseBinOp(parseShift, &.{.{ .token = .Ampersand, .op = .BitAnd }});
}

/// Parse bitwise shift operators: << and >>
pub fn parseShift(self: *Parser) ParseError!ast.Node {
    return self.parseBinOp(parseAddSub, &.{
        .{ .token = .LtLt, .op = .LShift },
        .{ .token = .GtGt, .op = .RShift },
    });
}

/// Parse addition and subtraction
pub fn parseAddSub(self: *Parser) ParseError!ast.Node {
    return self.parseBinOp(parseMulDiv, &.{
        .{ .token = .Plus, .op = .Add },
        .{ .token = .Minus, .op = .Sub },
    });
}

/// Parse multiplication, division, floor division, modulo, and matrix multiplication
pub fn parseMulDiv(self: *Parser) ParseError!ast.Node {
    return self.parseBinOp(parseFactor, &.{
        .{ .token = .Star, .op = .Mult },
        .{ .token = .At, .op = .MatMul },
        .{ .token = .Slash, .op = .Div },
        .{ .token = .DoubleSlash, .op = .FloorDiv },
        .{ .token = .Percent, .op = .Mod },
    });
}

/// Parse unary factor: +, -, ~ operators (binds less tightly than **)
/// Python grammar: factor: ('+' | '-' | '~') factor | power
pub fn parseFactor(self: *Parser) ParseError!ast.Node {
    if (self.peek()) |tok| {
        switch (tok.type) {
            .Minus => {
                _ = self.advance();
                var operand = try parseFactor(self); // Recurse to handle --x, -~x, etc.
                errdefer operand.deinit(self.allocator);
                return ast.Node{ .unaryop = .{ .op = .USub, .operand = try self.allocNode(operand) } };
            },
            .Plus => {
                _ = self.advance();
                var operand = try parseFactor(self);
                errdefer operand.deinit(self.allocator);
                return ast.Node{ .unaryop = .{ .op = .UAdd, .operand = try self.allocNode(operand) } };
            },
            .Tilde => {
                _ = self.advance();
                var operand = try parseFactor(self);
                errdefer operand.deinit(self.allocator);
                return ast.Node{ .unaryop = .{ .op = .Invert, .operand = try self.allocNode(operand) } };
            },
            else => {},
        }
    }
    return parsePower(self);
}

/// Parse power (exponentiation) - right associative
/// Python grammar: power: await_primary ['**' factor]
pub fn parsePower(self: *Parser) ParseError!ast.Node {
    var left = try self.parsePostfix();
    errdefer left.deinit(self.allocator);

    if (self.match(.DoubleStar)) {
        var right = try parseFactor(self); // RHS is factor, so -2**3**2 = -(2**(3**2))
        errdefer right.deinit(self.allocator);

        return ast.Node{ .binop = .{
            .left = try self.allocNode(left),
            .op = .Pow,
            .right = try self.allocNode(right),
        } };
    }

    return left;
}
