//! test.test_ctypes.test_incomplete - Tests for incomplete types
//! Reference: cpython/Lib/test/test_ctypes/test_incomplete.py
//!
//! Tests for forward declarations and incomplete type handling
//! in ctypes including self-referential structures and opaque types.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Incomplete Type Markers
// ============================================================================

/// Marker for an incomplete (forward-declared) type
pub fn IncompleteType(comptime name: []const u8) type {
    return struct {
        const Self = @This();
        pub const type_name = name;
        pub const is_complete = false;

        _opaque: ?*anyopaque = null,

        pub fn init() Self {
            return .{};
        }

        /// Check if this type has been completed
        pub fn isComplete(_: Self) bool {
            return false;
        }

        /// Get the type name
        pub fn typeName(_: Self) []const u8 {
            return name;
        }
    };
}

/// Complete an incomplete type with a real definition
pub fn CompleteType(comptime Incomplete: type, comptime fields: []const FieldDef) type {
    return struct {
        const Self = @This();
        pub const original_type = Incomplete;
        pub const is_complete = true;
        pub const _fields_ = fields;

        data: [calculateSize(fields)]u8 = undefined,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        pub fn isComplete(_: Self) bool {
            return true;
        }

        pub fn sizeof() usize {
            return calculateSize(fields);
        }
    };
}

pub const FieldDef = struct {
    name: []const u8,
    size: usize,
    offset: usize,
};

fn calculateSize(fields: []const FieldDef) usize {
    if (fields.len == 0) return 0;
    const last = fields[fields.len - 1];
    return last.offset + last.size;
}

// ============================================================================
// Self-Referential Structures
// ============================================================================

/// A linked list node with self-reference
pub const ListNode = struct {
    const Self = @This();

    value: i32 = 0,
    next: ?*Self = null,

    pub fn init(value: i32) Self {
        return .{ .value = value };
    }

    pub fn append(self: *Self, node: *Self) void {
        var current = self;
        while (current.next) |next| {
            current = next;
        }
        current.next = node;
    }

    pub fn length(self: *const Self) usize {
        var count: usize = 1;
        var current = self;
        while (current.next) |next| {
            count += 1;
            current = next;
        }
        return count;
    }
};

/// A tree node with self-reference
pub const TreeNode = struct {
    const Self = @This();

    value: i32 = 0,
    left: ?*Self = null,
    right: ?*Self = null,

    pub fn init(value: i32) Self {
        return .{ .value = value };
    }

    pub fn isLeaf(self: *const Self) bool {
        return self.left == null and self.right == null;
    }

    pub fn height(self: *const Self) usize {
        const left_h = if (self.left) |l| l.height() else 0;
        const right_h = if (self.right) |r| r.height() else 0;
        return 1 + @max(left_h, right_h);
    }
};

// ============================================================================
// Opaque Types
// ============================================================================

/// An opaque handle type
pub const OpaqueHandle = struct {
    const Self = @This();

    _handle: usize = 0,

    pub fn init(handle: usize) Self {
        return .{ ._handle = handle };
    }

    pub fn isValid(self: Self) bool {
        return self._handle != 0;
    }

    pub fn invalidate(self: *Self) void {
        self._handle = 0;
    }
};

/// Forward-declared struct pointer
pub const ForwardDeclPtr = struct {
    const Self = @This();

    ptr: ?*anyopaque = null,

    pub fn init() Self {
        return .{};
    }

    pub fn isNull(self: Self) bool {
        return self.ptr == null;
    }

    pub fn setPtr(self: *Self, p: *anyopaque) void {
        self.ptr = p;
    }
};

// ============================================================================
// Type Checking
// ============================================================================

/// Check if a type is incomplete
pub fn isIncomplete(comptime T: type) bool {
    if (@hasDecl(T, "is_complete")) {
        return !T.is_complete;
    }
    return false;
}

/// Check if a type is a pointer to incomplete type
pub fn isPointerToIncomplete(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .pointer) {
        return isIncomplete(info.pointer.child);
    }
    return false;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testIncompleteType() !void {
    const Incomplete = IncompleteType("MyStruct");
    const instance = Incomplete.init();

    try std.testing.expect(!instance.isComplete());
    try std.testing.expectEqualStrings("MyStruct", instance.typeName());
}

