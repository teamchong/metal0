const std = @import("std");
const ast = @import("../ast.zig");
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
    // Must be an identifier followed by :=
    if (self.check(.Ident)) {
        const saved_pos = self.current;
        const ident_tok = self.advance().?;

        if (self.check(.ColonEq)) {
            // It's a named expression
            _ = self.advance(); // consume :=
            const value = try parseConditionalExpr(self); // Parse the value expression

            const target_ptr = try self.allocator.create(ast.Node);
            target_ptr.* = ast.Node{ .name = .{ .id = ident_tok.lexeme } };

            const value_ptr = try self.allocator.create(ast.Node);
            value_ptr.* = value;

            return ast.Node{
                .named_expr = .{
                    .target = target_ptr,
                    .value = value_ptr,
                },
            };
        } else {
            // Not a named expression, restore position
            self.current = saved_pos;
        }
    }

    // Parse the left side (which could be the 'body' of an if_expr)
    const left = try parseOrExpr(self);

    // Check for conditional expression: value if condition else orelse_value
    if (self.match(.If)) {
        const condition = try parseOrExpr(self); // Parse the condition
        _ = try self.expect(.Else); // Expect 'else'
        const orelse_value = try parseConditionalExpr(self); // Right-associative: parse recursively

        const body_ptr = try self.allocator.create(ast.Node);
        body_ptr.* = left;

        const test_ptr = try self.allocator.create(ast.Node);
        test_ptr.* = condition;

        const orelse_ptr = try self.allocator.create(ast.Node);
        orelse_ptr.* = orelse_value;

        return ast.Node{
            .if_expr = .{
                .body = body_ptr,
                .condition = test_ptr,
                .orelse_value = orelse_ptr,
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

    // Lambda can have zero parameters: lambda: 5
    if (!self.check(.Colon)) {
        while (true) {
            if (self.peek()) |tok| {
                if (tok.type == .Ident) {
                    const param_name = self.advance().?.lexeme;

                    // Parse default value if present (e.g., = 0.1)
                    var default_value: ?*ast.Node = null;
                    if (self.match(.Eq)) {
                        const default_expr = try parseOrExpr(self);
                        const default_ptr = try self.allocator.create(ast.Node);
                        default_ptr.* = default_expr;
                        default_value = default_ptr;
                    }

                    try args.append(self.allocator, .{
                        .name = param_name,
                        .type_annotation = null,
                        .default = default_value,
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

    // Consume ':' separator
    _ = try self.expect(.Colon);

    // Parse body (single expression)
    const body_expr = try parseOrExpr(self);
    const body_ptr = try self.allocator.create(ast.Node);
    body_ptr.* = body_expr;

    return ast.Node{
        .lambda = .{
            .args = try args.toOwnedSlice(self.allocator),
            .body = body_ptr,
        },
    };
}
