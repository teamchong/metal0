//! AST Dump
//! Pretty print AST nodes for debugging.

const std = @import("std");
const nodes = @import("nodes.zig");

const Module = nodes.Module;
const Statement = nodes.Statement;
const Expr = nodes.Expr;

/// Pretty print an AST
pub fn dump(allocator: std.mem.Allocator, node: anytype, annotate_fields: bool, include_attributes: bool, indent_level: ?usize) ![]u8 {
    _ = annotate_fields;
    _ = include_attributes;
    const indent = indent_level orelse 2;

    var result = std.ArrayList(u8).init(allocator);
    try dumpNode(&result, node, 0, indent);
    return result.toOwnedSlice();
}

fn dumpNode(result: *std.ArrayList(u8), node: anytype, depth: usize, indent: usize) !void {
    const T = @TypeOf(node);

    // Add indentation
    for (0..depth * indent) |_| {
        try result.append(' ');
    }

    if (T == *Module) {
        try result.appendSlice("Module(body=[\n");
        for (node.body) |stmt| {
            try dumpStatement(result, stmt, depth + 1, indent);
            try result.appendSlice(",\n");
        }
        for (0..depth * indent) |_| {
            try result.append(' ');
        }
        try result.appendSlice("])");
    } else if (T == Expr) {
        try dumpExpr(result, node, depth, indent);
    } else if (T == Statement) {
        try dumpStatement(result, node, depth, indent);
    }
}

pub fn dumpStatement(result: *std.ArrayList(u8), stmt: Statement, depth: usize, indent: usize) !void {
    for (0..depth * indent) |_| {
        try result.append(' ');
    }

    switch (stmt) {
        .pass_stmt => try result.appendSlice("Pass()"),
        .break_stmt => try result.appendSlice("Break()"),
        .continue_stmt => try result.appendSlice("Continue()"),
        .return_stmt => |r| {
            try result.appendSlice("Return(value=");
            if (r.value) |v| {
                try dumpExpr(result, v, 0, indent);
            } else {
                try result.appendSlice("None");
            }
            try result.append(')');
        },
        .expr_stmt => |e| {
            try result.appendSlice("Expr(value=");
            try dumpExpr(result, e.value, 0, indent);
            try result.append(')');
        },
        .assign => |a| {
            try result.appendSlice("Assign(targets=[");
            for (a.targets) |target| {
                try dumpExpr(result, target, 0, indent);
            }
            try result.appendSlice("], value=");
            try dumpExpr(result, a.value, 0, indent);
            try result.append(')');
        },
        .function_def => |f| {
            try result.appendSlice("FunctionDef(name='");
            try result.appendSlice(f.name);
            try result.appendSlice("', args=arguments(...), body=[...])");
        },
        .class_def => |c| {
            try result.appendSlice("ClassDef(name='");
            try result.appendSlice(c.name);
            try result.appendSlice("', bases=[...], body=[...])");
        },
        .if_stmt => try result.appendSlice("If(test=..., body=[...], orelse=[...])"),
        .for_stmt => try result.appendSlice("For(target=..., iter=..., body=[...])"),
        .while_stmt => try result.appendSlice("While(test=..., body=[...])"),
        .import_stmt => |im| {
            try result.appendSlice("Import(names=[");
            for (im.names, 0..) |alias, i| {
                if (i > 0) try result.appendSlice(", ");
                try result.appendSlice("alias(name='");
                try result.appendSlice(alias.name);
                try result.appendSlice("')");
            }
            try result.appendSlice("])");
        },
        else => try result.appendSlice("..."),
    }
}

pub fn dumpExpr(result: *std.ArrayList(u8), expr: Expr, depth: usize, indent: usize) !void {
    _ = depth;
    _ = indent;

    switch (expr) {
        .constant => |c| {
            try result.appendSlice("Constant(value=");
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
            try result.append(')');
        },
        .name => |n| {
            try result.appendSlice("Name(id='");
            try result.appendSlice(n.id);
            try result.appendSlice("', ctx=Load())");
        },
        .bin_op => |b| {
            try result.appendSlice("BinOp(left=");
            try dumpExpr(result, b.left.*, 0, 0);
            try result.appendSlice(", op=");
            try result.appendSlice(@tagName(b.op));
            try result.appendSlice("(), right=");
            try dumpExpr(result, b.right.*, 0, 0);
            try result.append(')');
        },
        .call => |c| {
            try result.appendSlice("Call(func=");
            try dumpExpr(result, c.func.*, 0, 0);
            try result.appendSlice(", args=[...])");
        },
        else => try result.appendSlice("..."),
    }
}
