//! xml.dom - DOM API for XML processing
//! Reference: cpython/Lib/xml/dom/__init__.py
//!
//! This package provides the W3C DOM API for XML document manipulation.
//!
//! CPython __all__: ['INDEX_SIZE_ERR', 'DOMSTRING_SIZE_ERR', 'HIERARCHY_REQUEST_ERR',
//!                   'WRONG_DOCUMENT_ERR', 'INVALID_CHARACTER_ERR', 'NO_DATA_ALLOWED_ERR',
//!                   'NO_MODIFICATION_ALLOWED_ERR', 'NOT_FOUND_ERR', 'NOT_SUPPORTED_ERR',
//!                   'INUSE_ATTRIBUTE_ERR', 'INVALID_STATE_ERR', 'SYNTAX_ERR',
//!                   'INVALID_MODIFICATION_ERR', 'NAMESPACE_ERR', 'INVALID_ACCESS_ERR',
//!                   'VALIDATION_ERR', 'DOMException', 'getDOMImplementation',
//!                   'registerDOMImplementation', 'EMPTY_NAMESPACE', 'XML_NAMESPACE',
//!                   'XMLNS_NAMESPACE', 'XHTML_NAMESPACE']

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// DOM Exception Codes (W3C DOM Level 2)
// ============================================================================

pub const INDEX_SIZE_ERR: u16 = 1;
pub const DOMSTRING_SIZE_ERR: u16 = 2;
pub const HIERARCHY_REQUEST_ERR: u16 = 3;
pub const WRONG_DOCUMENT_ERR: u16 = 4;
pub const INVALID_CHARACTER_ERR: u16 = 5;
pub const NO_DATA_ALLOWED_ERR: u16 = 6;
pub const NO_MODIFICATION_ALLOWED_ERR: u16 = 7;
pub const NOT_FOUND_ERR: u16 = 8;
pub const NOT_SUPPORTED_ERR: u16 = 9;
pub const INUSE_ATTRIBUTE_ERR: u16 = 10;
pub const INVALID_STATE_ERR: u16 = 11;
pub const SYNTAX_ERR: u16 = 12;
pub const INVALID_MODIFICATION_ERR: u16 = 13;
pub const NAMESPACE_ERR: u16 = 14;
pub const INVALID_ACCESS_ERR: u16 = 15;
pub const VALIDATION_ERR: u16 = 16;

// ============================================================================
// Namespace Constants
// ============================================================================

/// Empty namespace
pub const EMPTY_NAMESPACE: ?[]const u8 = null;

/// XML namespace
pub const XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace";

/// XMLNS namespace
pub const XMLNS_NAMESPACE = "http://www.w3.org/2000/xmlns/";

/// XHTML namespace
pub const XHTML_NAMESPACE = "http://www.w3.org/1999/xhtml";

// ============================================================================
// DOMException
// ============================================================================

/// DOM Exception
/// CPython: class DOMException(Exception)
pub const DOMException = struct {
    code: u16,
    msg: ?[]const u8,

    pub fn init(code: u16, msg: ?[]const u8) DOMException {
        return .{ .code = code, .msg = msg };
    }
};

/// DOM Exception error type
pub const DOMError = error{
    IndexSizeErr,
    DomstringSizeErr,
    HierarchyRequestErr,
    WrongDocumentErr,
    InvalidCharacterErr,
    NoDataAllowedErr,
    NoModificationAllowedErr,
    NotFoundErr,
    NotSupportedErr,
    InuseAttributeErr,
    InvalidStateErr,
    SyntaxErr,
    InvalidModificationErr,
    NamespaceErr,
    InvalidAccessErr,
    ValidationErr,
};

// ============================================================================
// Node Types (W3C DOM)
// ============================================================================

pub const NodeType = enum(u16) {
    ELEMENT_NODE = 1,
    ATTRIBUTE_NODE = 2,
    TEXT_NODE = 3,
    CDATA_SECTION_NODE = 4,
    ENTITY_REFERENCE_NODE = 5,
    ENTITY_NODE = 6,
    PROCESSING_INSTRUCTION_NODE = 7,
    COMMENT_NODE = 8,
    DOCUMENT_NODE = 9,
    DOCUMENT_TYPE_NODE = 10,
    DOCUMENT_FRAGMENT_NODE = 11,
    NOTATION_NODE = 12,
};

// ============================================================================
// Node Interface
// ============================================================================

