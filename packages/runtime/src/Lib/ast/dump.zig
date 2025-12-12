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

    var result: std.ArrayList(u8) = .{};
    try dumpNode(&result, allocator, node, 0, indent);
    return result.toOwnedSlice(allocator);
}

fn dumpNode(result: *std.ArrayList(u8), allocator: std.mem.Allocator, node: anytype, depth: usize, indent: usize) !void {
    const T = @TypeOf(node);

    // Add indentation
    for (0..depth * indent) |_| {
        try result.append(allocator, ' ');
    }

    if (T == *Module) {
        try result.appendSlice(allocator, "Module(body=[\n");
        for (node.body) |stmt| {
            try dumpStatement(result, allocator, stmt, depth + 1, indent);
            try result.appendSlice(allocator, ",\n");
        }
        for (0..depth * indent) |_| {
            try result.append(allocator, ' ');
        }
        try result.appendSlice(allocator, "])");
    } else if (T == Expr) {
        try dumpExpr(result, allocator, node, depth, indent);
    } else if (T == Statement) {
        try dumpStatement(result, allocator, node, depth, indent);
    }
}

pub fn dumpStatement(result: *std.ArrayList(u8), allocator: std.mem.Allocator, stmt: Statement, depth: usize, indent: usize) !void {
    for (0..depth * indent) |_| {
        try result.append(allocator, ' ');
    }

    switch (stmt) {
        .pass_stmt => try result.appendSlice(allocator, "Pass()"),
        .break_stmt => try result.appendSlice(allocator, "Break()"),
        .continue_stmt => try result.appendSlice(allocator, "Continue()"),
        .return_stmt => |r| {
            try result.appendSlice(allocator, "Return(value=");
            if (r.value) |v| {
                try dumpExpr(result, allocator, v, 0, indent);
            } else {
                try result.appendSlice(allocator, "None");
            }
            try result.append(allocator, ')');
        },
        .expr_stmt => |e| {
            try result.appendSlice(allocator, "Expr(value=");
            try dumpExpr(result, allocator, e.value, 0, indent);
            try result.append(allocator, ')');
        },
        .assign => |a| {
            try result.appendSlice(allocator, "Assign(targets=[");
            for (a.targets) |target| {
                try dumpExpr(result, allocator, target, 0, indent);
            }
            try result.appendSlice(allocator, "], value=");
            try dumpExpr(result, allocator, a.value, 0, indent);
            try result.append(allocator, ')');
        },
        .function_def => |f| {
            try result.appendSlice(allocator, "FunctionDef(name='");
            try result.appendSlice(allocator, f.name);
            try result.appendSlice(allocator, "', args=arguments(...), body=[...])");
        },
        .class_def => |c| {
            try result.appendSlice(allocator, "ClassDef(name='");
            try result.appendSlice(allocator, c.name);
            try result.appendSlice(allocator, "', bases=[...], body=[...])");
        },
        .if_stmt => try result.appendSlice(allocator, "If(test=..., body=[...], orelse=[...])"),
        .for_stmt => try result.appendSlice(allocator, "For(target=..., iter=..., body=[...])"),
        .while_stmt => try result.appendSlice(allocator, "While(test=..., body=[...])"),
        .import_stmt => |im| {
            try result.appendSlice(allocator, "Import(names=[");
            for (im.names, 0..) |alias, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                try result.appendSlice(allocator, "alias(name='");
                try result.appendSlice(allocator, alias.name);
                try result.appendSlice(allocator, "')");
            }
            try result.appendSlice(allocator, "])");
        },
        else => try result.appendSlice(allocator, "..."),
    }
}

pub fn dumpExpr(result: *std.ArrayList(u8), allocator: std.mem.Allocator, expr: Expr, depth: usize, indent: usize) !void {
    _ = depth;
    _ = indent;

    switch (expr) {
        .constant => |c| {
            try result.appendSlice(allocator, "Constant(value=");
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
            try result.append(allocator, ')');
        },
        .name => |n| {
            try result.appendSlice(allocator, "Name(id='");
            try result.appendSlice(allocator, n.id);
            try result.appendSlice(allocator, "', ctx=Load())");
        },
        .bin_op => |b| {
            try result.appendSlice(allocator, "BinOp(left=");
            try dumpExpr(result, allocator, b.left.*, 0, 0);
            try result.appendSlice(allocator, ", op=");
            try result.appendSlice(allocator, @tagName(b.op));
            try result.appendSlice(allocator, "(), right=");
            try dumpExpr(result, allocator, b.right.*, 0, 0);
            try result.append(allocator, ')');
        },
        .call => |c| {
            try result.appendSlice(allocator, "Call(func=");
            try dumpExpr(result, allocator, c.func.*, 0, 0);
            try result.appendSlice(allocator, ", args=[...])");
        },
        else => try result.appendSlice(allocator, "..."),
    }
}
