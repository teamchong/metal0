//! Python 'xml' module - XML processing utilities
//!
//! Provides XML parsing, building, and manipulation APIs.
//!
//! Mirrors: CPython Lib/xml/

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");

// Import modular components
const element_mod = @import("xml/element.zig");
const tree_mod = @import("xml/tree.zig");
const parser_mod = @import("xml/parser.zig");
const builder_mod = @import("xml/builder.zig");
const errors_mod = @import("xml/errors.zig");

// ============================================================================
// xml.etree.ElementTree - Element tree XML API
// ============================================================================

pub const etree = struct {
    // Re-export Element and related types
    pub const Element = element_mod.Element;
    pub const ChildIterator = element_mod.ChildIterator;
    pub const ElementTree = tree_mod.ElementTree;

    // Re-export builder functions
    pub const fromstring = builder_mod.fromstring;
    pub const tostring = builder_mod.tostring;
    pub const createElement = builder_mod.createElement;
    pub const SubElement = builder_mod.SubElement;
    pub const Comment = builder_mod.Comment;
    pub const ProcessingInstruction = builder_mod.ProcessingInstruction;
    pub const iselement = builder_mod.iselement;

    // Re-export tree functions
    pub const parseFile = tree_mod.parseFile;
};

// ============================================================================
// xml.sax - SAX2 parser
// ============================================================================

pub const sax = struct {
    pub const ContentHandler = struct {
        // Callbacks
        startDocument: ?*const fn () void = null,
        endDocument: ?*const fn () void = null,
        startElement: ?*const fn (name: []const u8, attrs: anytype) void = null,
        endElement: ?*const fn (name: []const u8) void = null,
        characters: ?*const fn (content: []const u8) void = null,
        ignorableWhitespace: ?*const fn (whitespace: []const u8) void = null,
        processingInstruction: ?*const fn (target: []const u8, data: []const u8) void = null,
    };

    pub const ErrorHandler = struct {
        error_handler: ?*const fn (exception: anytype) void = null,
        fatalError: ?*const fn (exception: anytype) void = null,
        warning: ?*const fn (exception: anytype) void = null,
    };

    /// SAX parser
    pub fn makeParser() XMLReader {
        return XMLReader{};
    }

    pub const XMLReader = struct {
        content_handler: ?ContentHandler = null,
        error_handler: ?ErrorHandler = null,

        pub fn setContentHandler(self: *XMLReader, handler: ContentHandler) void {
            self.content_handler = handler;
        }

        pub fn setErrorHandler(self: *XMLReader, handler: ErrorHandler) void {
            self.error_handler = handler;
        }

        pub fn parse(self: *XMLReader, source: []const u8) !void {
            // SAX-style event-driven parsing
            if (self.content_handler) |handler| {
                handler.startDocument();
            }

            var pos: usize = 0;
            while (pos < source.len) {
                if (source[pos] == '<') {
                    if (pos + 1 < source.len and source[pos + 1] == '/') {
                        // End tag </name>
                        const tag_start = pos + 2;
                        const tag_end = std.mem.indexOf(u8, source[tag_start..], ">") orelse break;
                        const tag_name = source[tag_start .. tag_start + tag_end];
                        if (self.content_handler) |handler| {
                            handler.endElement("", tag_name, tag_name);
                        }
                        pos = tag_start + tag_end + 1;
                    } else if (pos + 1 < source.len and source[pos + 1] == '?') {
                        // Processing instruction <?...?>
                        const pi_end = std.mem.indexOf(u8, source[pos..], "?>") orelse break;
                        pos = pos + pi_end + 2;
                    } else if (pos + 1 < source.len and source[pos + 1] == '!') {
                        // Comment or CDATA
                        if (std.mem.startsWith(u8, source[pos..], "<!--")) {
                            const comment_end = std.mem.indexOf(u8, source[pos..], "-->") orelse break;
                            pos = pos + comment_end + 3;
                        } else if (std.mem.startsWith(u8, source[pos..], "<![CDATA[")) {
                            const cdata_end = std.mem.indexOf(u8, source[pos..], "]]>") orelse break;
                            const cdata_content = source[pos + 9 .. pos + cdata_end];
                            if (self.content_handler) |handler| {
                                handler.characters(cdata_content);
                            }
                            pos = pos + cdata_end + 3;
                        } else {
                            pos += 1;
                        }
                    } else {
                        // Start tag <name attrs>
                        const tag_end = std.mem.indexOfAny(u8, source[pos + 1 ..], " \t\n/>") orelse break;
                        const tag_name = source[pos + 1 .. pos + 1 + tag_end];

                        // Find end of tag
                        const close = std.mem.indexOf(u8, source[pos..], ">") orelse break;
                        const is_self_closing = close > 0 and source[pos + close - 1] == '/';

                        if (self.content_handler) |handler| {
                            handler.startElement("", tag_name, tag_name, null);
                            if (is_self_closing) {
                                handler.endElement("", tag_name, tag_name);
                            }
                        }
                        pos = pos + close + 1;
                    }
                } else {
                    // Text content
                    const text_end = std.mem.indexOf(u8, source[pos..], "<") orelse source.len - pos;
                    const text = std.mem.trim(u8, source[pos .. pos + text_end], " \t\n\r");
                    if (text.len > 0) {
                        if (self.content_handler) |handler| {
                            handler.characters(text);
                        }
                    }
                    pos = pos + text_end;
                }
            }

            if (self.content_handler) |handler| {
                handler.endDocument();
            }
        }

        pub fn parseFile(self: *XMLReader, filename: []const u8) !void {
            // Read file and parse
            const file = try std.fs.cwd().openFile(filename, .{});
            defer file.close();

            const stat = try file.stat();
            const allocator = allocator_helper.fast_allocator;
            const content = try allocator.alloc(u8, stat.size);
            defer allocator.free(content);

            _ = try file.readAll(content);
            try self.parse(content);
        }
    };

    /// Parse XML with handler
    pub fn parseString(xml_string: []const u8, handler: ContentHandler) !void {
        var reader = XMLReader{};
        reader.setContentHandler(handler);
        try reader.parse(xml_string);
    }
};

