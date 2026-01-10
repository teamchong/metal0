//! xml.sax.saxutils - SAX utility functions
//! Reference: cpython/Lib/xml/sax/saxutils.py
//!
//! CPython __all__: ['escape', 'unescape', 'quoteattr', 'XMLGenerator',
//!                   'XMLFilterBase', 'prepare_input_source']

const std = @import("std");
const sax = @import("../sax.zig");

// ============================================================================
// Escaping Functions
// ============================================================================

/// Escape special XML characters
/// CPython: def escape(data, entities={})
pub fn escape(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (data) |c| {
        switch (c) {
            '<' => try result.appendSlice(allocator, "&lt;"),
            '>' => try result.appendSlice(allocator, "&gt;"),
            '&' => try result.appendSlice(allocator, "&amp;"),
            else => try result.append(allocator, c),
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Unescape XML entities
/// CPython: def unescape(data, entities={})
pub fn unescape(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < data.len) {
        if (data[i] == '&') {
            if (std.mem.startsWith(u8, data[i..], "&lt;")) {
                try result.append(allocator, '<');
                i += 4;
            } else if (std.mem.startsWith(u8, data[i..], "&gt;")) {
                try result.append(allocator, '>');
                i += 4;
            } else if (std.mem.startsWith(u8, data[i..], "&amp;")) {
                try result.append(allocator, '&');
                i += 5;
            } else if (std.mem.startsWith(u8, data[i..], "&quot;")) {
                try result.append(allocator, '"');
                i += 6;
            } else if (std.mem.startsWith(u8, data[i..], "&apos;")) {
                try result.append(allocator, '\'');
                i += 6;
            } else if (data[i + 1] == '#') {
                // Numeric character reference
                const end = std.mem.indexOfScalarPos(u8, data, i, ';') orelse {
                    try result.append(allocator, data[i]);
                    i += 1;
                    continue;
                };
                const num_str = data[i + 2 .. end];
                const is_hex = num_str.len > 0 and (num_str[0] == 'x' or num_str[0] == 'X');
                const num = if (is_hex)
                    std.fmt.parseInt(u21, num_str[1..], 16) catch null
                else
                    std.fmt.parseInt(u21, num_str, 10) catch null;

                if (num) |code| {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(code, &buf) catch {
                        try result.append(allocator, data[i]);
                        i += 1;
                        continue;
                    };
                    try result.appendSlice(allocator, buf[0..len]);
                    i = end + 1;
                } else {
                    try result.append(allocator, data[i]);
                    i += 1;
                }
            } else {
                try result.append(allocator, data[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, data[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Quote an attribute value
/// CPython: def quoteattr(data, entities={})
pub fn quoteattr(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Determine quote character
    const has_single = std.mem.indexOf(u8, data, "'") != null;
    const has_double = std.mem.indexOf(u8, data, "\"") != null;

    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    if (has_double and !has_single) {
        try result.append(allocator, '\'');
        for (data) |c| {
            switch (c) {
                '<' => try result.appendSlice(allocator, "&lt;"),
                '>' => try result.appendSlice(allocator, "&gt;"),
                '&' => try result.appendSlice(allocator, "&amp;"),
                else => try result.append(allocator, c),
            }
        }
        try result.append(allocator, '\'');
    } else {
        try result.append(allocator, '"');
        for (data) |c| {
            switch (c) {
                '<' => try result.appendSlice(allocator, "&lt;"),
                '>' => try result.appendSlice(allocator, "&gt;"),
                '&' => try result.appendSlice(allocator, "&amp;"),
                '"' => try result.appendSlice(allocator, "&quot;"),
                else => try result.append(allocator, c),
            }
        }
        try result.append(allocator, '"');
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// XMLGenerator
// ============================================================================

/// XML generator - SAX handler that generates XML output
/// CPython: class XMLGenerator(ContentHandler)
pub const XMLGenerator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    encoding: []const u8,
    short_empty_elements: bool,
    in_element: bool,

    pub fn init(allocator: std.mem.Allocator, encoding: []const u8, short_empty_elements: bool) Self {
        return .{
            .allocator = allocator,
            .output = .{},
            .encoding = encoding,
            .short_empty_elements = short_empty_elements,
            .in_element = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
    }

    /// Get generated XML
    pub fn getvalue(self: *Self) []const u8 {
        return self.output.items;
    }

    /// Start document
    pub fn startDocument(self: *Self) !void {
        try self.output.appendSlice(self.allocator, "<?xml version=\"1.0\" encoding=\"");
        try self.output.appendSlice(self.allocator, self.encoding);
        try self.output.appendSlice(self.allocator, "\"?>\n");
    }

    /// End document
    pub fn endDocument(self: *Self) void {
        _ = self;
    }

    /// Start element
    pub fn startElement(self: *Self, name: []const u8, attrs: anytype) !void {
        try self.output.append(self.allocator, '<');
        try self.output.appendSlice(self.allocator, name);

        if (@TypeOf(attrs) != @TypeOf(null)) {
            var iter = attrs.iterator();
            while (iter.next()) |entry| {
                try self.output.append(self.allocator, ' ');
                try self.output.appendSlice(self.allocator, entry.key_ptr.*);
                try self.output.appendSlice(self.allocator, "=\"");
                const escaped = try escape(self.allocator, entry.value_ptr.*);
                defer self.allocator.free(escaped);
                try self.output.appendSlice(self.allocator, escaped);
                try self.output.append(self.allocator, '"');
            }
        }

        try self.output.append(self.allocator, '>');
        self.in_element = true;
    }

    /// End element
    pub fn endElement(self: *Self, name: []const u8) !void {
        try self.output.appendSlice(self.allocator, "</");
        try self.output.appendSlice(self.allocator, name);
        try self.output.append(self.allocator, '>');
        self.in_element = false;
    }

    /// Characters
    pub fn characters(self: *Self, content: []const u8) !void {
        const escaped = try escape(self.allocator, content);
        defer self.allocator.free(escaped);
        try self.output.appendSlice(self.allocator, escaped);
    }

    /// Processing instruction
    pub fn processingInstruction(self: *Self, target: []const u8, data: []const u8) !void {
        try self.output.appendSlice(self.allocator, "<?");
        try self.output.appendSlice(self.allocator, target);
        if (data.len > 0) {
            try self.output.append(self.allocator, ' ');
            try self.output.appendSlice(self.allocator, data);
        }
        try self.output.appendSlice(self.allocator, "?>");
    }

    /// Comment
    pub fn comment(self: *Self, content: []const u8) !void {
        try self.output.appendSlice(self.allocator, "<!--");
        try self.output.appendSlice(self.allocator, content);
        try self.output.appendSlice(self.allocator, "-->");
    }
};

// ============================================================================
// XMLFilterBase
// ============================================================================

/// XML filter base class
/// CPython: class XMLFilterBase(XMLReader)
pub const XMLFilterBase = struct {
    const Self = @This();

    parent: ?*sax.XMLReader,
    content_handler: ?sax.ContentHandler,
    error_handler: ?sax.ErrorHandler,

    pub fn init() Self {
        return .{
            .parent = null,
            .content_handler = null,
            .error_handler = null,
        };
    }

    pub fn setParent(self: *Self, parent: *sax.XMLReader) void {
        self.parent = parent;
    }

    pub fn getParent(self: *Self) ?*sax.XMLReader {
        return self.parent;
    }

    pub fn setContentHandler(self: *Self, handler: sax.ContentHandler) void {
        self.content_handler = handler;
    }

    pub fn setErrorHandler(self: *Self, handler: sax.ErrorHandler) void {
        self.error_handler = handler;
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Prepare input source
/// CPython: def prepare_input_source(source, base="")
pub fn prepare_input_source(source: anytype, base: []const u8) sax.InputSource {
    _ = base;
    var input = sax.InputSource.init();

    const T = @TypeOf(source);
    if (T == []const u8 or T == []u8) {
        input.system_id = source;
    }

    return input;
}

// ============================================================================
// Tests
// ============================================================================

test "escape" {
    const allocator = std.testing.allocator;
    const result = try escape(allocator, "<tag>&value</tag>");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("&lt;tag&gt;&amp;value&lt;/tag&gt;", result);
}

test "unescape" {
    const allocator = std.testing.allocator;
    const result = try unescape(allocator, "&lt;tag&gt;&amp;value&lt;/tag&gt;");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<tag>&value</tag>", result);
}

test "quoteattr" {
    const allocator = std.testing.allocator;
    const result = try quoteattr(allocator, "value");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\"value\"", result);
}

test "XMLGenerator" {
    const allocator = std.testing.allocator;
    var gen = XMLGenerator.init(allocator, "utf-8", false);
    defer gen.deinit();

    try gen.startDocument();
    try gen.startElement("root", null);
    try gen.characters("Hello");
    try gen.endElement("root");

    const output = gen.getvalue();
    try std.testing.expect(std.mem.indexOf(u8, output, "<root>Hello</root>") != null);
}
