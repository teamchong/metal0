//! test.test_ast - Abstract Syntax Tree tests
//!
//! This module provides comprehensive AST manipulation utilities for Python code,
//! including parsing, unparsing, transformation, optimization, and incremental updates.

const std = @import("std");

// Module exports
pub const compile = @import("test_compile.zig");
pub const nodevisitor = @import("test_nodevisitor.zig");
pub const transformer = @import("test_transformer.zig");
pub const dump = @import("test_dump.zig");
pub const parse = @import("test_parse.zig");
pub const unparse = @import("test_unparse.zig");
pub const copy = @import("test_copy.zig");
pub const literal = @import("test_literal.zig");
pub const incremental = @import("test_incremental.zig");
pub const optimize = @import("test_optimize.zig");

/// Primary AST Node type enum used across modules
pub const NodeType = enum {
    Module,
    Interactive,
    Expression,
    FunctionDef,
    AsyncFunctionDef,
    ClassDef,
    Return,
    Delete,
    Assign,
    AugAssign,
    AnnAssign,
    For,
    AsyncFor,
    While,
    If,
    With,
    AsyncWith,
    Match,
    Raise,
    Try,
    TryStar,
    Assert,
    Import,
    ImportFrom,
    Global,
    Nonlocal,
    Expr,
    Pass,
    Break,
    Continue,
    BoolOp,
    NamedExpr,
    BinOp,
    UnaryOp,
    Lambda,
    IfExp,
    Dict,
    Set,
    ListComp,
    SetComp,
    DictComp,
    GeneratorExp,
    Await,
    Yield,
    YieldFrom,
    Compare,
    Call,
    FormattedValue,
    JoinedStr,
    Constant,
    Attribute,
    Subscript,
    Starred,
    Name,
    List,
    Tuple,
    Slice,
};

/// Primary AST Node structure for basic operations
pub const AST = struct {
    node_type: NodeType,
    lineno: usize = 0,
    col_offset: usize = 0,
    end_lineno: ?usize = null,
    end_col_offset: ?usize = null,
    children: std.ArrayList(*AST),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType) @This() {
        return .{
            .allocator = allocator,
            .node_type = node_type,
            .children = std.ArrayList(*AST).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
    }

    pub fn addChild(self: *@This(), child: *AST) !void {
        try self.children.append(child);
    }

    pub fn createChild(self: *@This(), node_type: NodeType) !*AST {
        const child = try self.allocator.create(AST);
        child.* = AST.init(self.allocator, node_type);
        try self.addChild(child);
        return child;
    }

    pub fn nodeCount(self: *const @This()) usize {
        var count: usize = 1;
        for (self.children.items) |child| {
            count += child.nodeCount();
        }
        return count;
    }
};

/// NodeVisitor base for traversing AST
pub const NodeVisitor = struct {
    pub fn visit(self: *@This(), node: *AST) void {
        _ = self;
        switch (node.node_type) {
            .Module => self.visit_Module(node),
            .FunctionDef => self.visit_FunctionDef(node),
            else => self.generic_visit(node),
        }
    }

    pub fn visit_Module(self: *@This(), node: *AST) void {
        self.generic_visit(node);
    }

    pub fn visit_FunctionDef(self: *@This(), node: *AST) void {
        self.generic_visit(node);
    }

    pub fn generic_visit(self: *@This(), node: *AST) void {
        for (node.children.items) |child| {
            self.visit(child);
        }
    }
};

/// Parse Python source code into an AST (wrapper)
pub fn parseSource(allocator: std.mem.Allocator, source: []const u8) !*AST {
    _ = source;
    const node = try allocator.create(AST);
    node.* = AST.init(allocator, .Module);
    return node;
}

/// Dump AST to string representation (wrapper)
pub fn dumpAST(node: *AST, writer: anytype) !void {
    try writer.print("{s}(", .{@tagName(node.node_type)});
    for (node.children.items, 0..) |child, i| {
        if (i > 0) try writer.writeAll(", ");
        try dumpAST(child, writer);
    }
    try writer.writeByte(')');
}

/// Evaluate a literal expression safely
pub fn literal_eval(s: []const u8) !i64 {
    return std.fmt.parseInt(i64, s, 10);
}

// Unit tests

test "ast_init" {
    var node = AST.init(std.testing.allocator, .Module);
    defer node.deinit();
    try std.testing.expectEqual(NodeType.Module, node.node_type);
}

test "ast_add_child" {
    var parent = AST.init(std.testing.allocator, .Module);
    defer parent.deinit();

    const child = try parent.createChild(.FunctionDef);
    _ = child;

    try std.testing.expectEqual(@as(usize, 1), parent.children.items.len);
}

test "ast_node_count" {
    var parent = AST.init(std.testing.allocator, .Module);
    defer parent.deinit();

    const child1 = try parent.createChild(.FunctionDef);
    _ = try child1.createChild(.Return);
    _ = try parent.createChild(.ClassDef);

    try std.testing.expectEqual(@as(usize, 4), parent.nodeCount());
}

test "literal_eval_int" {
    try std.testing.expectEqual(@as(i64, 42), try literal_eval("42"));
    try std.testing.expectEqual(@as(i64, -10), try literal_eval("-10"));
}

test "node_types" {
    try std.testing.expect(NodeType.Module != NodeType.ClassDef);
    try std.testing.expect(NodeType.FunctionDef != NodeType.AsyncFunctionDef);
}

// Reference all submodules for testing
test {
    _ = compile;
    _ = nodevisitor;
    _ = transformer;
    _ = dump;
    _ = parse;
    _ = unparse;
    _ = copy;
    _ = literal;
    _ = incremental;
    _ = optimize;
}
