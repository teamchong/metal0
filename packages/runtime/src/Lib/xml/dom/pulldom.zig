//! xml.dom.pulldom - Pull-style DOM builder
//! Reference: cpython/Lib/xml/dom/pulldom.py
//!
//! This module provides a pull-style event-based DOM builder.
//!
//! CPython __all__: ['parseString', 'parse', 'SAX2DOM', 'DOMEventStream',
//!                   'START_ELEMENT', 'END_ELEMENT', 'COMMENT', 'START_DOCUMENT',
//!                   'END_DOCUMENT', 'PROCESSING_INSTRUCTION', 'IGNORABLE_WHITESPACE',
//!                   'CHARACTERS', 'default_bufsize']

const std = @import("std");
const dom = @import("../dom.zig");
const minidom = @import("minidom.zig");

// ============================================================================
// Event Types
// ============================================================================

pub const START_ELEMENT = 1;
pub const END_ELEMENT = 2;
pub const COMMENT = 3;
pub const START_DOCUMENT = 4;
pub const END_DOCUMENT = 5;
pub const PROCESSING_INSTRUCTION = 6;
pub const IGNORABLE_WHITESPACE = 7;
pub const CHARACTERS = 8;

/// Default buffer size
pub const default_bufsize: usize = 16384;

// ============================================================================
// Event Types
// ============================================================================

/// DOM Event
pub const DOMEvent = struct {
    event_type: u8,
    node: ?*dom.Node,
};

// ============================================================================
// DOMEventStream
// ============================================================================

/// Pull-style DOM event stream
/// CPython: class DOMEventStream
pub const DOMEventStream = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    events: std.ArrayList(DOMEvent),
    current: usize,
    document: ?*dom.Document,
    expand_entity_refs: bool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .events = .{},
            .current = 0,
            .document = null,
            .expand_entity_refs = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit(self.allocator);
        if (self.document) |doc| {
            doc.deinit();
            self.allocator.destroy(doc);
        }
    }

    /// Get next event
    pub fn getEvent(self: *Self) ?DOMEvent {
        if (self.current < self.events.items.len) {
            const event = self.events.items[self.current];
            self.current += 1;
            return event;
        }
        return null;
    }

    /// Reset stream to beginning
    pub fn reset(self: *Self) void {
        self.current = 0;
    }

    /// Expand node (build full subtree)
    pub fn expandNode(self: *Self, node: *dom.Node) void {
        // In pull parsing, this would build the full subtree
        _ = self;
        _ = node;
    }
};

// ============================================================================
// SAX2DOM Handler
// ============================================================================