fn testCompleteType() !void {
    const Incomplete = IncompleteType("Point");
    const Complete = CompleteType(Incomplete, &.{
        .{ .name = "x", .size = 4, .offset = 0 },
        .{ .name = "y", .size = 4, .offset = 4 },
    });

    const instance = Complete.init();
    try std.testing.expect(instance.isComplete());
    try std.testing.expectEqual(@as(usize, 8), Complete.sizeof());
}

fn testListNode() !void {
    var node1 = ListNode.init(1);
    var node2 = ListNode.init(2);
    var node3 = ListNode.init(3);

    node1.append(&node2);
    node1.append(&node3);

    try std.testing.expectEqual(@as(usize, 3), node1.length());
    try std.testing.expectEqual(@as(i32, 1), node1.value);
    try std.testing.expectEqual(@as(i32, 2), node1.next.?.value);
    try std.testing.expectEqual(@as(i32, 3), node1.next.?.next.?.value);
}

fn testTreeNode() !void {
    var root = TreeNode.init(10);
    var left = TreeNode.init(5);
    var right = TreeNode.init(15);

    root.left = &left;
    root.right = &right;

    try std.testing.expect(!root.isLeaf());
    try std.testing.expect(left.isLeaf());
    try std.testing.expect(right.isLeaf());
    try std.testing.expectEqual(@as(usize, 2), root.height());
}

fn testOpaqueHandle() !void {
    var handle = OpaqueHandle.init(12345);
    try std.testing.expect(handle.isValid());

    handle.invalidate();
    try std.testing.expect(!handle.isValid());
}

fn testForwardDeclPtr() !void {
    var fwd = ForwardDeclPtr.init();
    try std.testing.expect(fwd.isNull());

    var dummy: i32 = 42;
    fwd.setPtr(@ptrCast(&dummy));
    try std.testing.expect(!fwd.isNull());
}

fn testIsIncomplete() !void {
    const Complete = struct {
        pub const is_complete = true;
    };
    const Incomplete = struct {
        pub const is_complete = false;
    };

    try std.testing.expect(!isIncomplete(Complete));
    try std.testing.expect(isIncomplete(Incomplete));
}

fn testSelfReferentialSize() !void {
    // ListNode should be able to calculate its size
    try std.testing.expect(@sizeOf(ListNode) >= @sizeOf(i32) + @sizeOf(?*ListNode));

    // TreeNode should have room for value and two pointers
    try std.testing.expect(@sizeOf(TreeNode) >= @sizeOf(i32) + 2 * @sizeOf(?*TreeNode));
}

fn testLinkedListTraversal() !void {
    var nodes: [5]ListNode = undefined;
    for (&nodes, 0..) |*node, i| {
        node.* = ListNode.init(@intCast(i));
    }

    // Link them
    for (0..4) |i| {
        nodes[i].next = &nodes[i + 1];
    }

    // Traverse
    var current: ?*ListNode = &nodes[0];
    var count: usize = 0;
    while (current) |node| {
        count += 1;
        current = node.next;
    }

    try std.testing.expectEqual(@as(usize, 5), count);
}

fn testTreeHeight() !void {
    //       1
    //      / \
    //     2   3
    //    /
    //   4
    var n1 = TreeNode.init(1);
    var n2 = TreeNode.init(2);
    var n3 = TreeNode.init(3);
    var n4 = TreeNode.init(4);

    n1.left = &n2;
    n1.right = &n3;
    n2.left = &n4;

    try std.testing.expectEqual(@as(usize, 3), n1.height());
    try std.testing.expectEqual(@as(usize, 2), n2.height());
    try std.testing.expectEqual(@as(usize, 1), n3.height());
    try std.testing.expectEqual(@as(usize, 1), n4.height());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "incomplete_type" {
    try testIncompleteType();
}

test "complete_type" {
    try testCompleteType();
}

test "list_node" {
    try testListNode();
}

test "tree_node" {
    try testTreeNode();
}

test "opaque_handle" {
    try testOpaqueHandle();
}

test "forward_decl_ptr" {
    try testForwardDeclPtr();
}

test "is_incomplete" {
    try testIsIncomplete();
}

test "self_referential_size" {
    try testSelfReferentialSize();
}

test "linked_list_traversal" {
    try testLinkedListTraversal();
}

test "tree_height" {
    try testTreeHeight();
}
