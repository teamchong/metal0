/// Assignment statement parsing
const std = @import("std");
const ast = @import("../../ast.zig");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

pub fn parseExprOrAssign(self: *Parser) ParseError!ast.Node {
        const expr = try self.parseExpression();

        // Check for type annotation: x: int = 5
        if (self.match(.Colon)) {
            const annotation = try self.parseExpression();

            const target_ptr = try self.allocator.create(ast.Node);
            target_ptr.* = expr;

            const annotation_ptr = try self.allocator.create(ast.Node);
            annotation_ptr.* = annotation;

            // Check for assignment value
            if (self.match(.Eq)) {
                const value = try self.parseExpression();
                _ = self.expect(.Newline) catch {};

                const value_ptr = try self.allocator.create(ast.Node);
                value_ptr.* = value;

                return ast.Node{
                    .ann_assign = .{
                        .target = target_ptr,
                        .annotation = annotation_ptr,
                        .value = value_ptr,
                        .simple = true,
                    },
                };
            } else {
                // Type annotation without assignment (e.g., x: int)
                _ = self.expect(.Newline) catch {};
                return ast.Node{
                    .ann_assign = .{
                        .target = target_ptr,
                        .annotation = annotation_ptr,
                        .value = null,
                        .simple = true,
                    },
                };
            }
        }

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
                const first_value = try self.parseExpression();

                // Check if the value side is also a tuple (comma-separated)
                const value = if (self.check(.Comma)) blk: {
                    var value_list = std.ArrayList(ast.Node){};
                    defer value_list.deinit(self.allocator);
                    try value_list.append(self.allocator, first_value);

                    while (self.match(.Comma)) {
                        const val = try self.parseExpression();
                        try value_list.append(self.allocator, val);
                    }

                    const value_array = try value_list.toOwnedSlice(self.allocator);
                    break :blk ast.Node{ .tuple = .{ .elts = value_array } };
                } else first_value;

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
        // Check if this is a module docstring (first statement + string constant)
        const is_module_docstring = self.is_first_statement and
            expr == .constant and
            expr.constant.value == .string;

        // If it's a module docstring, don't require newline before import
        if (is_module_docstring) {
            _ = self.match(.Newline);
        } else {
            _ = self.expect(.Newline) catch {};
        }

        const expr_ptr = try self.allocator.create(ast.Node);
        expr_ptr.* = expr;

        return ast.Node{
            .expr_stmt = .{
                .value = expr_ptr,
            },
        };
    }
