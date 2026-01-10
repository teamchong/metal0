//! test.test_ast - Abstract Syntax Tree tests
const std = @import("std");

pub const NodeType = enum {
    Module, Interactive, Expression, FunctionDef, AsyncFunctionDef,
    ClassDef, Return, Delete, Assign, AugAssign, AnnAssign,
    For, AsyncFor, While, If, With, AsyncWith, Match, Raise,
    Try, TryStar, Assert, Import, ImportFrom, Global, Nonlocal,
    Expr, Pass, Break, Continue, BoolOp, NamedExpr, BinOp, UnaryOp,
    Lambda, IfExp, Dict, Set, ListComp, SetComp, DictComp, GeneratorExp,
    Await, Yield, YieldFrom, Compare, Call, FormattedValue, JoinedStr,
    Constant, Attribute, Subscript, Starred, Name, List, Tuple, Slice,
};

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
        self.children.deinit();
    }
    
    pub fn addChild(self: *@This(), child: *AST) !void {
        try self.children.append(child);
    }
};

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

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !*AST {
    _ = source;
    const node = try allocator.create(AST);
    node.* = AST.init(allocator, .Module);
    return node;
}

pub fn dump(node: *AST, writer: anytype) !void {
    try writer.print("{s}", .{@tagName(node.node_type)});
}

pub fn literal_eval(s: []const u8) !i64 {
    return std.fmt.parseInt(i64, s, 10);
}

test "ast_init" {
    var node = AST.init(std.testing.allocator, .Module);
    defer node.deinit();
    try std.testing.expectEqual(NodeType.Module, node.node_type);
}

test "ast_add_child" {
    var parent = AST.init(std.testing.allocator, .Module);
    defer parent.deinit();
    var child = try std.testing.allocator.create(AST);
    child.* = AST.init(std.testing.allocator, .FunctionDef);
    try parent.addChild(child);
    try std.testing.expectEqual(@as(usize, 1), parent.children.items.len);
    child.deinit();
    std.testing.allocator.destroy(child);
}

test "literal_eval" {
    try std.testing.expectEqual(@as(i64, 42), try literal_eval("42"));
    try std.testing.expectEqual(@as(i64, -10), try literal_eval("-10"));
}

test "node_types" {
    try std.testing.expect(NodeType.Module != NodeType.ClassDef);
    try std.testing.expect(NodeType.FunctionDef != NodeType.AsyncFunctionDef);
}
