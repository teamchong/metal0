//! xml.etree.ElementTree - ElementTree XML API
//! Reference: cpython/Lib/xml/etree/ElementTree.py
//!
//! CPython __all__: ['Comment', 'dump', 'Element', 'ElementTree', 'fromstring',
//!                   'fromstringlist', 'indent', 'iselement', 'iterparse',
//!                   'parse', 'ParseError', 'PI', 'ProcessingInstruction',
//!                   'QName', 'SubElement', 'tostring', 'tostringlist',
//!                   'TreeBuilder', 'VERSION', 'XML', 'XMLID', 'XMLParser',
//!                   'XMLPullParser', 'register_namespace', 'canonicalize',
//!                   'C14NWriterTarget']

const std = @import("std");
const etree = @import("../etree.zig");
const element_mod = @import("../element.zig");
const tree_mod = @import("../tree.zig");
const builder_mod = @import("../builder.zig");
const parser_mod = @import("../parser.zig");

// ============================================================================
// Re-exports from parent modules (DRY)
// ============================================================================

pub const Element = element_mod.Element;
pub const ChildIterator = element_mod.ChildIterator;
pub const ElementTree = tree_mod.ElementTree;
pub const fromstring = builder_mod.fromstring;
pub const tostring = builder_mod.tostring;
pub const SubElement = builder_mod.SubElement;
pub const Comment = builder_mod.Comment;
pub const ProcessingInstruction = builder_mod.ProcessingInstruction;
pub const PI = ProcessingInstruction;
pub const iselement = builder_mod.iselement;
pub const parse = tree_mod.parseFile;

// Re-export from etree
pub const fromstringlist = etree.fromstringlist;
pub const tostringlist = etree.tostringlist;
pub const indent = etree.indent;
pub const register_namespace = etree.register_namespace;
pub const canonicalize = etree.canonicalize;
pub const XML = fromstring;
pub const XMLID = fromstring;

// ============================================================================
// Constants
// ============================================================================

/// ElementTree version
pub const VERSION = "1.3.0";

// ============================================================================
// ParseError
// ============================================================================

/// Parse error exception
/// CPython: class ParseError(SyntaxError)
pub const ParseError = error{
    ParseError,
    MalformedXML,
    InvalidCharacter,
};

// ============================================================================
// QName
// ============================================================================

/// Qualified XML name
/// CPython: class QName
pub const QName = struct {
    text: []const u8,
    tag: []const u8,

    pub fn init(text: []const u8, tag: ?[]const u8) QName {
        return .{
            .text = text,
            .tag = tag orelse text,
        };
    }

    pub fn format(self: *const QName, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.text);
    }
};

// ============================================================================
// TreeBuilder
// ============================================================================

/// Tree builder for constructing element trees
/// CPython: class TreeBuilder
pub const TreeBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    element_factory: ?*const fn (std.mem.Allocator, []const u8) anyerror!*Element,
    stack: std.ArrayList(*Element),
    last: ?*Element,
    root: ?*Element,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .element_factory = null,
            .stack = .{},
            .last = null,
            .root = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
    }

    /// Start a new element
    pub fn start(self: *Self, tag: []const u8, attrs: ?std.StringHashMap([]const u8)) !*Element {
        const elem = try Element.init(self.allocator, tag);

        if (attrs) |a| {
            var iter = a.iterator();
            while (iter.next()) |entry| {
                try elem.set(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        if (self.stack.items.len > 0) {
            const parent = self.stack.items[self.stack.items.len - 1];
            try parent.append(elem);
        } else {
            self.root = elem;
        }

        try self.stack.append(self.allocator, elem);
        self.last = elem;
        return elem;
    }

    /// End an element
    pub fn end(self: *Self, tag: []const u8) *Element {
        _ = tag;
        self.last = self.stack.pop();
        return self.last.?;
    }

    /// Add text data
    pub fn data(self: *Self, text: []const u8) !void {
        if (self.last) |last| {
            try last.setText(text);
        }
    }

    /// Close and return the root element
    pub fn close(self: *Self) ?*Element {
        return self.root;
    }
};

// ============================================================================
// XMLParser
// ============================================================================

/// XML Parser using expat-style callbacks
/// CPython: class XMLParser
pub const XMLParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    target: TreeBuilder,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .target = TreeBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.target.deinit();
    }

    /// Feed XML data to the parser
    pub fn feed(self: *Self, data: []const u8) !void {
        // Parse and build tree
        const root = try parser_mod.parseXML(self.allocator, data);
        self.target.root = root;
    }

    /// Close parser and return root element
    pub fn close(self: *Self) ?*Element {
        return self.target.close();
    }
};

