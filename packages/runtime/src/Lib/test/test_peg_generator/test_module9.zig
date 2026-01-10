//! test.test_peg_generator.test_ast - AST generation tests
//!
//! This module tests Abstract Syntax Tree generation from PEG parsers,
//! including node types, tree construction, and visitor patterns.

const std = @import("std");

/// Types of AST nodes
pub const NodeType = enum {
    // Literals
    identifier,
    number,
    string,
    boolean,

    // Expressions
    binary_expr,
    unary_expr,
    call_expr,
    index_expr,
    member_expr,

    // Statements
    assignment,
    if_stmt,
    while_stmt,
    for_stmt,
    return_stmt,
    block,

    // Declarations
    function_decl,
    variable_decl,
    class_decl,

    // Other
    program,
    parameter,
    argument,

    pub fn isExpression(self: NodeType) bool {
        return switch (self) {
            .identifier, .number, .string, .boolean, .binary_expr, .unary_expr, .call_expr, .index_expr, .member_expr => true,
            else => false,
        };
    }

    pub fn isStatement(self: NodeType) bool {
        return switch (self) {
            .assignment, .if_stmt, .while_stmt, .for_stmt, .return_stmt, .block => true,
            else => false,
        };
    }

    pub fn isDeclaration(self: NodeType) bool {
        return switch (self) {
            .function_decl, .variable_decl, .class_decl => true,
            else => false,
        };
    }

    pub fn name(self: NodeType) []const u8 {
        return @tagName(self);
    }
};

/// Source location information
pub const SourceLocation = struct {
    start_line: usize,
    start_column: usize,
    end_line: usize,
    end_column: usize,
    start_offset: usize,
    end_offset: usize,

    pub fn init(start_line: usize, start_col: usize, end_line: usize, end_col: usize) SourceLocation {
        return .{
            .start_line = start_line,
            .start_column = start_col,
            .end_line = end_line,
            .end_column = end_col,
            .start_offset = 0,
            .end_offset = 0,
        };
    }

    pub fn withOffsets(self: SourceLocation, start: usize, end: usize) SourceLocation {
        var copy = self;
        copy.start_offset = start;
        copy.end_offset = end;
        return copy;
    }

    pub fn span(self: SourceLocation) usize {
        return self.end_offset - self.start_offset;
    }

    pub fn merge(a: SourceLocation, b: SourceLocation) SourceLocation {
        return .{
            .start_line = @min(a.start_line, b.start_line),
            .start_column = if (a.start_line <= b.start_line) a.start_column else b.start_column,
            .end_line = @max(a.end_line, b.end_line),
            .end_column = if (a.end_line >= b.end_line) a.end_column else b.end_column,
            .start_offset = @min(a.start_offset, b.start_offset),
            .end_offset = @max(a.end_offset, b.end_offset),
        };
    }
};

/// An AST node
pub const AstNode = struct {
    node_type: NodeType,
    value: ?[]const u8,
    children: std.ArrayList(*AstNode),
    location: SourceLocation,
    attributes: std.StringHashMap([]const u8),
    parent: ?*AstNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType) !*AstNode {
        const node = try allocator.create(AstNode);
        node.* = .{
            .node_type = node_type,
            .value = null,
            .children = std.ArrayList(*AstNode).init(allocator),
            .location = SourceLocation.init(0, 0, 0, 0),
            .attributes = std.StringHashMap([]const u8).init(allocator),
            .parent = null,
            .allocator = allocator,
        };
        return node;
    }

    pub fn deinit(self: *AstNode) void {
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
        self.attributes.deinit();
    }

    pub fn setValue(self: *AstNode, value: []const u8) void {
        self.value = value;
    }

    pub fn setLocation(self: *AstNode, loc: SourceLocation) void {
        self.location = loc;
    }

    pub fn addChild(self: *AstNode, child: *AstNode) !void {
        child.parent = self;
        try self.children.append(child);
    }

    pub fn setAttribute(self: *AstNode, key: []const u8, value: []const u8) !void {
        try self.attributes.put(key, value);
    }

    pub fn getAttribute(self: AstNode, key: []const u8) ?[]const u8 {
        return self.attributes.get(key);
    }

    pub fn childCount(self: AstNode) usize {
        return self.children.items.len;
    }

    pub fn getChild(self: AstNode, index: usize) ?*AstNode {
        if (index >= self.children.items.len) return null;
        return self.children.items[index];
    }

    pub fn isLeaf(self: AstNode) bool {
        return self.children.items.len == 0;
    }

    pub fn depth(self: AstNode) usize {
        var d: usize = 0;
        var current = self.parent;
        while (current) |p| {
            d += 1;
            current = p.parent;
        }
        return d;
    }

    pub fn root(self: *AstNode) *AstNode {
        var current = self;
        while (current.parent) |p| {
            current = p;
        }
        return current;
    }
};

