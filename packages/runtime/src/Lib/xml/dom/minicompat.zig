//! xml.dom.minicompat - Compatibility helpers for minidom
//! Reference: cpython/Lib/xml/dom/minicompat.py
//!
//! This module provides compatibility classes for minidom.

const std = @import("std");
const dom = @import("../dom.zig");

// ============================================================================
// NodeList
// ============================================================================

/// Read-only list of nodes
/// CPython: class NodeList(list)
pub const NodeList = struct {
    const Self = @This();

    items: []*dom.Node,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .items = &[_]*dom.Node{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.items.len > 0) {
            self.allocator.free(self.items);
        }
    }

    /// Get item at index
    pub fn item(self: *const Self, index: usize) ?*dom.Node {
        if (index < self.items.len) {
            return self.items[index];
        }
        return null;
    }

    /// Get number of items
    pub fn length(self: *const Self) usize {
        return self.items.len;
    }

    /// Check if list contains a value
    pub fn contains(self: *const Self, node: *dom.Node) bool {
        for (self.items) |item_node| {
            if (item_node == node) return true;
        }
        return false;
    }
};

// ============================================================================
// EmptyNodeList
// ============================================================================

/// Empty node list singleton
/// CPython: class EmptyNodeList(tuple)
pub const EmptyNodeList = struct {
    pub fn item(_: *const EmptyNodeList, _: usize) ?*dom.Node {
        return null;
    }

    pub fn length(_: *const EmptyNodeList) usize {
        return 0;
    }

    pub fn contains(_: *const EmptyNodeList, _: *dom.Node) bool {
        return false;
    }
};

/// Singleton empty node list
pub const empty_node_list = EmptyNodeList{};

// ============================================================================
// StringTypes
// ============================================================================

/// Check if value is a string type
pub fn isString(value: anytype) bool {
    const T = @TypeOf(value);
    return T == []const u8 or T == []u8;
}

// ============================================================================
// defproperty helper
// ============================================================================

/// Define a property (compatibility helper)
/// CPython: def defproperty(klass, name, doc)
pub fn defproperty(comptime T: type, name: []const u8, doc: []const u8) void {
    _ = T;
    _ = name;
    _ = doc;
    // In Zig, properties are implemented as struct fields
}

// ============================================================================
// Tests
// ============================================================================

test "NodeList" {
    const allocator = std.testing.allocator;
    var list = NodeList.init(allocator);
    defer list.deinit();

    try std.testing.expectEqual(@as(usize, 0), list.length());
    try std.testing.expect(list.item(0) == null);
}

test "EmptyNodeList" {
    try std.testing.expectEqual(@as(usize, 0), empty_node_list.length());
    try std.testing.expect(empty_node_list.item(0) == null);
}