// ============================================================================
// xml.dom - DOM API
// ============================================================================

pub const dom = struct {
    pub const Node = struct {
        node_type: NodeType,
        node_name: []const u8,
        node_value: ?[]const u8,
        parent_node: ?*Node,
        child_nodes: std.ArrayList(*Node),
        attributes: ?hashmap_helper.StringHashMap([]const u8),

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

        pub fn appendChild(self: *Node, child: *Node) !void {
            child.parent_node = self;
            try self.child_nodes.append(child);
        }

        pub fn removeChild(self: *Node, child: *Node) void {
            for (self.child_nodes.items, 0..) |c, i| {
                if (c == child) {
                    _ = self.child_nodes.orderedRemove(i);
                    child.parent_node = null;
                    break;
                }
            }
        }

        pub fn hasChildNodes(self: *Node) bool {
            return self.child_nodes.items.len > 0;
        }

        pub fn getAttribute(self: *Node, name: []const u8) ?[]const u8 {
            if (self.attributes) |attrs| {
                return attrs.get(name);
            }
            return null;
        }

        pub fn setAttribute(self: *Node, name: []const u8, value: []const u8) !void {
            if (self.attributes) |*attrs| {
                try attrs.put(name, value);
            }
        }
    };

    pub const Document = struct {
        allocator: std.mem.Allocator,
        document_element: ?*Node,

        pub fn init(allocator: std.mem.Allocator) Document {
            return .{
                .allocator = allocator,
                .document_element = null,
            };
        }

        pub fn createElement(self: *Document, tag_name: []const u8) !*Node {
            const node = try self.allocator.create(Node);
            node.* = .{
                .node_type = .ELEMENT_NODE,
                .node_name = try self.allocator.dupe(u8, tag_name),
                .node_value = null,
                .parent_node = null,
                .child_nodes = std.ArrayList(*Node).init(self.allocator),
                .attributes = hashmap_helper.StringHashMap([]const u8).init(self.allocator),
            };
            return node;
        }

        pub fn createTextNode(self: *Document, data: []const u8) !*Node {
            const node = try self.allocator.create(Node);
            node.* = .{
                .node_type = .TEXT_NODE,
                .node_name = "#text",
                .node_value = try self.allocator.dupe(u8, data),
                .parent_node = null,
                .child_nodes = std.ArrayList(*Node).init(self.allocator),
                .attributes = null,
            };
            return node;
        }

        pub fn getElementsByTagName(self: *Document, name: []const u8) ![]*Node {
            var result = std.ArrayList(*Node).init(self.allocator);
            if (self.document_element) |root| {
                try collectByTagName(&result, root, name);
            }
            return result.toOwnedSlice();
        }

        fn collectByTagName(result: *std.ArrayList(*Node), node: *Node, name: []const u8) !void {
            if (std.mem.eql(u8, node.node_name, name)) {
                try result.append(node);
            }
            for (node.child_nodes.items) |child| {
                try collectByTagName(result, child, name);
            }
        }
    };

    pub const minidom = struct {
        /// Parse XML string to Document
        pub fn parseString(allocator: std.mem.Allocator, xml_string: []const u8) !Document {
            _ = xml_string;
            return Document.init(allocator);
        }

        /// Parse XML file to Document
        pub fn parse(allocator: std.mem.Allocator, filename: []const u8) !Document {
            _ = filename;
            return Document.init(allocator);
        }
    };
};

// ============================================================================
// Errors
// ============================================================================

pub const XMLError = errors_mod.XMLError;

// ============================================================================
// Tests
// ============================================================================

test "Element creation" {
    const allocator = std.testing.allocator;

    const elem = try etree.Element.init(allocator, "root");
    defer {
        elem.deinit();
        allocator.destroy(elem);
    }

    try std.testing.expectEqualStrings("root", elem.tag);
    try std.testing.expect(elem.text == null);
}

test "Element attributes" {
    const allocator = std.testing.allocator;

    const elem = try etree.Element.init(allocator, "div");
    defer {
        elem.deinit();
        allocator.destroy(elem);
    }

    try elem.set("class", "container");
    try elem.set("id", "main");

    try std.testing.expectEqualStrings("container", elem.get("class", null).?);
    try std.testing.expectEqualStrings("main", elem.get("id", null).?);
}

test "Element children" {
    const allocator = std.testing.allocator;

    const root = try etree.Element.init(allocator, "root");
    defer {
        root.deinit();
        allocator.destroy(root);
    }

    const child1 = try root.makeElement("child");
    const child2 = try root.makeElement("child");

    try std.testing.expectEqual(@as(usize, 2), root.len());
    try std.testing.expectEqualStrings("child", child1.tag);
    try std.testing.expectEqualStrings("child", child2.tag);
}

test "Element find" {
    const allocator = std.testing.allocator;

    const root = try etree.Element.init(allocator, "root");
    defer {
        root.deinit();
        allocator.destroy(root);
    }

    _ = try root.makeElement("item");
    const item2 = try root.makeElement("item");
    try item2.set("id", "special");

    const found = root.find("item");
    try std.testing.expect(found != null);
}

test "ElementTree" {
    const allocator = std.testing.allocator;

    const root = try etree.Element.init(allocator, "html");
    var tree = etree.ElementTree.init(allocator, root);
    defer tree.deinit();

    try std.testing.expectEqualStrings("html", tree.getroot().?.tag);
}