/// AST builder for constructing trees
pub const AstBuilder = struct {
    allocator: std.mem.Allocator,
    current: ?*AstNode,
    root_node: ?*AstNode,

    pub fn init(allocator: std.mem.Allocator) AstBuilder {
        return .{
            .allocator = allocator,
            .current = null,
            .root_node = null,
        };
    }

    pub fn createNode(self: *AstBuilder, node_type: NodeType) !*AstNode {
        return AstNode.init(self.allocator, node_type);
    }

    pub fn startNode(self: *AstBuilder, node_type: NodeType) !*AstNode {
        const node = try self.createNode(node_type);
        if (self.current) |parent| {
            try parent.addChild(node);
        } else {
            self.root_node = node;
        }
        self.current = node;
        return node;
    }

    pub fn endNode(self: *AstBuilder) ?*AstNode {
        const finished = self.current;
        if (self.current) |c| {
            self.current = c.parent;
        }
        return finished;
    }

    pub fn addLeaf(self: *AstBuilder, node_type: NodeType, value: ?[]const u8) !*AstNode {
        const node = try self.createNode(node_type);
        if (value) |v| {
            node.setValue(v);
        }
        if (self.current) |parent| {
            try parent.addChild(node);
        } else {
            self.root_node = node;
        }
        return node;
    }

    pub fn getRoot(self: AstBuilder) ?*AstNode {
        return self.root_node;
    }

    pub fn reset(self: *AstBuilder) void {
        self.current = null;
        self.root_node = null;
    }
};

/// Visitor interface for AST traversal
pub const AstVisitor = struct {
    context: *anyopaque,
    visitFn: *const fn (*anyopaque, *AstNode) VisitResult,

    pub const VisitResult = enum {
        continue_,
        skip_children,
        stop,
    };

    pub fn visit(self: AstVisitor, node: *AstNode) VisitResult {
        return self.visitFn(self.context, node);
    }
};

/// Walk the AST in pre-order
pub fn walkPreOrder(node: *AstNode, visitor: AstVisitor) void {
    const result = visitor.visit(node);
    if (result == .stop) return;
    if (result == .skip_children) return;

    for (node.children.items) |child| {
        walkPreOrder(child, visitor);
    }
}

/// Walk the AST in post-order
pub fn walkPostOrder(node: *AstNode, visitor: AstVisitor) void {
    for (node.children.items) |child| {
        walkPostOrder(child, visitor);
    }
    _ = visitor.visit(node);
}

/// Count nodes in the AST
pub fn countNodes(node: *AstNode) usize {
    var count: usize = 1;
    for (node.children.items) |child| {
        count += countNodes(child);
    }
    return count;
}

/// Find nodes of a specific type
pub fn findNodes(allocator: std.mem.Allocator, node: *AstNode, node_type: NodeType) !std.ArrayList(*AstNode) {
    var results = std.ArrayList(*AstNode).init(allocator);

    const Collector = struct {
        list: *std.ArrayList(*AstNode),
        target_type: NodeType,

        fn visit(ctx: *anyopaque, n: *AstNode) AstVisitor.VisitResult {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (n.node_type == self.target_type) {
                self.list.append(n) catch {};
            }
            return .continue_;
        }
    };

    var collector = Collector{ .list = &results, .target_type = node_type };
    const visitor = AstVisitor{
        .context = @ptrCast(&collector),
        .visitFn = Collector.visit,
    };

    walkPreOrder(node, visitor);
    return results;
}

