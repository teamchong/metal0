//! AST Unparser
//! Convert AST nodes back to Python source code.

const std = @import("std");
const nodes = @import("nodes.zig");

const Module = nodes.Module;
const Statement = nodes.Statement;
const Expr = nodes.Expr;

/// Convert AST to source code
pub fn unparse(allocator: std.mem.Allocator, node: anytype) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    try unparseNode(&result, allocator, node, 0);
    return result.toOwnedSlice(allocator);
}

fn unparseNode(result: *std.ArrayList(u8), allocator: std.mem.Allocator, node: anytype, indent: usize) !void {
    const T = @TypeOf(node);

    if (T == *Module) {
        for (node.body) |stmt| {
            try unparseStatement(result, allocator, stmt, indent);
            try result.append(allocator, '\n');
        }
    } else if (T == Expr) {
        try unparseExpr(result, allocator, node);
    } else if (T == Statement) {
        try unparseStatement(result, allocator, node, indent);
    }
}

pub fn unparseStatement(result: *std.ArrayList(u8), allocator: std.mem.Allocator, stmt: Statement, indent: usize) !void {
    // Add indentation
    for (0..indent) |_| {
        try result.appendSlice(allocator, "    ");
    }

    switch (stmt) {
        .pass_stmt => try result.appendSlice(allocator, "pass"),
        .break_stmt => try result.appendSlice(allocator, "break"),
        .continue_stmt => try result.appendSlice(allocator, "continue"),
        .return_stmt => |r| {
            try result.appendSlice(allocator, "return");
            if (r.value) |v| {
                try result.append(allocator, ' ');
                try unparseExpr(result, allocator, v);
            }
        },
        .expr_stmt => |e| try unparseExpr(result, allocator, e.value),
        .assign => |a| {
            for (a.targets, 0..) |target, i| {
                if (i > 0) try result.appendSlice(allocator, " = ");
                try unparseExpr(result, allocator, target);
            }
            try result.appendSlice(allocator, " = ");
            try unparseExpr(result, allocator, a.value);
        },
        .function_def => |f| {
            try result.appendSlice(allocator, "def ");
            try result.appendSlice(allocator, f.name);
            try result.append(allocator, '(');
            for (f.args.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                try result.appendSlice(allocator, arg.arg);
            }
            try result.appendSlice(allocator, "):\n");
            for (f.body) |body_stmt| {
                try unparseStatement(result, allocator, body_stmt, indent + 1);
                try result.append(allocator, '\n');
            }
        },
        .class_def => |c| {
            try result.appendSlice(allocator, "class ");
            try result.appendSlice(allocator, c.name);
            if (c.bases.len > 0) {
                try result.append(allocator, '(');
                for (c.bases, 0..) |base, i| {
                    if (i > 0) try result.appendSlice(allocator, ", ");
                    try unparseExpr(result, allocator, base);
                }
                try result.append(allocator, ')');
            }
            try result.appendSlice(allocator, ":\n");
            for (c.body) |body_stmt| {
                try unparseStatement(result, allocator, body_stmt, indent + 1);
                try result.append(allocator, '\n');
            }
        },
        .if_stmt => |i| {
            try result.appendSlice(allocator, "if ");
            try unparseExpr(result, allocator, i.test);
            try result.appendSlice(allocator, ":\n");
            for (i.body) |body_stmt| {
                try unparseStatement(result, allocator, body_stmt, indent + 1);
                try result.append(allocator, '\n');
            }
            if (i.orelse.len > 0) {
                for (0..indent) |_| {
                    try result.appendSlice(allocator, "    ");
                }
                try result.appendSlice(allocator, "else:\n");
                for (i.orelse) |else_stmt| {
                    try unparseStatement(result, allocator, else_stmt, indent + 1);
                    try result.append(allocator, '\n');
                }
            }
        },
        .for_stmt => |f| {
            try result.appendSlice(allocator, "for ");
            try unparseExpr(result, allocator, f.target);
            try result.appendSlice(allocator, " in ");
            try unparseExpr(result, allocator, f.iter);
            try result.appendSlice(allocator, ":\n");
            for (f.body) |body_stmt| {
                try unparseStatement(result, allocator, body_stmt, indent + 1);
                try result.append(allocator, '\n');
            }
        },
        .while_stmt => |w| {
            try result.appendSlice(allocator, "while ");
            try unparseExpr(result, allocator, w.test);
            try result.appendSlice(allocator, ":\n");
            for (w.body) |body_stmt| {
                try unparseStatement(result, allocator, body_stmt, indent + 1);
                try result.append(allocator, '\n');
            }
        },
        .import_stmt => |im| {
            try result.appendSlice(allocator, "import ");
            for (im.names, 0..) |alias, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                try result.appendSlice(allocator, alias.name);
                if (alias.asname) |asname| {
                    try result.appendSlice(allocator, " as ");
                    try result.appendSlice(allocator, asname);
                }
            }
        },
        else => try result.appendSlice(allocator, "# unsupported statement"),
    }
}