// ============================================================================
// XMLPullParser
// ============================================================================

/// Pull-style XML parser
/// CPython: class XMLPullParser
pub const XMLPullParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),
    parser: XMLParser,

    pub const Event = struct {
        event_type: EventType,
        element: ?*Element,
    };

    pub const EventType = enum {
        start,
        end,
        start_ns,
        end_ns,
        comment,
        pi,
    };

    pub fn init(allocator: std.mem.Allocator, events: ?[]const EventType) Self {
        _ = events;
        return .{
            .allocator = allocator,
            .events = .{},
            .parser = XMLParser.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit(self.allocator);
        self.parser.deinit();
    }

    /// Feed data to parser
    pub fn feed(self: *Self, data: []const u8) !void {
        try self.parser.feed(data);
    }

    /// Close and return events
    pub fn close(self: *Self) ?*Element {
        return self.parser.close();
    }

    /// Read events (iterator-style)
    pub fn readEvents(self: *Self) []Event {
        return self.events.items;
    }
};

// ============================================================================
// iterparse
// ============================================================================

/// Incrementally parse XML file
/// CPython: def iterparse(source, events=None, parser=None)
pub fn iterparse(allocator: std.mem.Allocator, source: []const u8, events: ?[]const XMLPullParser.EventType) !XMLPullParser {
    var pull_parser = XMLPullParser.init(allocator, events);
    try pull_parser.feed(source);
    return pull_parser;
}

// ============================================================================
// dump
// ============================================================================

/// Write element tree to stdout
/// CPython: def dump(elem)
pub fn dump(elem: *Element) void {
    const stdout = std.io.getStdOut().writer();
    writeElementDebug(stdout, elem, 0) catch {};
}

fn writeElementDebug(writer: anytype, elem: *Element, depth: usize) !void {
    for (0..depth) |_| try writer.writeAll("  ");
    try writer.print("<{s}", .{elem.tag});

    var iter = elem.attrib.iterator();
    while (iter.next()) |entry| {
        try writer.print(" {s}=\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    if (elem.children.items.len == 0 and elem.text == null) {
        try writer.writeAll("/>\n");
    } else {
        try writer.writeAll(">");
        if (elem.text) |text| try writer.writeAll(text);
        if (elem.children.items.len > 0) {
            try writer.writeAll("\n");
            for (elem.children.items) |child| {
                try writeElementDebug(writer, child, depth + 1);
            }
            for (0..depth) |_| try writer.writeAll("  ");
        }
        try writer.print("</{s}>\n", .{elem.tag});
    }
}

// ============================================================================
// C14NWriterTarget
// ============================================================================

/// Target for C14N (Canonical XML) output
/// CPython: class C14NWriterTarget
pub const C14NWriterTarget = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn getvalue(self: *Self) []const u8 {
        return self.buffer.items;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "QName" {
    const qn = QName.init("{http://example.com}tag", null);
    try std.testing.expectEqualStrings("{http://example.com}tag", qn.text);
}

test "TreeBuilder" {
    const allocator = std.testing.allocator;
    var builder = TreeBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.start("root", null);
    _ = try builder.start("child", null);
    _ = builder.end("child");
    _ = builder.end("root");

    const root = builder.close();
    try std.testing.expect(root != null);
    defer {
        root.?.deinit();
        allocator.destroy(root.?);
    }
    try std.testing.expectEqualStrings("root", root.?.tag);
}
