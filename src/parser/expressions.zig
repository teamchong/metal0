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
    // Must be an identifier followed by :=
    if (self.check(.Ident)) {
        const saved_pos = self.current;
        const ident_tok = self.advance().?;

        if (self.check(.ColonEq)) {
            // It's a named expression
            _ = self.advance(); // consume :=
            var value = try parseConditionalExpr(self); // Parse the value expression
            errdefer value.deinit(self.allocator);

            var target_ptr: ?*ast.Node = null;
            errdefer if (target_ptr) |ptr| {
                ptr.deinit(self.allocator);
                self.allocator.destroy(ptr);
            };

            var value_ptr: ?*ast.Node = null;
            errdefer if (value_ptr) |ptr| {
                ptr.deinit(self.allocator);
                self.allocator.destroy(ptr);
            };

            target_ptr = try self.allocator.create(ast.Node);
            target_ptr.?.* = ast.Node{ .name = .{ .id = ident_tok.lexeme } };

            value_ptr = try self.allocator.create(ast.Node);
            value_ptr.?.* = value;

            // Success - transfer ownership
            const final_target = target_ptr.?;
            target_ptr = null;
            const final_value = value_ptr.?;
            value_ptr = null;

            return ast.Node{
                .named_expr = .{
                    .target = final_target,
                    .value = final_value,
                },
            };
        } else {
            // Not a named expression, restore position
            self.current = saved_pos;
        }
    }

    // Parse the left side (which could be the 'body' of an if_expr)
    var left = try parseOrExpr(self);
    errdefer left.deinit(self.allocator);

    // Check for conditional expression: value if condition else orelse_value
    if (self.match(.If)) {
        var condition = try parseOrExpr(self); // Parse the condition
        errdefer condition.deinit(self.allocator);
        _ = try self.expect(.Else); // Expect 'else'
        var orelse_value = try parseConditionalExpr(self); // Right-associative: parse recursively
        errdefer orelse_value.deinit(self.allocator);

        var body_ptr: ?*ast.Node = null;
        errdefer if (body_ptr) |ptr| {
            ptr.deinit(self.allocator);
            self.allocator.destroy(ptr);
        };

        var test_ptr: ?*ast.Node = null;
        errdefer if (test_ptr) |ptr| {
            ptr.deinit(self.allocator);
            self.allocator.destroy(ptr);
        };

        var orelse_ptr: ?*ast.Node = null;
        errdefer if (orelse_ptr) |ptr| {
            ptr.deinit(self.allocator);
            self.allocator.destroy(ptr);
        };

        body_ptr = try self.allocator.create(ast.Node);
        body_ptr.?.* = left;

        test_ptr = try self.allocator.create(ast.Node);
        test_ptr.?.* = condition;

        orelse_ptr = try self.allocator.create(ast.Node);
        orelse_ptr.?.* = orelse_value;

        // Success - transfer ownership
        const final_body = body_ptr.?;
        body_ptr = null;
        const final_test = test_ptr.?;
        test_ptr = null;
        const final_orelse = orelse_ptr.?;
        orelse_ptr = null;

        return ast.Node{
            .if_expr = .{
                .body = final_body,
                .condition = final_test,
                .orelse_value = final_orelse,
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
                    // **kwargs must be last, break out
                    break;
                }
                // Handle *args in lambda
                if (tok.type == .Star) {
                    _ = self.advance(); // consume *
                    const param_name = (try self.expect(.Ident)).lexeme;
                    try args.append(self.allocator, .{
                        .name = param_name,
                        .type_annotation = null,
                        .default = null,
                    });
                    if (self.match(.Comma)) {
                        continue;
                    } else {
                        break;
                    }
                }
                if (tok.type == .Ident) {
                    const param_name = self.advance().?.lexeme;

                    // Parse default value if present (e.g., = 0.1)
                    var default_value: ?*ast.Node = null;
                    if (self.match(.Eq)) {
                        var default_expr = try parseOrExpr(self);
                        errdefer default_expr.deinit(self.allocator);
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
    var body_expr = try parseOrExpr(self);
    errdefer body_expr.deinit(self.allocator);

    var body_ptr: ?*ast.Node = null;
    errdefer if (body_ptr) |ptr| {
        ptr.deinit(self.allocator);
        self.allocator.destroy(ptr);
    };

    body_ptr = try self.allocator.create(ast.Node);
    body_ptr.?.* = body_expr;

    // Success - transfer ownership
    const final_args = try args.toOwnedSlice(self.allocator);
    args = std.ArrayList(ast.Arg){}; // Reset
    const final_body = body_ptr.?;
    body_ptr = null;

    return ast.Node{
        .lambda = .{
            .args = final_args,
            .body = final_body,
        },
    };
}
