/// Assignment statement parsing
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

pub fn parseExprOrAssign(self: *Parser) ParseError!ast.Node {
    var expr = try self.parseExpression();
    errdefer expr.deinit(self.allocator);

    // Check for type annotation: x: int = 5
    if (self.match(.Colon)) {
        var annotation = try self.parseExpression();
        errdefer annotation.deinit(self.allocator);

        var target_ptr: ?*ast.Node = null;
        errdefer if (target_ptr) |ptr| {
            ptr.deinit(self.allocator);
            self.allocator.destroy(ptr);
        };

        var annotation_ptr: ?*ast.Node = null;
        errdefer if (annotation_ptr) |ptr| {
            ptr.deinit(self.allocator);
            self.allocator.destroy(ptr);
        };

        target_ptr = try self.allocator.create(ast.Node);
        target_ptr.?.* = expr;

        annotation_ptr = try self.allocator.create(ast.Node);
        annotation_ptr.?.* = annotation;

        // Check for assignment value
        if (self.match(.Eq)) {
            var value = try self.parseExpression();
            errdefer value.deinit(self.allocator);
            _ = self.expect(.Newline) catch {};

            var value_ptr: ?*ast.Node = null;
            errdefer if (value_ptr) |ptr| {
                ptr.deinit(self.allocator);
                self.allocator.destroy(ptr);
            };

            value_ptr = try self.allocator.create(ast.Node);
            value_ptr.?.* = value;

            // Success - transfer ownership
            const final_target = target_ptr.?;
            target_ptr = null;
            const final_annotation = annotation_ptr.?;
            annotation_ptr = null;
            const final_value = value_ptr.?;
            value_ptr = null;

            return ast.Node{
                .ann_assign = .{
                    .target = final_target,
                    .annotation = final_annotation,
                    .value = final_value,
                    .simple = true,
                },
            };
        } else {
            // Type annotation without assignment (e.g., x: int)
            _ = self.expect(.Newline) catch {};

            // Success - transfer ownership
            const final_target = target_ptr.?;
            target_ptr = null;
            const final_annotation = annotation_ptr.?;
            annotation_ptr = null;

            return ast.Node{
                .ann_assign = .{
                    .target = final_target,
                    .annotation = final_annotation,
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
        errdefer {
            for (targets_list.items) |*t| t.deinit(self.allocator);
            targets_list.deinit(self.allocator);
        }
        try targets_list.append(self.allocator, expr);

        while (self.match(.Comma)) {
            var target = try self.parseExpression();
            errdefer target.deinit(self.allocator);
            try targets_list.append(self.allocator, target);
        }

        // Now expect assignment
        if (self.match(.Eq)) {
            var first_value = try self.parseExpression();
            errdefer first_value.deinit(self.allocator);

            // Check if the value side is also a tuple (comma-separated)
            var value = if (self.check(.Comma)) blk: {
                var value_list = std.ArrayList(ast.Node){};
                errdefer {
                    for (value_list.items) |*v| v.deinit(self.allocator);
                    value_list.deinit(self.allocator);
                }
                try value_list.append(self.allocator, first_value);

                while (self.match(.Comma)) {
                    var val = try self.parseExpression();
                    errdefer val.deinit(self.allocator);
                    try value_list.append(self.allocator, val);
                }

                const value_array = try value_list.toOwnedSlice(self.allocator);
                value_list = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free
                break :blk ast.Node{ .tuple = .{ .elts = value_array } };
            } else first_value;
            errdefer value.deinit(self.allocator);

            _ = self.expect(.Newline) catch {};

            // Allocate value on heap
            var value_ptr: ?*ast.Node = null;
            errdefer if (value_ptr) |ptr| {
                ptr.deinit(self.allocator);
                self.allocator.destroy(ptr);
            };

            value_ptr = try self.allocator.create(ast.Node);
            value_ptr.?.* = value;

            // Create a tuple node for the targets (directly in array, no intermediate pointer)
            const targets_array = try targets_list.toOwnedSlice(self.allocator);
            targets_list = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free
            var targets = try self.allocator.alloc(ast.Node, 1);
            targets[0] = ast.Node{ .tuple = .{ .elts = targets_array } };

            // Success - transfer ownership
            const final_value = value_ptr.?;
            value_ptr = null;

            return ast.Node{
                .assign = .{
                    .targets = targets,
                    .value = final_value,
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
        if (self.match(.AmpersandEq)) break :blk ast.Operator.BitAnd;
        if (self.match(.PipeEq)) break :blk ast.Operator.BitOr;
        if (self.match(.CaretEq)) break :blk ast.Operator.BitXor;
        if (self.match(.LtLtEq)) break :blk ast.Operator.LShift;
        if (self.match(.GtGtEq)) break :blk ast.Operator.RShift;
        break :blk null;
    };

    if (aug_op) |op| {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        _ = self.expect(.Newline) catch {};

        // Allocate nodes on heap
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
        target_ptr.?.* = expr;

        value_ptr = try self.allocator.create(ast.Node);
        value_ptr.?.* = value;

        // Success - transfer ownership
        const final_target = target_ptr.?;
        target_ptr = null;
        const final_value = value_ptr.?;
        value_ptr = null;

        return ast.Node{
            .aug_assign = .{
                .target = final_target,
                .op = op,
                .value = final_value,
            },
        };
    }

    // Check for regular assignment (including chained: a = b = c)
    if (self.match(.Eq)) {
        // Collect all assignment targets for chained assignment
        var all_targets = std.ArrayList(ast.Node){};
        errdefer {
            for (all_targets.items) |*t| t.deinit(self.allocator);
            all_targets.deinit(self.allocator);
        }
        try all_targets.append(self.allocator, expr);

        // Parse value (or next target in chain)
        var first_value = try self.parseExpression();
        errdefer first_value.deinit(self.allocator);

        // Check if value is a tuple (comma-separated): x = a, b, c
        var value = if (self.check(.Comma) and !self.check(.Eq)) blk: {
            var value_list = std.ArrayList(ast.Node){};
            errdefer {
                for (value_list.items) |*v| v.deinit(self.allocator);
                value_list.deinit(self.allocator);
            }
            try value_list.append(self.allocator, first_value);

            while (self.match(.Comma)) {
                // Check if next is '=' (chained assignment) - if so, stop tuple building
                if (self.check(.Eq)) break;
                var val = try self.parseExpression();
                errdefer val.deinit(self.allocator);
                try value_list.append(self.allocator, val);
            }

            const value_array = try value_list.toOwnedSlice(self.allocator);
            value_list = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free
            break :blk ast.Node{ .tuple = .{ .elts = value_array } };
        } else first_value;
        errdefer value.deinit(self.allocator);

        // Handle chained assignment: a = b = c
        while (self.match(.Eq)) {
            // Current value is actually another target
            try all_targets.append(self.allocator, value);
            // Parse the next value
            value = try self.parseExpression();
        }

        _ = self.expect(.Newline) catch {};

        // Allocate value on heap
        var value_ptr: ?*ast.Node = null;
        errdefer if (value_ptr) |ptr| {
            ptr.deinit(self.allocator);
            self.allocator.destroy(ptr);
        };

        value_ptr = try self.allocator.create(ast.Node);
        value_ptr.?.* = value;

        // Convert targets to owned slice
        const targets = try all_targets.toOwnedSlice(self.allocator);
        all_targets = std.ArrayList(ast.Node){}; // Reset so errdefer doesn't double-free

        // Success - transfer ownership
        const final_value = value_ptr.?;
        value_ptr = null;

        return ast.Node{
            .assign = .{
                .targets = targets,
                .value = final_value,
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
