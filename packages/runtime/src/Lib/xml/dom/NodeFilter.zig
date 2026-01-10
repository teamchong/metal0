//! xml.dom.NodeFilter - DOM Level 2 NodeFilter interface
//! Reference: cpython/Lib/xml/dom/NodeFilter.py
//!
//! This module provides the NodeFilter interface for DOM tree traversal.

const std = @import("std");
const dom = @import("../dom.zig");

// ============================================================================
// NodeFilter Constants (W3C DOM Level 2 Traversal)
// ============================================================================

/// Filter return values
pub const FILTER_ACCEPT: i16 = 1;
pub const FILTER_REJECT: i16 = 2;
pub const FILTER_SKIP: i16 = 3;

/// What to show constants
pub const SHOW_ALL: u32 = 0xFFFFFFFF;
pub const SHOW_ELEMENT: u32 = 0x00000001;
pub const SHOW_ATTRIBUTE: u32 = 0x00000002;
pub const SHOW_TEXT: u32 = 0x00000004;
pub const SHOW_CDATA_SECTION: u32 = 0x00000008;
pub const SHOW_ENTITY_REFERENCE: u32 = 0x00000010;
pub const SHOW_ENTITY: u32 = 0x00000020;
pub const SHOW_PROCESSING_INSTRUCTION: u32 = 0x00000040;
pub const SHOW_COMMENT: u32 = 0x00000080;
pub const SHOW_DOCUMENT: u32 = 0x00000100;
pub const SHOW_DOCUMENT_TYPE: u32 = 0x00000200;
pub const SHOW_DOCUMENT_FRAGMENT: u32 = 0x00000400;
pub const SHOW_NOTATION: u32 = 0x00000800;

// ============================================================================
// NodeFilter Interface
// ============================================================================

/// NodeFilter interface
/// CPython: class NodeFilter
pub const NodeFilter = struct {
    const Self = @This();

    /// Filter function type
    pub const FilterFn = *const fn (node: *dom.Node) i16;

    filter_fn: ?FilterFn,

    pub fn init() Self {
        return .{ .filter_fn = null };
    }

    /// Accept node
    /// CPython: def acceptNode(self, node)
    pub fn acceptNode(self: *const Self, node: *dom.Node) i16 {
        if (self.filter_fn) |f| {
            return f(node);
        }
        return FILTER_ACCEPT;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if node type matches show mask
pub fn matchesShowMask(node: *const dom.Node, what_to_show: u32) bool {
    const node_bit: u32 = switch (node.node_type) {
        .ELEMENT_NODE => SHOW_ELEMENT,
        .ATTRIBUTE_NODE => SHOW_ATTRIBUTE,
        .TEXT_NODE => SHOW_TEXT,
        .CDATA_SECTION_NODE => SHOW_CDATA_SECTION,
        .ENTITY_REFERENCE_NODE => SHOW_ENTITY_REFERENCE,
        .ENTITY_NODE => SHOW_ENTITY,
        .PROCESSING_INSTRUCTION_NODE => SHOW_PROCESSING_INSTRUCTION,
        .COMMENT_NODE => SHOW_COMMENT,
        .DOCUMENT_NODE => SHOW_DOCUMENT,
        .DOCUMENT_TYPE_NODE => SHOW_DOCUMENT_TYPE,
        .DOCUMENT_FRAGMENT_NODE => SHOW_DOCUMENT_FRAGMENT,
        .NOTATION_NODE => SHOW_NOTATION,
    };
    return (what_to_show & node_bit) != 0;
}

// ============================================================================
// Tests
// ============================================================================

test "NodeFilter constants" {
    try std.testing.expectEqual(@as(i16, 1), FILTER_ACCEPT);
    try std.testing.expectEqual(@as(i16, 2), FILTER_REJECT);
    try std.testing.expectEqual(@as(i16, 3), FILTER_SKIP);
}

test "matchesShowMask" {
    const allocator = std.testing.allocator;
    var doc = dom.Document.init(allocator);
    defer doc.deinit();

    const elem = try doc.createElement("test");
    defer {
        elem.deinit();
        allocator.destroy(elem);
    }

    try std.testing.expect(matchesShowMask(elem, SHOW_ELEMENT));
    try std.testing.expect(matchesShowMask(elem, SHOW_ALL));
    try std.testing.expect(!matchesShowMask(elem, SHOW_TEXT));
}
