const std = @import("std");
const ast = @import("ast");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse function call after '(' has been consumed
pub fn parseCall(self: *Parser, func: ast.Node) ParseError!ast.Node {
    var fn_node = func;
    errdefer fn_node.deinit(self.allocator);

    var args = std.ArrayList(ast.Node){};
    errdefer {
        for (args.items) |*arg| arg.deinit(self.allocator);
        args.deinit(self.allocator);
    }

    var keyword_args = std.ArrayList(ast.Node.KeywordArg){};
    errdefer {
        for (keyword_args.items) |*kw| kw.value.deinit(self.allocator);
        keyword_args.deinit(self.allocator);
    }

    while (!self.match(.RParen)) {
        // Check for ** operator for kwargs unpacking: func(**kwargs)
        // Must check DoubleStar before Star since ** starts with *
        if (self.match(.DoubleStar)) {
            var arg = try parseDoubleStarArg(self);
            errdefer arg.deinit(self.allocator);
            try args.append(self.allocator, arg);
        } else if (self.match(.Star)) {
            // Check for * operator for unpacking: func(*args)
            var arg = try parseStarArg(self);
            errdefer arg.deinit(self.allocator);
            try args.append(self.allocator, arg);
        } else {
            // Check if this is a keyword argument (name=value)
            try parsePositionalOrKeywordArg(self, &args, &keyword_args);
        }

        if (!self.match(.Comma)) {
            _ = try self.expect(.RParen);
            break;
        }
    }

    var func_ptr: ?*ast.Node = null;
    errdefer if (func_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    func_ptr = try self.allocator.create(ast.Node);
    func_ptr.?.* = fn_node;

    // Success - transfer ownership
    const final_func = func_ptr.?;
    func_ptr = null;
    const final_args = try args.toOwnedSlice(self.allocator);
    args = std.ArrayList(ast.Node){}; // Reset
    const final_kwargs = try keyword_args.toOwnedSlice(self.allocator);
    keyword_args = std.ArrayList(ast.Node.KeywordArg){}; // Reset

    return ast.Node{
        .call = .{
            .func = final_func,
            .args = final_args,
            .keyword_args = final_kwargs,
        },
    };
}

/// Parse **kwargs unpacking argument
fn parseDoubleStarArg(self: *Parser) ParseError!ast.Node {
    var value = try self.parseExpression();
    errdefer value.deinit(self.allocator);

    var value_ptr: ?*ast.Node = null;
    errdefer if (value_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    value_ptr = try self.allocator.create(ast.Node);
    value_ptr.?.* = value;

    // Success - transfer ownership
    const final_value = value_ptr.?;
    value_ptr = null;

    return ast.Node{
        .double_starred = .{
            .value = final_value,
        },
    };
}

/// Parse *args unpacking argument
fn parseStarArg(self: *Parser) ParseError!ast.Node {
    var value = try self.parseExpression();
    errdefer value.deinit(self.allocator);

    var value_ptr: ?*ast.Node = null;
    errdefer if (value_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    value_ptr = try self.allocator.create(ast.Node);
    value_ptr.?.* = value;

    // Success - transfer ownership
    const final_value = value_ptr.?;
    value_ptr = null;

    return ast.Node{
        .starred = .{
            .value = final_value,
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
            var value = try self.parseExpression();
            errdefer value.deinit(self.allocator);
            try keyword_args.append(self.allocator, .{
                .name = name_tok.lexeme,
                .value = value,
            });
        } else {
            // Not a keyword arg, restore position and parse as normal expression
            self.current = saved_pos;
            var arg = try self.parseExpression();
            errdefer arg.deinit(self.allocator);
            try args.append(self.allocator, arg);
        }
    } else {
        var arg = try self.parseExpression();
        errdefer arg.deinit(self.allocator);
        try args.append(self.allocator, arg);
    }
}