/// SAX2 to DOM converter
/// CPython: class SAX2DOM(xml.sax.ContentHandler)
pub const SAX2DOM = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    document: ?*dom.Document,
    cur_node: ?*dom.Node,
    pending_events: std.ArrayList(DOMEvent),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .document = null,
            .cur_node = null,
            .pending_events = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.pending_events.deinit(self.allocator);
    }

    /// Start document handler
    pub fn startDocument(self: *Self) !void {
        self.document = try self.allocator.create(dom.Document);
        self.document.?.* = dom.Document.init(self.allocator);
        try self.pending_events.append(self.allocator, .{
            .event_type = START_DOCUMENT,
            .node = null,
        });
    }

    /// End document handler
    pub fn endDocument(self: *Self) !void {
        try self.pending_events.append(self.allocator, .{
            .event_type = END_DOCUMENT,
            .node = null,
        });
    }

    /// Start element handler
    pub fn startElement(self: *Self, name: []const u8, attrs: anytype) !void {
        const doc = self.document orelse return;
        const node = try doc.createElement(name);

        // Copy attributes
        if (@TypeOf(attrs) != @TypeOf(null)) {
            var iter = attrs.iterator();
            while (iter.next()) |entry| {
                try node.setAttribute(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        if (self.cur_node) |parent| {
            _ = try parent.appendChild(node);
        } else {
            doc.document_element = node;
        }

        self.cur_node = node;
        try self.pending_events.append(self.allocator, .{
            .event_type = START_ELEMENT,
            .node = node,
        });
    }

    /// End element handler
    pub fn endElement(self: *Self, name: []const u8) !void {
        _ = name;
        if (self.cur_node) |node| {
            try self.pending_events.append(self.allocator, .{
                .event_type = END_ELEMENT,
                .node = node,
            });
            self.cur_node = node.parent_node;
        }
    }

    /// Characters handler
    pub fn characters(self: *Self, content: []const u8) !void {
        const doc = self.document orelse return;
        const text_node = try doc.createTextNode(content);

        if (self.cur_node) |parent| {
            _ = try parent.appendChild(text_node);
        }

        try self.pending_events.append(self.allocator, .{
            .event_type = CHARACTERS,
            .node = text_node,
        });
    }

    /// Processing instruction handler
    pub fn processingInstruction(self: *Self, target: []const u8, data: []const u8) !void {
        const doc = self.document orelse return;
        const pi_node = try doc.createProcessingInstruction(target, data);

        if (self.cur_node) |parent| {
            _ = try parent.appendChild(pi_node);
        }

        try self.pending_events.append(self.allocator, .{
            .event_type = PROCESSING_INSTRUCTION,
            .node = pi_node,
        });
    }

    /// Comment handler
    pub fn comment(self: *Self, content: []const u8) !void {
        const doc = self.document orelse return;
        const comment_node = try doc.createComment(content);

        if (self.cur_node) |parent| {
            _ = try parent.appendChild(comment_node);
        }

        try self.pending_events.append(self.allocator, .{
            .event_type = COMMENT,
            .node = comment_node,
        });
    }

    /// Get the built document
    pub fn getDocument(self: *Self) ?*dom.Document {
        return self.document;
    }
};

// ============================================================================
// Parsing Functions
// ============================================================================

/// Parse XML file with pull-style events
/// CPython: def parse(stream_or_string, parser=None, bufsize=None)
pub fn parse(allocator: std.mem.Allocator, filename: []const u8) !DOMEventStream {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    return parseString(allocator, content);
}

/// Parse XML string with pull-style events
/// CPython: def parseString(string, parser=None)
pub fn parseString(allocator: std.mem.Allocator, xml_string: []const u8) !DOMEventStream {
    var stream = DOMEventStream.init(allocator);
    errdefer stream.deinit();

    // Build document using minidom
    stream.document = try minidom.parseString(allocator, xml_string);

    // Generate events from document
    try stream.events.append(allocator, .{ .event_type = START_DOCUMENT, .node = null });

    if (stream.document.?.document_element) |root| {
        try generateEvents(allocator, &stream.events, root);
    }

    try stream.events.append(allocator, .{ .event_type = END_DOCUMENT, .node = null });

    return stream;
}

/// Generate events from DOM tree
fn generateEvents(allocator: std.mem.Allocator, events: *std.ArrayList(DOMEvent), node: *dom.Node) !void {
    try events.append(allocator, .{ .event_type = START_ELEMENT, .node = node });

    for (node.child_nodes.items) |child| {
        switch (child.node_type) {
            .ELEMENT_NODE => try generateEvents(allocator, events, child),
            .TEXT_NODE => try events.append(allocator, .{ .event_type = CHARACTERS, .node = child }),
            .COMMENT_NODE => try events.append(allocator, .{ .event_type = COMMENT, .node = child }),
            .PROCESSING_INSTRUCTION_NODE => try events.append(allocator, .{
                .event_type = PROCESSING_INSTRUCTION,
                .node = child,
            }),
            else => {},
        }
    }

    try events.append(allocator, .{ .event_type = END_ELEMENT, .node = node });
}

// ============================================================================
// Tests
// ============================================================================

test "DOMEventStream" {
    const allocator = std.testing.allocator;
    var stream = try parseString(allocator, "<root><child/></root>");
    defer stream.deinit();

    // Should have events
    var count: usize = 0;
    while (stream.getEvent()) |_| {
        count += 1;
    }
    try std.testing.expect(count > 0);
}

test "SAX2DOM" {
    const allocator = std.testing.allocator;
    var handler = SAX2DOM.init(allocator);
    defer handler.deinit();

    try handler.startDocument();
    try handler.startElement("root", null);
    try handler.characters("text");
    try handler.endElement("root");
    try handler.endDocument();

    const doc = handler.getDocument();
    try std.testing.expect(doc != null);
    defer {
        doc.?.deinit();
        allocator.destroy(doc.?);
    }
}