pub fn unparseExpr(result: *std.ArrayList(u8), allocator: std.mem.Allocator, expr: Expr) !void {
    switch (expr) {
        .constant => |c| {
            switch (c.value) {
                .none => try result.appendSlice(allocator, "None"),
                .bool_val => |b| try result.appendSlice(allocator, if (b) "True" else "False"),
                .int_val => |i| try result.writer(allocator).print("{d}", .{i}),
                .float_val => |f| try result.writer(allocator).print("{d}", .{f}),
                .string_val => |s| {
                    try result.append(allocator, '\'');
                    try result.appendSlice(allocator, s);
                    try result.append(allocator, '\'');
                },
                .bytes_val => |b| {
                    try result.appendSlice(allocator, "b'");
                    try result.appendSlice(allocator, b);
                    try result.append(allocator, '\'');
                },
                .ellipsis => try result.appendSlice(allocator, "..."),
            }
        },
        .name => |n| try result.appendSlice(allocator, n.id),
        .bin_op => |b| {
            try result.append(allocator, '(');
            try unparseExpr(result, allocator, b.left.*);
            const op_str: []const u8 = switch (b.op) {
                .add => " + ",
                .sub => " - ",
                .mult => " * ",
                .div => " / ",
                .mod => " % ",
                .pow => " ** ",
                .floor_div => " // ",
                .mat_mult => " @ ",
                .lshift => " << ",
                .rshift => " >> ",
                .bit_or => " | ",
                .bit_xor => " ^ ",
                .bit_and => " & ",
            };
            try result.appendSlice(allocator, op_str);
            try unparseExpr(result, allocator, b.right.*);
            try result.append(allocator, ')');
        },
        .unary_op => |u| {
            const op_str: []const u8 = switch (u.op) {
                .invert => "~",
                .not => "not ",
                .uadd => "+",
                .usub => "-",
            };
            try result.appendSlice(allocator, op_str);
            try unparseExpr(result, allocator, u.operand.*);
        },
        .bool_op => |b| {
            const op_str: []const u8 = switch (b.op) {
                .@"and" => " and ",
                .@"or" => " or ",
            };
            for (b.values, 0..) |v, i| {
                if (i > 0) try result.appendSlice(allocator, op_str);
                try unparseExpr(result, allocator, v);
            }
        },
        .compare => |c| {
            try unparseExpr(result, allocator, c.left.*);
            for (c.ops, 0..) |op, i| {
                const op_str: []const u8 = switch (op) {
                    .eq => " == ",
                    .not_eq => " != ",
                    .lt => " < ",
                    .lte => " <= ",
                    .gt => " > ",
                    .gte => " >= ",
                    .is => " is ",
                    .is_not => " is not ",
                    .in => " in ",
                    .not_in => " not in ",
                };
                try result.appendSlice(allocator, op_str);
                try unparseExpr(result, allocator, c.comparators[i]);
            }
        },
        .call => |c| {
            try unparseExpr(result, allocator, c.func.*);
            try result.append(allocator, '(');
            for (c.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                try unparseExpr(result, allocator, arg);
            }
            try result.append(allocator, ')');
        },
        .attribute => |a| {
            try unparseExpr(result, allocator, a.value.*);
            try result.append(allocator, '.');
            try result.appendSlice(allocator, a.attr);
        },
        .subscript => |s| {
            try unparseExpr(result, allocator, s.value.*);
            try result.append(allocator, '[');
            try unparseExpr(result, allocator, s.slice.*);
            try result.append(allocator, ']');
        },
        .list => |l| {
            try result.append(allocator, '[');
            for (l.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                try unparseExpr(result, allocator, elt);
            }
            try result.append(allocator, ']');
        },
        .tuple => |t| {
            try result.append(allocator, '(');
            for (t.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                try unparseExpr(result, allocator, elt);
            }
            if (t.elts.len == 1) try result.append(allocator, ',');
            try result.append(allocator, ')');
        },
        .dict => |d| {
            try result.append(allocator, '{');
            for (d.keys, 0..) |key, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                if (key) |k| {
                    try unparseExpr(result, allocator, k);
                    try result.appendSlice(allocator, ": ");
                } else {
                    try result.appendSlice(allocator, "**");
                }
                try unparseExpr(result, allocator, d.values[i]);
            }
            try result.append(allocator, '}');
        },
        .set => |s| {
            try result.append(allocator, '{');
            for (s.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                try unparseExpr(result, allocator, elt);
            }
            try result.append(allocator, '}');
        },
        else => try result.appendSlice(allocator, "..."),
    }
}
