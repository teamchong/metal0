/// Assignment statement parsing
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

pub fn parseExprOrAssign(self: *Parser) ParseError!ast.Node {
        const expr = try self.parseExpression();

        // Check if this is tuple unpacking (comma-separated targets)
        if (self.check(.Comma)) {
            // Parse comma-separated targets: a, b, c
            var targets_list = std.ArrayList(ast.Node){};
            try targets_list.append(self.allocator, expr);

            while (self.match(.Comma)) {
                const target = try self.parseExpression();
                try targets_list.append(self.allocator, target);
            }

            // Now expect assignment
            if (self.match(.Eq)) {
                const value = try self.parseExpression();
                _ = self.expect(.Newline) catch {};

                // Allocate value on heap
                const value_ptr = try self.allocator.create(ast.Node);
                value_ptr.* = value;

                // Create a tuple node for the targets
                const targets_array = try targets_list.toOwnedSlice(self.allocator);
                const target_tuple = try self.allocator.create(ast.Node);
                target_tuple.* = ast.Node{ .tuple = .{ .elts = targets_array } };

                // Wrap the tuple in array (single target)
                var targets = try self.allocator.alloc(ast.Node, 1);
                targets[0] = target_tuple.*;

                return ast.Node{
                    .assign = .{
                        .targets = targets,
                        .value = value_ptr,
                    },
                };
            } else {
                // This is invalid - can't have comma-separated expressions as statement
                return error.UnexpectedToken;
            }
        }

        // Check for augmented assignment (+=, -=, etc.)
        const aug_op = blk: {
            if (self.match(.PlusEq)) break :blk ast.Operator.Add;
            if (self.match(.MinusEq)) break :blk ast.Operator.Sub;
            if (self.match(.StarEq)) break :blk ast.Operator.Mult;
            if (self.match(.SlashEq)) break :blk ast.Operator.Div;
            if (self.match(.DoubleSlashEq)) break :blk ast.Operator.FloorDiv;
            if (self.match(.PercentEq)) break :blk ast.Operator.Mod;
            if (self.match(.StarStarEq)) break :blk ast.Operator.Pow;
            break :blk null;
        };

        if (aug_op) |op| {
            const value = try self.parseExpression();
            _ = self.expect(.Newline) catch {};

            // Allocate nodes on heap
            const target_ptr = try self.allocator.create(ast.Node);
            target_ptr.* = expr;

            const value_ptr = try self.allocator.create(ast.Node);
            value_ptr.* = value;

            return ast.Node{
                .aug_assign = .{
                    .target = target_ptr,
                    .op = op,
                    .value = value_ptr,
                },
            };
        }

        // Check for regular assignment
        if (self.match(.Eq)) {
            const value = try self.parseExpression();
            _ = self.expect(.Newline) catch {};

            // Allocate nodes on heap
            const value_ptr = try self.allocator.create(ast.Node);
            value_ptr.* = value;

            // For simplicity, wrap expr in array (single target)
            var targets = try self.allocator.alloc(ast.Node, 1);
            targets[0] = expr;

            return ast.Node{
                .assign = .{
                    .targets = targets,
                    .value = value_ptr,
                },
            };
        }

        // Expression statement
        _ = self.expect(.Newline) catch {};

        const expr_ptr = try self.allocator.create(ast.Node);
        expr_ptr.* = expr;

        return ast.Node{
            .expr_stmt = .{
                .value = expr_ptr,
            },
        };
    }