// Tests
test "node_type_is_expression" {
    try std.testing.expect(NodeType.identifier.isExpression());
    try std.testing.expect(NodeType.binary_expr.isExpression());
    try std.testing.expect(!NodeType.if_stmt.isExpression());
    try std.testing.expect(!NodeType.function_decl.isExpression());
}

test "node_type_is_statement" {
    try std.testing.expect(NodeType.if_stmt.isStatement());
    try std.testing.expect(NodeType.while_stmt.isStatement());
    try std.testing.expect(!NodeType.identifier.isStatement());
}

test "node_type_is_declaration" {
    try std.testing.expect(NodeType.function_decl.isDeclaration());
    try std.testing.expect(NodeType.variable_decl.isDeclaration());
    try std.testing.expect(!NodeType.if_stmt.isDeclaration());
}

test "node_type_name" {
    try std.testing.expectEqualStrings("identifier", NodeType.identifier.name());
    try std.testing.expectEqualStrings("binary_expr", NodeType.binary_expr.name());
}

test "source_location_init" {
    const loc = SourceLocation.init(1, 5, 1, 10);
    try std.testing.expectEqual(@as(usize, 1), loc.start_line);
    try std.testing.expectEqual(@as(usize, 5), loc.start_column);
    try std.testing.expectEqual(@as(usize, 1), loc.end_line);
    try std.testing.expectEqual(@as(usize, 10), loc.end_column);
}

test "source_location_with_offsets" {
    const loc = SourceLocation.init(1, 1, 1, 5).withOffsets(0, 4);
    try std.testing.expectEqual(@as(usize, 0), loc.start_offset);
    try std.testing.expectEqual(@as(usize, 4), loc.end_offset);
    try std.testing.expectEqual(@as(usize, 4), loc.span());
}

test "source_location_merge" {
    const a = SourceLocation.init(1, 5, 2, 10).withOffsets(4, 30);
    const b = SourceLocation.init(3, 1, 3, 15).withOffsets(50, 65);

    const merged = SourceLocation.merge(a, b);
    try std.testing.expectEqual(@as(usize, 1), merged.start_line);
    try std.testing.expectEqual(@as(usize, 3), merged.end_line);
    try std.testing.expectEqual(@as(usize, 4), merged.start_offset);
    try std.testing.expectEqual(@as(usize, 65), merged.end_offset);
}

test "ast_node_init" {
    const node = try AstNode.init(std.testing.allocator, .identifier);
    defer {
        node.deinit();
        std.testing.allocator.destroy(node);
    }

    try std.testing.expect(node.node_type == .identifier);
    try std.testing.expect(node.value == null);
    try std.testing.expect(node.isLeaf());
}

test "ast_node_set_value" {
    const node = try AstNode.init(std.testing.allocator, .identifier);
    defer {
        node.deinit();
        std.testing.allocator.destroy(node);
    }

    node.setValue("myVar");
    try std.testing.expectEqualStrings("myVar", node.value.?);
}

test "ast_node_add_child" {
    const parent = try AstNode.init(std.testing.allocator, .binary_expr);
    defer {
        parent.deinit();
        std.testing.allocator.destroy(parent);
    }

    const child = try AstNode.init(std.testing.allocator, .identifier);
    try parent.addChild(child);

    try std.testing.expectEqual(@as(usize, 1), parent.childCount());
    try std.testing.expect(!parent.isLeaf());
    try std.testing.expect(child.parent == parent);
}

test "ast_node_get_child" {
    const parent = try AstNode.init(std.testing.allocator, .block);
    defer {
        parent.deinit();
        std.testing.allocator.destroy(parent);
    }

    const child1 = try AstNode.init(std.testing.allocator, .assignment);
    const child2 = try AstNode.init(std.testing.allocator, .return_stmt);
    try parent.addChild(child1);
    try parent.addChild(child2);

    try std.testing.expect(parent.getChild(0).?.node_type == .assignment);
    try std.testing.expect(parent.getChild(1).?.node_type == .return_stmt);
    try std.testing.expect(parent.getChild(2) == null);
}

