//! AST Unparser
//! Convert AST nodes back to Python source code.

const std = @import("std");
const nodes = @import("nodes.zig");

const Module = nodes.Module;
const Statement = nodes.Statement;
const Expr = nodes.Expr;

/// Convert AST to source code
pub fn unparse(allocator: std.mem.Allocator, node: anytype) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try unparseNode(&result, node, 0);
    return result.toOwnedSlice();
}

fn unparseNode(result: *std.ArrayList(u8), node: anytype, indent: usize) !void {
    const T = @TypeOf(node);

    if (T == *Module) {
        for (node.body) |stmt| {
            try unparseStatement(result, stmt, indent);
            try result.append('\n');
        }
    } else if (T == Expr) {
        try unparseExpr(result, node);
    } else if (T == Statement) {
        try unparseStatement(result, node, indent);
    }
}

pub fn unparseStatement(result: *std.ArrayList(u8), stmt: Statement, indent: usize) !void {
    // Add indentation
    for (0..indent) |_| {
        try result.appendSlice("    ");
    }

    switch (stmt) {
        .pass_stmt => try result.appendSlice("pass"),
        .break_stmt => try result.appendSlice("break"),
        .continue_stmt => try result.appendSlice("continue"),
        .return_stmt => |r| {
            try result.appendSlice("return");
            if (r.value) |v| {
                try result.append(' ');
                try unparseExpr(result, v);
            }
        },
        .expr_stmt => |e| try unparseExpr(result, e.value),
        .assign => |a| {
            for (a.targets, 0..) |target, i| {
                if (i > 0) try result.appendSlice(" = ");
                try unparseExpr(result, target);
            }
            try result.appendSlice(" = ");
            try unparseExpr(result, a.value);
        },
        .function_def => |f| {
            try result.appendSlice("def ");
            try result.appendSlice(f.name);
            try result.append('(');
            for (f.args.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(", ");
                try result.appendSlice(arg.arg);
            }
            try result.appendSlice("):\n");
            for (f.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
        },
        .class_def => |c| {
            try result.appendSlice("class ");
            try result.appendSlice(c.name);
            if (c.bases.len > 0) {
                try result.append('(');
                for (c.bases, 0..) |base, i| {
                    if (i > 0) try result.appendSlice(", ");
                    try unparseExpr(result, base);
                }
                try result.append(')');
            }
            try result.appendSlice(":\n");
            for (c.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
        },
        .if_stmt => |i| {
            try result.appendSlice("if ");
            try unparseExpr(result, i.test);
            try result.appendSlice(":\n");
            for (i.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
            if (i.orelse.len > 0) {
                for (0..indent) |_| {
                    try result.appendSlice("    ");
                }
                try result.appendSlice("else:\n");
                for (i.orelse) |else_stmt| {
                    try unparseStatement(result, else_stmt, indent + 1);
                    try result.append('\n');
                }
            }
        },
        .for_stmt => |f| {
            try result.appendSlice("for ");
            try unparseExpr(result, f.target);
            try result.appendSlice(" in ");
            try unparseExpr(result, f.iter);
            try result.appendSlice(":\n");
            for (f.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
        },
        .while_stmt => |w| {
            try result.appendSlice("while ");
            try unparseExpr(result, w.test);
            try result.appendSlice(":\n");
            for (w.body) |body_stmt| {
                try unparseStatement(result, body_stmt, indent + 1);
                try result.append('\n');
            }
        },
        .import_stmt => |im| {
            try result.appendSlice("import ");
            for (im.names, 0..) |alias, i| {
                if (i > 0) try result.appendSlice(", ");
                try result.appendSlice(alias.name);
                if (alias.asname) |asname| {
                    try result.appendSlice(" as ");
                    try result.appendSlice(asname);
                }
            }
        },
        else => try result.appendSlice("# unsupported statement"),
    }
}

pub fn unparseExpr(result: *std.ArrayList(u8), expr: Expr) !void {
    switch (expr) {
        .constant => |c| {
            switch (c.value) {
                .none => try result.appendSlice("None"),
                .bool_val => |b| try result.appendSlice(if (b) "True" else "False"),
                .int_val => |i| try result.writer().print("{d}", .{i}),
                .float_val => |f| try result.writer().print("{d}", .{f}),
                .string_val => |s| {
                    try result.append('\'');
                    try result.appendSlice(s);
                    try result.append('\'');
                },
                .bytes_val => |b| {
                    try result.appendSlice("b'");
                    try result.appendSlice(b);
                    try result.append('\'');
                },
                .ellipsis => try result.appendSlice("..."),
            }
        },
        .name => |n| try result.appendSlice(n.id),
        .bin_op => |b| {
            try result.append('(');
            try unparseExpr(result, b.left.*);
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
            try result.appendSlice(op_str);
            try unparseExpr(result, b.right.*);
            try result.append(')');
        },
        .unary_op => |u| {
            const op_str: []const u8 = switch (u.op) {
                .invert => "~",
                .not => "not ",
                .uadd => "+",
                .usub => "-",
            };
            try result.appendSlice(op_str);
            try unparseExpr(result, u.operand.*);
        },
        .bool_op => |b| {
            const op_str: []const u8 = switch (b.op) {
                .@"and" => " and ",
                .@"or" => " or ",
            };
            for (b.values, 0..) |v, i| {
                if (i > 0) try result.appendSlice(op_str);
                try unparseExpr(result, v);
            }
        },
        .compare => |c| {
            try unparseExpr(result, c.left.*);
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
                try result.appendSlice(op_str);
                try unparseExpr(result, c.comparators[i]);
            }
        },
        .call => |c| {
            try unparseExpr(result, c.func.*);
            try result.append('(');
            for (c.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(", ");
                try unparseExpr(result, arg);
            }
            try result.append(')');
        },
        .attribute => |a| {
            try unparseExpr(result, a.value.*);
            try result.append('.');
            try result.appendSlice(a.attr);
        },
        .subscript => |s| {
            try unparseExpr(result, s.value.*);
            try result.append('[');
            try unparseExpr(result, s.slice.*);
            try result.append(']');
        },
        .list => |l| {
            try result.append('[');
            for (l.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(", ");
                try unparseExpr(result, elt);
            }
            try result.append(']');
        },
        .tuple => |t| {
            try result.append('(');
            for (t.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(", ");
                try unparseExpr(result, elt);
            }
            if (t.elts.len == 1) try result.append(',');
            try result.append(')');
        },
        .dict => |d| {
            try result.append('{');
            for (d.keys, 0..) |key, i| {
                if (i > 0) try result.appendSlice(", ");
                if (key) |k| {
                    try unparseExpr(result, k);
                    try result.appendSlice(": ");
                } else {
                    try result.appendSlice("**");
                }
                try unparseExpr(result, d.values[i]);
            }
            try result.append('}');
        },
        .set => |s| {
            try result.append('{');
            for (s.elts, 0..) |elt, i| {
                if (i > 0) try result.appendSlice(", ");
                try unparseExpr(result, elt);
            }
            try result.append('}');
        },
        else => try result.appendSlice("..."),
    }
}
