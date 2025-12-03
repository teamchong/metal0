const std = @import("std");
const ast = @import("ast");
const lexer = @import("../lexer.zig");
const ParseError = @import("../parser.zig").ParseError;
const Parser = @import("../parser.zig").Parser;

// Re-export submodules
pub const logical = @import("expressions/logical.zig");
pub const arithmetic = @import("expressions/arithmetic.zig");

// Re-export commonly used functions
pub const parseOrExpr = logical.parseOrExpr;
pub const parseAndExpr = logical.parseAndExpr;
pub const parseNotExpr = logical.parseNotExpr;
pub const parseComparison = logical.parseComparison;
pub const parseBitOr = arithmetic.parseBitOr;
pub const parseBitXor = arithmetic.parseBitXor;
pub const parseBitAnd = arithmetic.parseBitAnd;
pub const parseShift = arithmetic.parseShift;
pub const parseAddSub = arithmetic.parseAddSub;
pub const parseMulDiv = arithmetic.parseMulDiv;
pub const parsePower = arithmetic.parsePower;

/// Parse conditional expression (ternary): value if condition else orelse_value
/// This has the lowest precedence among expressions
pub fn parseConditionalExpr(self: *Parser) ParseError!ast.Node {
    // Check for named expression (walrus operator): identifier :=
    if (self.check(.Ident)) {
        const saved_pos = self.current;
        const ident_tok = self.advance().?;

        if (self.check(.ColonEq)) {
            _ = self.advance(); // consume :=
            var value = try parseConditionalExpr(self);
            errdefer value.deinit(self.allocator);

            return ast.Node{
                .named_expr = .{
                    .target = try self.allocNode(ast.Node{ .name = .{ .id = ident_tok.lexeme } }),
                    .value = try self.allocNode(value),
                },
            };
        } else {
            self.current = saved_pos;
        }
    }

    var left = try parseOrExpr(self);
    errdefer left.deinit(self.allocator);

    // Check for conditional expression: value if condition else orelse_value
    if (self.match(.If)) {
        var condition = try parseOrExpr(self);
        errdefer condition.deinit(self.allocator);
        _ = try self.expect(.Else);
        var orelse_value = try parseConditionalExpr(self);
        errdefer orelse_value.deinit(self.allocator);

        return ast.Node{
            .if_expr = .{
                .body = try self.allocNode(left),
                .condition = try self.allocNode(condition),
                .orelse_value = try self.allocNode(orelse_value),
            },
        };
    }

    return left;
}

/// Parse lambda expression: lambda x, y: x + y
pub fn parseLambda(self: *Parser) ParseError!ast.Node {
    // Consume 'lambda' keyword
    _ = try self.expect(.Lambda);

    // Parse parameters (comma-separated until ':')
    var args = std.ArrayList(ast.Arg){};
    errdefer {
        for (args.items) |arg| {
            if (arg.default) |d| {
                d.deinit(self.allocator);
                self.allocator.destroy(d);
            }
        }
        args.deinit(self.allocator);
    }

    // Lambda can have zero parameters: lambda: 5
    if (!self.check(.Colon)) {
        while (true) {
            if (self.peek()) |tok| {
                // Handle **kwargs in lambda
                if (tok.type == .DoubleStar) {
                    _ = self.advance(); // consume **
                    const param_name = (try self.expect(.Ident)).lexeme;
                    // Store as **name to indicate it's kwargs
                    try args.append(self.allocator, .{
                        .name = param_name,
                        .type_annotation = null,
                        .default = null,
                    });
                    // **kwargs must be last - consume optional trailing comma, then break
                    _ = self.match(.Comma);
                    break;
                }
                // Handle *args or bare * (keyword-only marker) in lambda
                if (tok.type == .Star) {
                    _ = self.advance(); // consume *
                    // Check if this is *args or bare * (keyword-only marker)
                    if (self.check(.Ident)) {
                        const param_name = self.advance().?.lexeme;
                        try args.append(self.allocator, .{
                            .name = param_name,
                            .type_annotation = null,
                            .default = null,
                        });
                    }
                    // else: bare * is keyword-only marker, just skip it
                    if (self.match(.Comma)) {
                        continue;
                    } else {
                        break;
                    }
                }
                // Handle / (positional-only marker) in lambda
                if (tok.type == .Slash) {
                    _ = self.advance(); // consume /
                    // Just a marker for positional-only, continue parsing
                    if (self.match(.Comma)) {
                        continue;
                    } else {
                        break;
                    }
                }
                if (tok.type == .Ident) {
                    const param_name = self.advance().?.lexeme;

                    // Parse default value if present (e.g., = 0.1)
                    var default_expr: ?ast.Node = null;
                    if (self.match(.Eq)) {
                        default_expr = try parseOrExpr(self);
                    }
                    errdefer if (default_expr) |*d| d.deinit(self.allocator);

                    try args.append(self.allocator, .{
                        .name = param_name,
                        .type_annotation = null,
                        .default = try self.allocNodeOpt(default_expr),
                    });

                    if (self.match(.Comma)) {
                        continue;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            } else {
                return error.UnexpectedEof;
            }
        }
    }

    _ = try self.expect(.Colon);

    var body_expr = try parseOrExpr(self);
    errdefer body_expr.deinit(self.allocator);

    const final_args = try args.toOwnedSlice(self.allocator);
    args = std.ArrayList(ast.Arg){};

    return ast.Node{
        .lambda = .{ .args = final_args, .body = try self.allocNode(body_expr) },
    };
}
