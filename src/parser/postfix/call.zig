const std = @import("std");
const ast = @import("../../ast.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse function call after '(' has been consumed
pub fn parseCall(self: *Parser, func: ast.Node) ParseError!ast.Node {
    var args = std.ArrayList(ast.Node){};
    defer args.deinit(self.allocator);
    var keyword_args = std.ArrayList(ast.Node.KeywordArg){};
    defer keyword_args.deinit(self.allocator);

    while (!self.match(.RParen)) {
        // Check for ** operator for kwargs unpacking: func(**kwargs)
        // Must check DoubleStar before Star since ** starts with *
        if (self.match(.DoubleStar)) {
            try args.append(self.allocator, try parseDoubleStarArg(self));
        } else if (self.match(.Star)) {
            // Check for * operator for unpacking: func(*args)
            try args.append(self.allocator, try parseStarArg(self));
        } else {
            // Check if this is a keyword argument (name=value)
            try parsePositionalOrKeywordArg(self, &args, &keyword_args);
        }

        if (!self.match(.Comma)) {
            _ = try self.expect(.RParen);
            break;
        }
    }

    const func_ptr = try self.allocator.create(ast.Node);
    func_ptr.* = func;

    return ast.Node{
        .call = .{
            .func = func_ptr,
            .args = try args.toOwnedSlice(self.allocator),
            .keyword_args = try keyword_args.toOwnedSlice(self.allocator),
        },
    };
}

/// Parse **kwargs unpacking argument
fn parseDoubleStarArg(self: *Parser) ParseError!ast.Node {
    const value = try self.parseExpression();
    const value_ptr = try self.allocator.create(ast.Node);
    value_ptr.* = value;

    return ast.Node{
        .double_starred = .{
            .value = value_ptr,
        },
    };
}

/// Parse *args unpacking argument
fn parseStarArg(self: *Parser) ParseError!ast.Node {
    const value = try self.parseExpression();
    const value_ptr = try self.allocator.create(ast.Node);
    value_ptr.* = value;

    return ast.Node{
        .starred = .{
            .value = value_ptr,
        },
    };
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
            const value = try self.parseExpression();
            try keyword_args.append(self.allocator, .{
                .name = name_tok.lexeme,
                .value = value,
            });
        } else {
            // Not a keyword arg, restore position and parse as normal expression
            self.current = saved_pos;
            const arg = try self.parseExpression();
            try args.append(self.allocator, arg);
        }
    } else {
        const arg = try self.parseExpression();
        try args.append(self.allocator, arg);
    }
}