/// DOM Node
/// CPython: Uses xml.dom.minidom.Node
pub const Node = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    node_type: NodeType,
    node_name: []const u8,
    node_value: ?[]const u8,
    parent_node: ?*Node,
    child_nodes: std.ArrayList(*Node),
    attributes: ?hashmap_helper.StringHashMap([]const u8),
    owner_document: ?*Document,
    namespace_uri: ?[]const u8,
    prefix: ?[]const u8,
    local_name: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType, node_name: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .node_type = node_type,
            .node_name = try allocator.dupe(u8, node_name),
            .node_value = null,
            .parent_node = null,
            .child_nodes = .{},
            .attributes = null,
            .owner_document = null,
            .namespace_uri = null,
            .prefix = null,
            .local_name = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.node_name);
        if (self.node_value) |v| self.allocator.free(v);
        if (self.namespace_uri) |ns| self.allocator.free(ns);
        if (self.prefix) |p| self.allocator.free(p);
        if (self.local_name) |ln| self.allocator.free(ln);

        if (self.attributes) |*attrs| {
            var iter = attrs.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            attrs.deinit();
        }

        for (self.child_nodes.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.child_nodes.deinit(self.allocator);
    }

    /// Append child node
    pub fn appendChild(self: *Self, child: *Node) !*Node {
        child.parent_node = self;
        try self.child_nodes.append(self.allocator, child);
        return child;
    }

    /// Insert before reference node
    pub fn insertBefore(self: *Self, new_child: *Node, ref_child: ?*Node) !*Node {
        new_child.parent_node = self;
        if (ref_child) |ref| {
            for (self.child_nodes.items, 0..) |child, i| {
                if (child == ref) {
                    try self.child_nodes.insert(self.allocator, i, new_child);
                    return new_child;
                }
            }
        }
        try self.child_nodes.append(self.allocator, new_child);
        return new_child;
    }

    /// Remove child node
    pub fn removeChild(self: *Self, old_child: *Node) !*Node {
        for (self.child_nodes.items, 0..) |child, i| {
            if (child == old_child) {
                _ = self.child_nodes.orderedRemove(i);
                old_child.parent_node = null;
                return old_child;
            }
        }
        return DOMError.NotFoundErr;
    }

    /// Replace child node
    pub fn replaceChild(self: *Self, new_child: *Node, old_child: *Node) !*Node {
        for (self.child_nodes.items, 0..) |child, i| {
            if (child == old_child) {
                new_child.parent_node = self;
                self.child_nodes.items[i] = new_child;
                old_child.parent_node = null;
                return old_child;
            }
        }
        return DOMError.NotFoundErr;
    }

    /// Check if node has child nodes
    pub fn hasChildNodes(self: *const Self) bool {
        return self.child_nodes.items.len > 0;
    }

    /// Clone node
    pub fn cloneNode(self: *Self, deep: bool) !*Node {
        const clone = try Node.init(self.allocator, self.node_type, self.node_name);
        if (self.node_value) |v| {
            clone.node_value = try self.allocator.dupe(u8, v);
        }

        if (self.attributes) |*attrs| {
            clone.attributes = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
            var iter = attrs.iterator();
            while (iter.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                const value = try self.allocator.dupe(u8, entry.value_ptr.*);
                try clone.attributes.?.put(key, value);
            }
        }

        if (deep) {
            for (self.child_nodes.items) |child| {
                const child_clone = try child.cloneNode(true);
                _ = try clone.appendChild(child_clone);
            }
        }

        return clone;
    }

    /// Normalize node (merge adjacent text nodes)
    pub fn normalize(self: *Self) void {
        var i: usize = 0;
        while (i < self.child_nodes.items.len) {
            const child = self.child_nodes.items[i];
            if (child.node_type == .TEXT_NODE and i + 1 < self.child_nodes.items.len) {
                const next = self.child_nodes.items[i + 1];
                if (next.node_type == .TEXT_NODE) {
                    // Merge text nodes
                    if (child.node_value) |v1| {
                        if (next.node_value) |v2| {
                            const merged = std.mem.concat(self.allocator, u8, &.{ v1, v2 }) catch continue;
                            self.allocator.free(v1);
                            child.node_value = merged;
                        }
                    }
                    _ = self.child_nodes.orderedRemove(i + 1);
                    next.deinit();
                    self.allocator.destroy(next);
                    continue;
                }
            }
            child.normalize();
            i += 1;
        }
    }

    /// Get first child
    pub fn firstChild(self: *const Self) ?*Node {
        if (self.child_nodes.items.len > 0) {
            return self.child_nodes.items[0];
        }
        return null;
    }

    /// Get last child
    pub fn lastChild(self: *const Self) ?*Node {
        if (self.child_nodes.items.len > 0) {
            return self.child_nodes.items[self.child_nodes.items.len - 1];
        }
        return null;
    }

    /// Get previous sibling
    pub fn previousSibling(self: *const Self) ?*Node {
        if (self.parent_node) |parent| {
            for (parent.child_nodes.items, 0..) |child, i| {
                if (child == self and i > 0) {
                    return parent.child_nodes.items[i - 1];
                }
            }
        }
        return null;
    }

    /// Get next sibling
    pub fn nextSibling(self: *const Self) ?*Node {
        if (self.parent_node) |parent| {
            for (parent.child_nodes.items, 0..) |child, i| {
                if (child == self and i + 1 < parent.child_nodes.items.len) {
                    return parent.child_nodes.items[i + 1];
                }
            }
        }
        return null;
    }

    /// Get/set attribute
    pub fn getAttribute(self: *const Self, name: []const u8) ?[]const u8 {
        if (self.attributes) |attrs| {
            return attrs.get(name);
        }
        return null;
    }

    pub fn setAttribute(self: *Self, name: []const u8, value: []const u8) !void {
        if (self.attributes == null) {
            self.attributes = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
        }
        const k = try self.allocator.dupe(u8, name);
        const v = try self.allocator.dupe(u8, value);
        try self.attributes.?.put(k, v);
    }

    pub fn removeAttribute(self: *Self, name: []const u8) void {
        if (self.attributes) |*attrs| {
            _ = attrs.remove(name);
        }
    }

    pub fn hasAttribute(self: *const Self, name: []const u8) bool {
        if (self.attributes) |attrs| {
            return attrs.contains(name);
        }
        return false;
    }
};

