//! AST Visitor and Transformer
//! Base classes for traversing and transforming AST nodes.

const std = @import("std");

/// Get docstring from node
pub fn getDocstring(node: anytype) ?[]const u8 {
    _ = node;
    return null;
}

/// Walk AST nodes
pub fn walk(allocator: std.mem.Allocator, node: anytype) !NodeIterator {
    return NodeIterator.init(allocator, node);
}

pub const NodeIterator = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList(*anyopaque),

    pub fn init(allocator: std.mem.Allocator, root: anytype) NodeIterator {
        _ = root;
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *NodeIterator) void {
        self.stack.deinit();
    }

    pub fn next(self: *NodeIterator) ?*anyopaque {
        if (self.stack.items.len == 0) return null;
        return self.stack.pop();
    }
};

/// Fix missing locations in AST
pub fn fixMissingLocations(node: anytype) void {
    _ = node;
}

/// Increment line numbers
pub fn incrementLineno(node: anytype, n: i32) void {
    _ = node;
    _ = n;
}

/// Copy location from one node to another
pub fn copyLocation(source: anytype, dest: anytype) void {
    _ = source;
    _ = dest;
}

/// Get source segment
pub fn getSourceSegment(source: []const u8, node: anytype, padded: bool) ?[]const u8 {
    _ = source;
    _ = node;
    _ = padded;
    return null;
}

/// Base class for AST visitors
pub fn NodeVisitor(comptime T: type) type {
    return struct {
        const Self = @This();

        context: T,

        pub fn init(context: T) Self {
            return .{ .context = context };
        }

        pub fn visit(self: *Self, node: anytype) void {
            _ = self;
            _ = node;
        }

        pub fn genericVisit(self: *Self, node: anytype) void {
            _ = self;
            _ = node;
        }
    };
}

/// Base class for AST transformers
pub fn NodeTransformer(comptime T: type) type {
    return struct {
        const Self = @This();

        context: T,

        pub fn init(context: T) Self {
            return .{ .context = context };
        }

        pub fn visit(self: *Self, node: anytype) @TypeOf(node) {
            _ = self;
            return node;
        }

        pub fn genericVisit(self: *Self, node: anytype) @TypeOf(node) {
            _ = self;
            return node;
        }
    };
}