test "ast_node_attributes" {
    const node = try AstNode.init(std.testing.allocator, .function_decl);
    defer {
        node.deinit();
        std.testing.allocator.destroy(node);
    }

    try node.setAttribute("name", "myFunc");
    try node.setAttribute("return_type", "int");

    try std.testing.expectEqualStrings("myFunc", node.getAttribute("name").?);
    try std.testing.expectEqualStrings("int", node.getAttribute("return_type").?);
    try std.testing.expect(node.getAttribute("nonexistent") == null);
}

test "ast_node_depth" {
    const root = try AstNode.init(std.testing.allocator, .program);
    defer {
        root.deinit();
        std.testing.allocator.destroy(root);
    }

    const child = try AstNode.init(std.testing.allocator, .function_decl);
    const grandchild = try AstNode.init(std.testing.allocator, .block);

    try root.addChild(child);
    try child.addChild(grandchild);

    try std.testing.expectEqual(@as(usize, 0), root.depth());
    try std.testing.expectEqual(@as(usize, 1), child.depth());
    try std.testing.expectEqual(@as(usize, 2), grandchild.depth());
}

test "ast_node_root" {
    const root = try AstNode.init(std.testing.allocator, .program);
    defer {
        root.deinit();
        std.testing.allocator.destroy(root);
    }

    const child = try AstNode.init(std.testing.allocator, .function_decl);
    const grandchild = try AstNode.init(std.testing.allocator, .block);

    try root.addChild(child);
    try child.addChild(grandchild);

    try std.testing.expect(grandchild.root() == root);
    try std.testing.expect(child.root() == root);
    try std.testing.expect(root.root() == root);
}

test "ast_builder_create_node" {
    var builder = AstBuilder.init(std.testing.allocator);
    const node = try builder.createNode(.identifier);
    defer {
        node.deinit();
        std.testing.allocator.destroy(node);
    }

    try std.testing.expect(node.node_type == .identifier);
}

test "ast_builder_start_end_node" {
    var builder = AstBuilder.init(std.testing.allocator);

    const root = try builder.startNode(.program);
    _ = try builder.startNode(.function_decl);
    _ = builder.endNode();
    _ = builder.endNode();

    defer {
        root.deinit();
        std.testing.allocator.destroy(root);
    }

    try std.testing.expect(builder.getRoot() == root);
    try std.testing.expectEqual(@as(usize, 1), root.childCount());
}

test "ast_builder_add_leaf" {
    var builder = AstBuilder.init(std.testing.allocator);

    const root = try builder.startNode(.binary_expr);
    _ = try builder.addLeaf(.identifier, "x");
    _ = try builder.addLeaf(.number, "42");
    _ = builder.endNode();

    defer {
        root.deinit();
        std.testing.allocator.destroy(root);
    }

    try std.testing.expectEqual(@as(usize, 2), root.childCount());
}

test "count_nodes" {
    const root = try AstNode.init(std.testing.allocator, .program);
    defer {
        root.deinit();
        std.testing.allocator.destroy(root);
    }

    const child1 = try AstNode.init(std.testing.allocator, .function_decl);
    const child2 = try AstNode.init(std.testing.allocator, .function_decl);
    const grandchild = try AstNode.init(std.testing.allocator, .block);

    try root.addChild(child1);
    try root.addChild(child2);
    try child1.addChild(grandchild);

    try std.testing.expectEqual(@as(usize, 4), countNodes(root));
}

test "find_nodes" {
    const root = try AstNode.init(std.testing.allocator, .program);
    defer {
        root.deinit();
        std.testing.allocator.destroy(root);
    }

    const func1 = try AstNode.init(std.testing.allocator, .function_decl);
    const func2 = try AstNode.init(std.testing.allocator, .function_decl);
    const var_decl = try AstNode.init(std.testing.allocator, .variable_decl);

    try root.addChild(func1);
    try root.addChild(func2);
    try root.addChild(var_decl);

    var results = try findNodes(std.testing.allocator, root, .function_decl);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 2), results.items.len);
}