// ============================================================================
// Document Interface
// ============================================================================

/// DOM Document
/// CPython: xml.dom.minidom.Document
pub const Document = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    document_element: ?*Node,
    doctype: ?*Node,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .document_element = null,
            .doctype = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.document_element) |elem| {
            elem.deinit();
            self.allocator.destroy(elem);
        }
        if (self.doctype) |dt| {
            dt.deinit();
            self.allocator.destroy(dt);
        }
    }

    /// Create element
    pub fn createElement(self: *Self, tag_name: []const u8) !*Node {
        const node = try Node.init(self.allocator, .ELEMENT_NODE, tag_name);
        node.owner_document = self;
        node.attributes = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
        return node;
    }

    /// Create element with namespace
    pub fn createElementNS(self: *Self, namespace_uri: ?[]const u8, qualified_name: []const u8) !*Node {
        const node = try self.createElement(qualified_name);
        if (namespace_uri) |ns| {
            node.namespace_uri = try self.allocator.dupe(u8, ns);
        }
        return node;
    }

    /// Create text node
    pub fn createTextNode(self: *Self, data: []const u8) !*Node {
        const node = try Node.init(self.allocator, .TEXT_NODE, "#text");
        node.node_value = try self.allocator.dupe(u8, data);
        node.owner_document = self;
        return node;
    }

    /// Create comment
    pub fn createComment(self: *Self, data: []const u8) !*Node {
        const node = try Node.init(self.allocator, .COMMENT_NODE, "#comment");
        node.node_value = try self.allocator.dupe(u8, data);
        node.owner_document = self;
        return node;
    }

    /// Create CDATA section
    pub fn createCDATASection(self: *Self, data: []const u8) !*Node {
        const node = try Node.init(self.allocator, .CDATA_SECTION_NODE, "#cdata-section");
        node.node_value = try self.allocator.dupe(u8, data);
        node.owner_document = self;
        return node;
    }

    /// Create processing instruction
    pub fn createProcessingInstruction(self: *Self, target: []const u8, data: []const u8) !*Node {
        const node = try Node.init(self.allocator, .PROCESSING_INSTRUCTION_NODE, target);
        node.node_value = try self.allocator.dupe(u8, data);
        node.owner_document = self;
        return node;
    }

    /// Create attribute
    pub fn createAttribute(self: *Self, name: []const u8) !*Node {
        const node = try Node.init(self.allocator, .ATTRIBUTE_NODE, name);
        node.owner_document = self;
        return node;
    }

    /// Create document fragment
    pub fn createDocumentFragment(self: *Self) !*Node {
        const node = try Node.init(self.allocator, .DOCUMENT_FRAGMENT_NODE, "#document-fragment");
        node.owner_document = self;
        return node;
    }

    /// Get elements by tag name
    pub fn getElementsByTagName(self: *Self, name: []const u8) ![]*Node {
        var result: std.ArrayList(*Node) = .{};
        if (self.document_element) |root| {
            try collectByTagName(self.allocator, &result, root, name);
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Get element by ID
    pub fn getElementById(self: *Self, element_id: []const u8) ?*Node {
        if (self.document_element) |root| {
            return findById(root, element_id);
        }
        return null;
    }
};

fn collectByTagName(allocator: std.mem.Allocator, result: *std.ArrayList(*Node), node: *Node, name: []const u8) !void {
    if (node.node_type == .ELEMENT_NODE) {
        if (std.mem.eql(u8, name, "*") or std.mem.eql(u8, node.node_name, name)) {
            try result.append(allocator, node);
        }
    }
    for (node.child_nodes.items) |child| {
        try collectByTagName(allocator, result, child, name);
    }
}

fn findById(node: *Node, id: []const u8) ?*Node {
    if (node.getAttribute("id")) |node_id| {
        if (std.mem.eql(u8, node_id, id)) return node;
    }
    for (node.child_nodes.items) |child| {
        if (findById(child, id)) |found| return found;
    }
    return null;
}

// ============================================================================
// DOMImplementation
// ============================================================================

/// DOM Implementation registry
var _implementations: ?hashmap_helper.StringHashMap(*const DOMImplementation) = null;

/// DOM Implementation
/// CPython: class DOMImplementation
pub const DOMImplementation = struct {
    name: []const u8,

    pub fn hasFeature(self: *const DOMImplementation, feature: []const u8, version: ?[]const u8) bool {
        _ = self;
        _ = version;
        // Support basic DOM features
        if (std.mem.eql(u8, feature, "XML") or std.mem.eql(u8, feature, "Core")) {
            return true;
        }
        return false;
    }

    pub fn createDocument(self: *const DOMImplementation, allocator: std.mem.Allocator, namespace_uri: ?[]const u8, qualified_name: ?[]const u8, doctype: ?*Node) !*Document {
        _ = self;
        const doc = try allocator.create(Document);
        doc.* = Document.init(allocator);
        doc.doctype = doctype;

        if (qualified_name) |qname| {
            const root = try doc.createElementNS(namespace_uri, qname);
            doc.document_element = root;
        }

        return doc;
    }

    pub fn createDocumentType(self: *const DOMImplementation, allocator: std.mem.Allocator, qualified_name: []const u8, public_id: ?[]const u8, system_id: ?[]const u8) !*Node {
        _ = self;
        _ = public_id;
        _ = system_id;
        const node = try Node.init(allocator, .DOCUMENT_TYPE_NODE, qualified_name);
        return node;
    }
};

/// Default implementation
const default_impl = DOMImplementation{ .name = "minidom" };

/// Get DOM implementation
/// CPython: def getDOMImplementation(name=None, features=())
pub fn getDOMImplementation(name: ?[]const u8) *const DOMImplementation {
    if (name) |n| {
        if (_implementations) |impls| {
            if (impls.get(n)) |impl| return impl;
        }
    }
    return &default_impl;
}

/// Register DOM implementation
/// CPython: def registerDOMImplementation(name, factory)
pub fn registerDOMImplementation(allocator: std.mem.Allocator, name: []const u8, impl: *const DOMImplementation) !void {
    if (_implementations == null) {
        _implementations = hashmap_helper.StringHashMap(*const DOMImplementation).init(allocator);
    }
    try _implementations.?.put(name, impl);
}

// ============================================================================
// Tests
// ============================================================================

test "Document createElement" {
    const allocator = std.testing.allocator;
    var doc = Document.init(allocator);
    defer doc.deinit();

    const elem = try doc.createElement("div");
    defer {
        elem.deinit();
        allocator.destroy(elem);
    }

    try std.testing.expectEqualStrings("div", elem.node_name);
    try std.testing.expect(elem.node_type == .ELEMENT_NODE);
}

test "Node appendChild" {
    const allocator = std.testing.allocator;
    var doc = Document.init(allocator);
    defer doc.deinit();

    const parent = try doc.createElement("parent");
    defer {
        parent.deinit();
        allocator.destroy(parent);
    }

    const child = try doc.createElement("child");
    _ = try parent.appendChild(child);

    try std.testing.expect(parent.hasChildNodes());
    try std.testing.expectEqual(@as(usize, 1), parent.child_nodes.items.len);
}

test "DOMImplementation" {
    const impl = getDOMImplementation(null);
    try std.testing.expect(impl.hasFeature("XML", null));
    try std.testing.expect(impl.hasFeature("Core", null));
}
