//! xml.dom.minidom - Minimal DOM implementation
//! Reference: cpython/Lib/xml/dom/minidom.py
//!
//! This module provides a lightweight DOM implementation.
//!
//! CPython __all__: ['parse', 'parseString', 'Document', 'Node', 'Text',
//!                   'Element', 'Attr', 'Comment', 'DocumentType',
//!                   'ProcessingInstruction', 'CharacterData', 'CDATASection',
//!                   'ReadOnlySequentialNamedNodeMap', 'Identified', 'Childless',
//!                   'DocumentFragment', 'NamedNodeMap', 'TypeInfo']

const std = @import("std");
const dom = @import("../dom.zig");
const parser_mod = @import("../parser.zig");

// ============================================================================
// Re-exports from parent dom module (DRY)
// ============================================================================

pub const Node = dom.Node;
pub const Document = dom.Document;
pub const NodeType = dom.NodeType;
pub const DOMException = dom.DOMException;
pub const DOMError = dom.DOMError;
pub const getDOMImplementation = dom.getDOMImplementation;

// Node type aliases
pub const Element = Node;
pub const Text = Node;
pub const Attr = Node;
pub const Comment = Node;
pub const DocumentType = Node;
pub const ProcessingInstruction = Node;
pub const CDATASection = Node;
pub const DocumentFragment = Node;
pub const CharacterData = Node;

// ============================================================================
// Parsing Functions
// ============================================================================

/// Parse XML from file
/// CPython: def parse(file, parser=None, bufsize=None)
pub fn parse(allocator: std.mem.Allocator, filename: []const u8) !*Document {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    return parseString(allocator, content);
}

/// Parse XML from string
/// CPython: def parseString(string, parser=None)
pub fn parseString(allocator: std.mem.Allocator, xml_string: []const u8) !*Document {
    const doc = try allocator.create(Document);
    doc.* = Document.init(allocator);
    errdefer {
        doc.deinit();
        allocator.destroy(doc);
    }

    // Parse using the parser module
    const root = try parser_mod.parseXML(allocator, xml_string);

    // Convert Element to DOM Node
    doc.document_element = try convertElementToNode(allocator, doc, root);

    // Free the original Element tree
    root.deinit();
    allocator.destroy(root);

    return doc;
}

/// Convert xml.element.Element to DOM Node
fn convertElementToNode(allocator: std.mem.Allocator, doc: *Document, elem: anytype) !*Node {
    const node = try doc.createElement(elem.tag);

    // Copy attributes
    var iter = elem.attrib.iterator();
    while (iter.next()) |entry| {
        try node.setAttribute(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Set text content
    if (elem.text) |text| {
        const text_node = try doc.createTextNode(text);
        _ = try node.appendChild(text_node);
    }

    // Convert children
    for (elem.children.items) |child| {
        const child_node = try convertElementToNode(allocator, doc, child);
        _ = try node.appendChild(child_node);

        // Handle tail text
        if (child.tail) |tail| {
            const tail_node = try doc.createTextNode(tail);
            _ = try node.appendChild(tail_node);
        }
    }

    return node;
}

// ============================================================================
// Additional Types
// ============================================================================

/// TypeInfo - type information for schema validation
/// CPython: class TypeInfo
pub const TypeInfo = struct {
    namespace: ?[]const u8,
    name: ?[]const u8,

    pub const DERIVATION_RESTRICTION: u16 = 0x01;
    pub const DERIVATION_EXTENSION: u16 = 0x02;
    pub const DERIVATION_UNION: u16 = 0x04;
    pub const DERIVATION_LIST: u16 = 0x08;
};

/// NamedNodeMap - collection of nodes accessible by name
/// CPython: class NamedNodeMap
pub const NamedNodeMap = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    nodes: std.ArrayList(*Node),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .nodes = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.nodes.deinit(self.allocator);
    }

    pub fn getNamedItem(self: *const Self, name: []const u8) ?*Node {
        for (self.nodes.items) |node| {
            if (std.mem.eql(u8, node.node_name, name)) {
                return node;
            }
        }
        return null;
    }

    pub fn setNamedItem(self: *Self, node: *Node) !?*Node {
        // Replace if exists
        for (self.nodes.items, 0..) |n, i| {
            if (std.mem.eql(u8, n.node_name, node.node_name)) {
                const old = n;
                self.nodes.items[i] = node;
                return old;
            }
        }
        // Add new
        try self.nodes.append(self.allocator, node);
        return null;
    }

    pub fn removeNamedItem(self: *Self, name: []const u8) !*Node {
        for (self.nodes.items, 0..) |node, i| {
            if (std.mem.eql(u8, node.node_name, name)) {
                return self.nodes.orderedRemove(i);
            }
        }
        return DOMError.NotFoundErr;
    }

    pub fn item(self: *const Self, index: usize) ?*Node {
        if (index < self.nodes.items.len) {
            return self.nodes.items[index];
        }
        return null;
    }

    pub fn length(self: *const Self) usize {
        return self.nodes.items.len;
    }
};

