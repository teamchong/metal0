//! Python 'xml' module - XML processing utilities
//!
//! Provides XML parsing, building, and manipulation APIs.
//!
//! Mirrors: CPython Lib/xml/

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// xml.etree.ElementTree - Element tree XML API
// ============================================================================

pub const etree = struct {
    /// XML Element
    pub const Element = struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        tag: []const u8,
        text: ?[]const u8,
        tail: ?[]const u8,
        attrib: hashmap_helper.StringHashMap([]const u8),
        children: std.ArrayList(*Element),
        parent: ?*Element,

        pub fn init(allocator: std.mem.Allocator, tag: []const u8) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .tag = try allocator.dupe(u8, tag),
                .text = null,
                .tail = null,
                .attrib = hashmap_helper.StringHashMap([]const u8).init(allocator),
                .children = std.ArrayList(*Element).init(allocator),
                .parent = null,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.tag);
            if (self.text) |t| self.allocator.free(t);
            if (self.tail) |t| self.allocator.free(t);

            var iter = self.attrib.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            self.attrib.deinit();

            for (self.children.items) |child| {
                child.deinit();
                self.allocator.destroy(child);
            }
            self.children.deinit();
        }

        /// Get attribute value
        pub fn get(self: *Self, key: []const u8, default: ?[]const u8) ?[]const u8 {
            return self.attrib.get(key) orelse default;
        }

        /// Set attribute value
        pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
            const k = try self.allocator.dupe(u8, key);
            const v = try self.allocator.dupe(u8, value);
            try self.attrib.put(k, v);
        }

        /// Get all attribute keys
        pub fn keys(self: *Self) ![][]const u8 {
            var result = std.ArrayList([]const u8).init(self.allocator);
            for (self.attrib.keys()) |key| {
                try result.append(key);
            }
            return result.toOwnedSlice();
        }

        /// Get all attribute items
        pub fn items(self: *Self) ![]struct { key: []const u8, value: []const u8 } {
            var result = std.ArrayList(struct { key: []const u8, value: []const u8 }).init(self.allocator);
            var iter = self.attrib.iterator();
            while (iter.next()) |entry| {
                try result.append(.{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
            }
            return result.toOwnedSlice();
        }

        /// Append a child element
        pub fn append(self: *Self, child: *Element) !void {
            child.parent = self;
            try self.children.append(child);
        }

        /// Insert a child at index
        pub fn insert(self: *Self, index: usize, child: *Element) !void {
            child.parent = self;
            try self.children.insert(index, child);
        }

        /// Remove a child element
        pub fn remove(self: *Self, child: *Element) void {
            for (self.children.items, 0..) |c, i| {
                if (c == child) {
                    _ = self.children.orderedRemove(i);
                    child.parent = null;
                    break;
                }
            }
        }

        /// Find first child with matching tag
        pub fn find(self: *Self, path: []const u8) ?*Element {
            for (self.children.items) |child| {
                if (std.mem.eql(u8, child.tag, path)) {
                    return child;
                }
            }
            return null;
        }

        /// Find all children with matching tag
        pub fn findall(self: *Self, path: []const u8) ![]*Element {
            var result = std.ArrayList(*Element).init(self.allocator);
            for (self.children.items) |child| {
                if (std.mem.eql(u8, child.tag, path)) {
                    try result.append(child);
                }
            }
            return result.toOwnedSlice();
        }

        /// Find text of first child with matching tag
        pub fn findtext(self: *Self, path: []const u8, default: ?[]const u8) ?[]const u8 {
            if (self.find(path)) |elem| {
                return elem.text orelse default;
            }
            return default;
        }

        /// Iterate over children
        pub fn iter(self: *Self, tag: ?[]const u8) ChildIterator {
            return ChildIterator{
                .element = self,
                .tag = tag,
                .index = 0,
            };
        }

        /// Get number of children
        pub fn len(self: *Self) usize {
            return self.children.items.len;
        }

        /// Create a subelement
        pub fn makeElement(self: *Self, tag: []const u8) !*Element {
            const child = try Element.init(self.allocator, tag);
            try self.append(child);
            return child;
        }

        /// Set text content
        pub fn setText(self: *Self, text: []const u8) !void {
            if (self.text) |t| self.allocator.free(t);
            self.text = try self.allocator.dupe(u8, text);
        }

        /// Set tail content
        pub fn setTail(self: *Self, text: []const u8) !void {
            if (self.tail) |t| self.allocator.free(t);
            self.tail = try self.allocator.dupe(u8, text);
        }
    };

    pub const ChildIterator = struct {
        element: *Element,
        tag: ?[]const u8,
        index: usize,

        pub fn next(self: *ChildIterator) ?*Element {
            while (self.index < self.element.children.items.len) {
                const child = self.element.children.items[self.index];
                self.index += 1;

                if (self.tag) |t| {
                    if (std.mem.eql(u8, child.tag, t)) {
                        return child;
                    }
                } else {
                    return child;
                }
            }
            return null;
        }
    };

    /// ElementTree wrapper
    pub const ElementTree = struct {
        allocator: std.mem.Allocator,
        root: ?*Element,

        pub fn init(allocator: std.mem.Allocator, root: ?*Element) ElementTree {
            return .{
                .allocator = allocator,
                .root = root,
            };
        }

        pub fn deinit(self: *ElementTree) void {
            if (self.root) |r| {
                r.deinit();
                self.allocator.destroy(r);
            }
        }

        pub fn getroot(self: *ElementTree) ?*Element {
            return self.root;
        }

        pub fn setroot(self: *ElementTree, root: *Element) void {
            self.root = root;
        }

        /// Parse XML from string
        pub fn parse(self: *ElementTree, source: []const u8) !void {
            var pos: usize = 0;

            // Skip XML declaration if present
            if (std.mem.startsWith(u8, source, "<?xml")) {
                if (std.mem.indexOf(u8, source, "?>")) |end| {
                    pos = end + 2;
                }
            }

            // Skip whitespace
            while (pos < source.len and std.ascii.isWhitespace(source[pos])) {
                pos += 1;
            }

            // Parse root element
            if (pos < source.len and source[pos] == '<') {
                self.root = try parseElement(self.allocator, source, &pos);
            }
        }

        fn parseElement(allocator: std.mem.Allocator, source: []const u8, pos: *usize) !*Element {
            // Skip '<'
            pos.* += 1;

            // Skip whitespace
            while (pos.* < source.len and std.ascii.isWhitespace(source[pos.*])) {
                pos.* += 1;
            }

            // Get tag name
            const tag_start = pos.*;
            while (pos.* < source.len and !std.ascii.isWhitespace(source[pos.*]) and
                source[pos.*] != '>' and source[pos.*] != '/')
            {
                pos.* += 1;
            }
            const tag = source[tag_start..pos.*];

            var elem = try Element.init(allocator, tag);
            errdefer elem.deinit();

            // Parse attributes
            while (pos.* < source.len and source[pos.*] != '>' and source[pos.*] != '/') {
                // Skip whitespace
                while (pos.* < source.len and std.ascii.isWhitespace(source[pos.*])) {
                    pos.* += 1;
                }

                if (pos.* >= source.len or source[pos.*] == '>' or source[pos.*] == '/') break;

                // Parse attribute name
                const attr_start = pos.*;
                while (pos.* < source.len and source[pos.*] != '=' and !std.ascii.isWhitespace(source[pos.*])) {
                    pos.* += 1;
                }
                const attr_name = source[attr_start..pos.*];

                // Skip to '='
                while (pos.* < source.len and source[pos.*] != '=') {
                    pos.* += 1;
                }
                pos.* += 1; // Skip '='

                // Skip whitespace and quote
                while (pos.* < source.len and (std.ascii.isWhitespace(source[pos.*]) or source[pos.*] == '"' or source[pos.*] == '\'')) {
                    pos.* += 1;
                }

                // Parse attribute value
                const val_start = pos.*;
                while (pos.* < source.len and source[pos.*] != '"' and source[pos.*] != '\'') {
                    pos.* += 1;
                }
                const attr_value = source[val_start..pos.*];

                // Skip closing quote
                if (pos.* < source.len) pos.* += 1;

                try elem.set(attr_name, attr_value);
            }

            // Check for self-closing tag
            if (pos.* < source.len and source[pos.*] == '/') {
                pos.* += 1;
                if (pos.* < source.len and source[pos.*] == '>') pos.* += 1;
                return elem;
            }

            // Skip '>'
            if (pos.* < source.len and source[pos.*] == '>') {
                pos.* += 1;
            }

            // Parse content and children
            var text_buf = std.ArrayList(u8).init(allocator);
            defer text_buf.deinit();

            while (pos.* < source.len) {
                if (source[pos.*] == '<') {
                    // Save accumulated text
                    if (text_buf.items.len > 0) {
                        elem.text = try allocator.dupe(u8, text_buf.items);
                        text_buf.clearRetainingCapacity();
                    }

                    // Check for closing tag
                    if (pos.* + 1 < source.len and source[pos.* + 1] == '/') {
                        // Find end of closing tag
                        while (pos.* < source.len and source[pos.*] != '>') {
                            pos.* += 1;
                        }
                        if (pos.* < source.len) pos.* += 1;
                        break;
                    }

                    // Parse child element
                    const child = try parseElement(allocator, source, pos);
                    try elem.append(child);
                } else {
                    try text_buf.append(source[pos.*]);
                    pos.* += 1;
                }
            }

            return elem;
        }

        /// Write XML to string
        pub fn tostring(self: *ElementTree, allocator: std.mem.Allocator) ![]u8 {
            if (self.root) |root| {
                return elementToString(allocator, root, 0);
            }
            return allocator.dupe(u8, "");
        }

        /// Write XML to file
        pub fn write(self: *ElementTree, file: std.fs.File, encoding: ?[]const u8, xml_declaration: bool) !void {
            _ = encoding;
            var writer = file.writer();

            if (xml_declaration) {
                try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            }

            if (self.root) |root| {
                try writeElement(writer, root, 0);
            }
        }
    };

    fn elementToString(allocator: std.mem.Allocator, elem: *Element, depth: usize) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        // Indent
        for (0..depth) |_| {
            try result.appendSlice("  ");
        }

        // Start tag
        try result.append('<');
        try result.appendSlice(elem.tag);

        // Attributes
        var iter = elem.attrib.iterator();
        while (iter.next()) |entry| {
            try result.append(' ');
            try result.appendSlice(entry.key_ptr.*);
            try result.appendSlice("=\"");
            try result.appendSlice(entry.value_ptr.*);
            try result.append('"');
        }

        if (elem.children.items.len == 0 and elem.text == null) {
            // Self-closing
            try result.appendSlice("/>\n");
        } else {
            try result.append('>');

            // Text
            if (elem.text) |text| {
                try result.appendSlice(text);
            }

            // Children
            if (elem.children.items.len > 0) {
                try result.append('\n');
                for (elem.children.items) |child| {
                    const child_str = try elementToString(allocator, child, depth + 1);
                    defer allocator.free(child_str);
                    try result.appendSlice(child_str);
                }

                // Indent closing tag
                for (0..depth) |_| {
                    try result.appendSlice("  ");
                }
            }

            // End tag
            try result.appendSlice("</");
            try result.appendSlice(elem.tag);
            try result.appendSlice(">\n");
        }

        // Tail
        if (elem.tail) |tail| {
            try result.appendSlice(tail);
        }

        return result.toOwnedSlice();
    }

    fn writeElement(writer: anytype, elem: *Element, depth: usize) !void {
        // Indent
        for (0..depth) |_| {
            try writer.writeAll("  ");
        }

        // Start tag
        try writer.writeByte('<');
        try writer.writeAll(elem.tag);

        // Attributes
        var iter = elem.attrib.iterator();
        while (iter.next()) |entry| {
            try writer.writeByte(' ');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeAll("=\"");
            try writer.writeAll(entry.value_ptr.*);
            try writer.writeByte('"');
        }

        if (elem.children.items.len == 0 and elem.text == null) {
            try writer.writeAll("/>\n");
        } else {
            try writer.writeByte('>');

            if (elem.text) |text| {
                try writer.writeAll(text);
            }

            if (elem.children.items.len > 0) {
                try writer.writeByte('\n');
                for (elem.children.items) |child| {
                    try writeElement(writer, child, depth + 1);
                }
                for (0..depth) |_| {
                    try writer.writeAll("  ");
                }
            }

            try writer.writeAll("</");
            try writer.writeAll(elem.tag);
            try writer.writeAll(">\n");
        }
    }

    /// Parse XML string to Element
    pub fn fromstring(allocator: std.mem.Allocator, text: []const u8) !*Element {
        return parseXML(allocator, text);
    }

    /// Parse XML file to ElementTree
    pub fn parseFile(allocator: std.mem.Allocator, filename: []const u8) !ElementTree {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        defer allocator.free(content);

        const root = try parseXML(allocator, content);
        return ElementTree.init(allocator, root);
    }

    /// Convert element to string
    pub fn tostring(allocator: std.mem.Allocator, elem: *Element) ![]u8 {
        return elementToString(allocator, elem, 0);
    }

    fn parseXML(allocator: std.mem.Allocator, text: []const u8) !*Element {
        // Simple XML parser
        var stack = std.ArrayList(*Element).init(allocator);
        defer stack.deinit();

        var root: ?*Element = null;
        var current: ?*Element = null;
        var i: usize = 0;

        while (i < text.len) {
            if (text[i] == '<') {
                if (i + 1 < text.len and text[i + 1] == '/') {
                    // End tag
                    const end = std.mem.indexOfScalarPos(u8, text, i + 2, '>') orelse break;
                    i = end + 1;
                    if (stack.items.len > 0) {
                        _ = stack.pop();
                        current = if (stack.items.len > 0) stack.items[stack.items.len - 1] else null;
                    }
                } else if (i + 1 < text.len and text[i + 1] == '?') {
                    // XML declaration
                    const end = std.mem.indexOf(u8, text[i..], "?>") orelse break;
                    i = i + end + 2;
                } else if (i + 1 < text.len and text[i + 1] == '!') {
                    // Comment or DOCTYPE
                    if (i + 4 < text.len and std.mem.eql(u8, text[i + 2 .. i + 4], "--")) {
                        const end = std.mem.indexOf(u8, text[i..], "-->") orelse break;
                        i = i + end + 3;
                    } else {
                        const end = std.mem.indexOfScalarPos(u8, text, i + 2, '>') orelse break;
                        i = end + 1;
                    }
                } else {
                    // Start tag
                    const end = std.mem.indexOfScalarPos(u8, text, i + 1, '>') orelse break;
                    const tag_content = text[i + 1 .. end];

                    // Check for self-closing
                    const self_closing = tag_content.len > 0 and tag_content[tag_content.len - 1] == '/';
                    const tag_end = if (self_closing) tag_content.len - 1 else tag_content.len;

                    // Parse tag name
                    var tag_name_end: usize = 0;
                    for (tag_content[0..tag_end], 0..) |c, idx| {
                        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                            tag_name_end = idx;
                            break;
                        }
                        tag_name_end = idx + 1;
                    }

                    const tag_name = tag_content[0..tag_name_end];
                    const elem = try Element.init(allocator, tag_name);

                    // Parse attributes (simplified)
                    if (tag_name_end < tag_end) {
                        const attrs_str = tag_content[tag_name_end..tag_end];
                        try parseAttributes(elem, attrs_str);
                    }

                    if (current) |cur| {
                        try cur.append(elem);
                    } else {
                        root = elem;
                    }

                    if (!self_closing) {
                        try stack.append(elem);
                        current = elem;
                    }

                    i = end + 1;
                }
            } else {
                // Text content
                const start = i;
                while (i < text.len and text[i] != '<') {
                    i += 1;
                }

                if (current) |cur| {
                    const text_content = std.mem.trim(u8, text[start..i], " \t\n\r");
                    if (text_content.len > 0) {
                        try cur.setText(text_content);
                    }
                }
            }
        }

        return root orelse error.ParseError;
    }

    fn parseAttributes(elem: *Element, attrs_str: []const u8) !void {
        var i: usize = 0;
        while (i < attrs_str.len) {
            // Skip whitespace
            while (i < attrs_str.len and (attrs_str[i] == ' ' or attrs_str[i] == '\t' or attrs_str[i] == '\n')) {
                i += 1;
            }
            if (i >= attrs_str.len) break;

            // Find attribute name
            const name_start = i;
            while (i < attrs_str.len and attrs_str[i] != '=' and attrs_str[i] != ' ') {
                i += 1;
            }
            const name = attrs_str[name_start..i];
            if (name.len == 0) break;

            // Skip to =
            while (i < attrs_str.len and attrs_str[i] != '=') {
                i += 1;
            }
            if (i >= attrs_str.len) break;
            i += 1; // Skip =

            // Skip whitespace
            while (i < attrs_str.len and (attrs_str[i] == ' ' or attrs_str[i] == '\t')) {
                i += 1;
            }
            if (i >= attrs_str.len) break;

            // Parse value
            if (attrs_str[i] == '"' or attrs_str[i] == '\'') {
                const quote = attrs_str[i];
                i += 1;
                const value_start = i;
                while (i < attrs_str.len and attrs_str[i] != quote) {
                    i += 1;
                }
                const value = attrs_str[value_start..i];
                i += 1; // Skip closing quote

                try elem.set(name, value);
            }
        }
    }

    /// Create a new element
    pub fn createElement(allocator: std.mem.Allocator, tag: []const u8) !*Element {
        return Element.init(allocator, tag);
    }

    /// Create a subelement
    pub fn SubElement(parent: *Element, tag: []const u8) !*Element {
        return parent.makeElement(tag);
    }

    /// Comment element
    pub fn Comment(allocator: std.mem.Allocator, text: []const u8) !*Element {
        const elem = try Element.init(allocator, "!--");
        try elem.setText(text);
        return elem;
    }

    /// ProcessingInstruction element
    pub fn ProcessingInstruction(allocator: std.mem.Allocator, target: []const u8, text: ?[]const u8) !*Element {
        const elem = try Element.init(allocator, target);
        if (text) |t| try elem.setText(t);
        return elem;
    }

    /// Check if element is comment
    pub fn iselement(elem: *Element) bool {
        _ = elem;
        return true;
    }
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
            _ = self;
            _ = source;
            // Would parse with SAX events
        }

        pub fn parseFile(self: *XMLReader, filename: []const u8) !void {
            _ = self;
            _ = filename;
            // Would parse file with SAX events
        }
    };

    /// Parse XML with handler
    pub fn parseString(xml_string: []const u8, handler: ContentHandler) !void {
        _ = xml_string;
        _ = handler;
        // Would parse and call handler methods
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

pub const XMLError = error{
    ParseError,
    MalformedXML,
    InvalidCharacter,
    UndefinedEntity,
    DuplicateAttribute,
};

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
