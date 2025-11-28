/// Assignment statement parsing
const std = @import("std");
const ast = @import("ast");
const lexer = @import("../../lexer.zig");
const ParseError = @import("../../parser.zig").ParseError;
const Parser = @import("../../parser.zig").Parser;

/// Parse assignment target - handles starred targets like *args
fn parseAssignTarget(self: *Parser) ParseError!ast.Node {
    if (self.match(.Star)) {
        var value = try self.parseExpression();
        errdefer value.deinit(self.allocator);
        return ast.Node{ .starred = .{ .value = try self.allocNode(value) } };
    }
    return self.parseExpression();
}

pub fn parseExprOrAssign(self: *Parser) ParseError!ast.Node {
    var expr = try parseAssignTarget(self);
    errdefer expr.deinit(self.allocator);

    // Check for type annotation: x: int = 5
    if (self.match(.Colon)) {
        var annotation = try self.parseExpression();
        errdefer annotation.deinit(self.allocator);

        // Check for assignment value
        var value: ?ast.Node = null;
        if (self.match(.Eq)) {
            value = try self.parseExpression();
        }
        errdefer if (value) |*v| v.deinit(self.allocator);

        _ = self.expect(.Newline) catch {};

        return ast.Node{
            .ann_assign = .{
                .target = try self.allocNode(expr),
                .annotation = try self.allocNode(annotation),
                .value = if (value) |v| try self.allocNode(v) else null,
                .simple = true,
            },
        };
    }

    // Check if this is tuple unpacking (comma-separated targets)
    if (self.check(.Comma)) {
        var targets_list = std.ArrayList(ast.Node){};
        errdefer {
            for (targets_list.items) |*t| t.deinit(self.allocator);
            targets_list.deinit(self.allocator);
        }
        try targets_list.append(self.allocator, expr);

        while (self.match(.Comma)) {
            // Check for trailing comma before =
            if (self.check(.Eq)) break;
            var target = try parseAssignTarget(self);
            errdefer target.deinit(self.allocator);
            try targets_list.append(self.allocator, target);
        }

        if (!self.match(.Eq)) return error.UnexpectedToken;

        // Create tuple from targets
        const targets_array = try targets_list.toOwnedSlice(self.allocator);
        targets_list = std.ArrayList(ast.Node){};
        const tuple_target = ast.Node{ .tuple = .{ .elts = targets_array } };

        // Collect all assignment targets for chained assignment (ka, va = ta = expr)
        var all_targets = std.ArrayList(ast.Node){};
        errdefer {
            for (all_targets.items) |*t| t.deinit(self.allocator);
            all_targets.deinit(self.allocator);
        }
        try all_targets.append(self.allocator, tuple_target);

        var first_value = try parseAssignTarget(self);
        errdefer first_value.deinit(self.allocator);

        // Check if value side is also a tuple (only if no chained assignment)
        var value = if (self.check(.Comma) and !self.check(.Eq)) blk: {
            var value_list = std.ArrayList(ast.Node){};
            errdefer {
                for (value_list.items) |*v| v.deinit(self.allocator);
                value_list.deinit(self.allocator);
            }
            try value_list.append(self.allocator, first_value);

            while (self.match(.Comma)) {
                if (self.check(.Eq) or self.check(.Newline)) break;
                var val = try parseAssignTarget(self);
                errdefer val.deinit(self.allocator);
                try value_list.append(self.allocator, val);
            }

            const value_array = try value_list.toOwnedSlice(self.allocator);
            value_list = std.ArrayList(ast.Node){};
            break :blk ast.Node{ .tuple = .{ .elts = value_array } };
        } else first_value;
        errdefer value.deinit(self.allocator);

        // Handle chained assignment: ka, va = ta = expr
        while (self.match(.Eq)) {
            // Current value is actually another target
            try all_targets.append(self.allocator, value);
            // Parse the next value
            value = try self.parseExpression();
        }

        _ = self.expect(.Newline) catch {};

        const targets = try all_targets.toOwnedSlice(self.allocator);
        all_targets = std.ArrayList(ast.Node){};

        return ast.Node{
            .assign = .{ .targets = targets, .value = try self.allocNode(value) },
        };
    }

    // Check for augmented assignment (+=, -=, etc.)
    const aug_op = blk: {
        if (self.match(.PlusEq)) break :blk ast.Operator.Add;
        if (self.match(.MinusEq)) break :blk ast.Operator.Sub;
        if (self.match(.StarEq)) break :blk ast.Operator.Mult;
        if (self.match(.AtEq)) break :blk ast.Operator.MatMul;
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

        return ast.Node{
            .aug_assign = .{
                .target = try self.allocNode(expr),
                .op = op,
                .value = try self.allocNode(value),
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

        // Parse value (or next target in chain) - use parseAssignTarget to handle *expr
        var first_value = try parseAssignTarget(self);
        errdefer first_value.deinit(self.allocator);

        // Check if value is a tuple (comma-separated): x = a, b, c or x = *a, *b
        var value = if (self.check(.Comma) and !self.check(.Eq)) blk: {
            var value_list = std.ArrayList(ast.Node){};
            errdefer {
                for (value_list.items) |*v| v.deinit(self.allocator);
                value_list.deinit(self.allocator);
            }
            try value_list.append(self.allocator, first_value);

            while (self.match(.Comma)) {
                // Check if next is '=' (chained assignment) or Newline (trailing comma) - if so, stop tuple building
                if (self.check(.Eq) or self.check(.Newline)) break;
                // Use parseAssignTarget to handle starred expressions like *args
                var val = try parseAssignTarget(self);
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

        const targets = try all_targets.toOwnedSlice(self.allocator);
        all_targets = std.ArrayList(ast.Node){};

        return ast.Node{
            .assign = .{ .targets = targets, .value = try self.allocNode(value) },
        };
    }

    // Expression statement
    const is_module_docstring = self.is_first_statement and
        expr == .constant and
        expr.constant.value == .string;

    if (is_module_docstring) {
        _ = self.match(.Newline);
    } else {
        _ = self.expect(.Newline) catch {};
    }

    return ast.Node{ .expr_stmt = .{ .value = try self.allocNode(expr) } };
}