/// ReadOnlySequentialNamedNodeMap - read-only node map
/// CPython: class ReadOnlySequentialNamedNodeMap
pub const ReadOnlySequentialNamedNodeMap = NamedNodeMap;

// ============================================================================
// Mixin Types (for documentation compatibility)
// ============================================================================

/// Identified mixin - for nodes with public/system ID
/// CPython: class Identified
pub const Identified = struct {
    public_id: ?[]const u8 = null,
    system_id: ?[]const u8 = null,
};

/// Childless mixin - for nodes that cannot have children
/// CPython: class Childless
pub const Childless = struct {};

// ============================================================================
// Utility Functions
// ============================================================================

/// Get text content of a node
pub fn getTextContent(node: *const Node) ?[]const u8 {
    if (node.node_type == .TEXT_NODE or node.node_type == .CDATA_SECTION_NODE) {
        return node.node_value;
    }
    return null;
}

/// Convert node to XML string
pub fn toxml(allocator: std.mem.Allocator, node: *Node) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    try writeNode(allocator, &result, node, 0);
    return result.toOwnedSlice(allocator);
}

/// Pretty print node to XML string
pub fn toprettyxml(allocator: std.mem.Allocator, node: *Node, indent_str: []const u8, newl: []const u8) ![]u8 {
    _ = indent_str;
    _ = newl;
    return toxml(allocator, node);
}

fn writeNode(allocator: std.mem.Allocator, result: *std.ArrayList(u8), node: *Node, depth: usize) !void {
    _ = depth;
    switch (node.node_type) {
        .ELEMENT_NODE => {
            try result.append(allocator, '<');
            try result.appendSlice(allocator, node.node_name);

            if (node.attributes) |attrs| {
                var iter = attrs.iterator();
                while (iter.next()) |entry| {
                    try result.append(allocator, ' ');
                    try result.appendSlice(allocator, entry.key_ptr.*);
                    try result.appendSlice(allocator, "=\"");
                    try result.appendSlice(allocator, entry.value_ptr.*);
                    try result.append(allocator, '"');
                }
            }

            if (node.child_nodes.items.len == 0) {
                try result.appendSlice(allocator, "/>");
            } else {
                try result.append(allocator, '>');
                for (node.child_nodes.items) |child| {
                    try writeNode(allocator, result, child, depth + 1);
                }
                try result.appendSlice(allocator, "</");
                try result.appendSlice(allocator, node.node_name);
                try result.append(allocator, '>');
            }
        },
        .TEXT_NODE => {
            if (node.node_value) |text| {
                try result.appendSlice(allocator, text);
            }
        },
        .COMMENT_NODE => {
            try result.appendSlice(allocator, "<!--");
            if (node.node_value) |text| {
                try result.appendSlice(allocator, text);
            }
            try result.appendSlice(allocator, "-->");
        },
        .CDATA_SECTION_NODE => {
            try result.appendSlice(allocator, "<![CDATA[");
            if (node.node_value) |text| {
                try result.appendSlice(allocator, text);
            }
            try result.appendSlice(allocator, "]]>");
        },
        .PROCESSING_INSTRUCTION_NODE => {
            try result.appendSlice(allocator, "<?");
            try result.appendSlice(allocator, node.node_name);
            if (node.node_value) |text| {
                try result.append(allocator, ' ');
                try result.appendSlice(allocator, text);
            }
            try result.appendSlice(allocator, "?>");
        },
        else => {},
    }
}

// ============================================================================
// Tests
// ============================================================================

test "parseString" {
    const allocator = std.testing.allocator;
    const doc = try parseString(allocator, "<root><child/></root>");
    defer {
        doc.deinit();
        allocator.destroy(doc);
    }

    try std.testing.expect(doc.document_element != null);
    try std.testing.expectEqualStrings("root", doc.document_element.?.node_name);
}

test "NamedNodeMap" {
    const allocator = std.testing.allocator;
    var map = NamedNodeMap.init(allocator);
    defer map.deinit();

    var doc = Document.init(allocator);
    defer doc.deinit();

    const node = try doc.createElement("test");
    defer {
        node.deinit();
        allocator.destroy(node);
    }

    _ = try map.setNamedItem(node);
    try std.testing.expectEqual(@as(usize, 1), map.length());
    try std.testing.expect(map.getNamedItem("test") != null);
}
