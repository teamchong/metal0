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

/// Parse multiplication, division, floor division, and modulo
pub fn parseMulDiv(self: *Parser) ParseError!ast.Node {
    return self.parseBinOp(parsePower, &.{
        .{ .token = .Star, .op = .Mult },
        .{ .token = .Slash, .op = .Div },
        .{ .token = .DoubleSlash, .op = .FloorDiv },
        .{ .token = .Percent, .op = .Mod },
    });
}

/// Parse power (exponentiation) - right associative
pub fn parsePower(self: *Parser) ParseError!ast.Node {
    var left = try self.parsePostfix();
    errdefer left.deinit(self.allocator);

    if (self.match(.DoubleStar)) {
        var right = try parsePower(self); // Right associative - recurse
        errdefer right.deinit(self.allocator);

        return ast.Node{ .binop = .{
            .left = try self.allocNode(left),
            .op = .Pow,
            .right = try self.allocNode(right),
        } };
    }

    return left;
}
