//! xml.sax - SAX2 XML parsing API
//! Reference: cpython/Lib/xml/sax/__init__.py
//!
//! This package provides the SAX2 API for XML parsing.
//!
//! CPython __all__: ['ContentHandler', 'ErrorHandler', 'EntityResolver',
//!                   'DTDHandler', 'SAXException', 'SAXNotRecognizedException',
//!                   'SAXNotSupportedException', 'SAXParseException',
//!                   'SAXReaderNotAvailable', 'make_parser', 'parse',
//!                   'parseString', 'default_parser_list']

const std = @import("std");
const xml_parser = @import("parser.zig");

// ============================================================================
// Exceptions
// ============================================================================

/// Base SAX exception
/// CPython: class SAXException(Exception)
pub const SAXException = error{
    SAXException,
    SAXParseException,
    SAXNotRecognizedException,
    SAXNotSupportedException,
    SAXReaderNotAvailable,
};

/// Parse exception with location info
pub const SAXParseException = struct {
    message: []const u8,
    line_number: ?usize,
    column_number: ?usize,
    public_id: ?[]const u8,
    system_id: ?[]const u8,

    pub fn init(message: []const u8) SAXParseException {
        return .{
            .message = message,
            .line_number = null,
            .column_number = null,
            .public_id = null,
            .system_id = null,
        };
    }
};

// ============================================================================
// Handler Interfaces
// ============================================================================

/// Content handler for SAX events
/// CPython: class ContentHandler
pub const ContentHandler = struct {
    const Self = @This();

    // Callback function pointers
    startDocument: ?*const fn (*Self) void = null,
    endDocument: ?*const fn (*Self) void = null,
    startPrefixMapping: ?*const fn (*Self, []const u8, []const u8) void = null,
    endPrefixMapping: ?*const fn (*Self, []const u8) void = null,
    startElement: ?*const fn (*Self, []const u8, []const u8, []const u8, anytype) void = null,
    endElement: ?*const fn (*Self, []const u8, []const u8, []const u8) void = null,
    characters: ?*const fn (*Self, []const u8) void = null,
    ignorableWhitespace: ?*const fn (*Self, []const u8) void = null,
    processingInstruction: ?*const fn (*Self, []const u8, []const u8) void = null,
    skippedEntity: ?*const fn (*Self, []const u8) void = null,

    // User data
    user_data: ?*anyopaque = null,

    /// Set document locator
    pub fn setDocumentLocator(self: *Self, locator: *Locator) void {
        _ = self;
        _ = locator;
    }
};

/// Error handler for SAX events
/// CPython: class ErrorHandler
pub const ErrorHandler = struct {
    const Self = @This();

    error_fn: ?*const fn (*Self, SAXParseException) void = null,
    fatalError: ?*const fn (*Self, SAXParseException) void = null,
    warning: ?*const fn (*Self, SAXParseException) void = null,
};

/// Entity resolver
/// CPython: class EntityResolver
pub const EntityResolver = struct {
    const Self = @This();

    /// Resolve entity
    pub fn resolveEntity(self: *Self, public_id: ?[]const u8, system_id: []const u8) ?InputSource {
        _ = self;
        _ = public_id;
        _ = system_id;
        return null;
    }
};

/// DTD handler
/// CPython: class DTDHandler
pub const DTDHandler = struct {
    const Self = @This();

    notationDecl: ?*const fn (*Self, []const u8, ?[]const u8, ?[]const u8) void = null,
    unparsedEntityDecl: ?*const fn (*Self, []const u8, ?[]const u8, []const u8, []const u8) void = null,
};

// ============================================================================
// Locator Interface
// ============================================================================

/// Document locator for tracking position
/// CPython: class Locator
pub const Locator = struct {
    const Self = @This();

    line_number: usize = 1,
    column_number: usize = 1,
    public_id: ?[]const u8 = null,
    system_id: ?[]const u8 = null,

    pub fn getLineNumber(self: *const Self) usize {
        return self.line_number;
    }

    pub fn getColumnNumber(self: *const Self) usize {
        return self.column_number;
    }

    pub fn getPublicId(self: *const Self) ?[]const u8 {
        return self.public_id;
    }

    pub fn getSystemId(self: *const Self) ?[]const u8 {
        return self.system_id;
    }
};

// ============================================================================
// InputSource
// ============================================================================

/// Input source for SAX parser
/// CPython: class InputSource
pub const InputSource = struct {
    const Self = @This();

    public_id: ?[]const u8 = null,
    system_id: ?[]const u8 = null,
    encoding: ?[]const u8 = null,
    byte_stream: ?*anyopaque = null,
    character_stream: ?*anyopaque = null,

    pub fn init() Self {
        return .{};
    }

    pub fn setPublicId(self: *Self, public_id: []const u8) void {
        self.public_id = public_id;
    }

    pub fn setSystemId(self: *Self, system_id: []const u8) void {
        self.system_id = system_id;
    }

    pub fn setEncoding(self: *Self, encoding: []const u8) void {
        self.encoding = encoding;
    }

    pub fn setByteStream(self: *Self, stream: *anyopaque) void {
        self.byte_stream = stream;
    }

    pub fn setCharacterStream(self: *Self, stream: *anyopaque) void {
        self.character_stream = stream;
    }
};

// ============================================================================
// XMLReader Interface
// ============================================================================

/// SAX XMLReader interface
/// CPython: class XMLReader
pub const XMLReader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    content_handler: ?ContentHandler = null,
    error_handler: ?ErrorHandler = null,
    dtd_handler: ?DTDHandler = null,
    entity_resolver: ?EntityResolver = null,
    locator: Locator = .{},

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn setContentHandler(self: *Self, handler: ContentHandler) void {
        self.content_handler = handler;
    }

    pub fn getContentHandler(self: *Self) ?ContentHandler {
        return self.content_handler;
    }

    pub fn setErrorHandler(self: *Self, handler: ErrorHandler) void {
        self.error_handler = handler;
    }

    pub fn getErrorHandler(self: *Self) ?ErrorHandler {
        return self.error_handler;
    }

    pub fn setDTDHandler(self: *Self, handler: DTDHandler) void {
        self.dtd_handler = handler;
    }

    pub fn getDTDHandler(self: *Self) ?DTDHandler {
        return self.dtd_handler;
    }

    pub fn setEntityResolver(self: *Self, resolver: EntityResolver) void {
        self.entity_resolver = resolver;
    }

    pub fn getEntityResolver(self: *Self) ?EntityResolver {
        return self.entity_resolver;
    }

    /// Parse from source
    pub fn parse(self: *Self, source: []const u8) !void {
        if (self.content_handler) |*handler| {
            if (handler.startDocument) |f| f(handler);
        }

        // Simple event-driven parsing
        var pos: usize = 0;
        while (pos < source.len) {
            if (source[pos] == '<') {
                if (pos + 1 < source.len and source[pos + 1] == '/') {
                    // End tag
                    const tag_start = pos + 2;
                    const tag_end = std.mem.indexOfScalarPos(u8, source, tag_start, '>') orelse break;
                    const tag_name = source[tag_start..tag_end];
                    if (self.content_handler) |*handler| {
                        if (handler.endElement) |f| f(handler, "", tag_name, tag_name);
                    }
                    pos = tag_end + 1;
                } else if (pos + 1 < source.len and source[pos + 1] == '?') {
                    // Processing instruction
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
                        if (self.content_handler) |*handler| {
                            if (handler.characters) |f| f(handler, cdata_content);
                        }
                        pos = pos + cdata_end + 3;
                    } else {
                        pos += 1;
                    }
                } else {
                    // Start tag
                    const tag_end = std.mem.indexOfAny(u8, source[pos + 1 ..], " \t\n/>") orelse break;
                    const tag_name = source[pos + 1 .. pos + 1 + tag_end];

                    const close = std.mem.indexOfScalarPos(u8, source, pos, '>') orelse break;
                    const is_self_closing = close > 0 and source[close - 1] == '/';

                    if (self.content_handler) |*handler| {
                        if (handler.startElement) |f| f(handler, "", tag_name, tag_name, null);
                        if (is_self_closing) {
                            if (handler.endElement) |ef| ef(handler, "", tag_name, tag_name);
                        }
                    }
                    pos = close + 1;
                }
            } else {
                // Text content
                const text_end = std.mem.indexOfScalarPos(u8, source, pos, '<') orelse source.len;
                const text = std.mem.trim(u8, source[pos..text_end], " \t\n\r");
                if (text.len > 0) {
                    if (self.content_handler) |*handler| {
                        if (handler.characters) |f| f(handler, text);
                    }
                }
                pos = text_end;
            }
        }

        if (self.content_handler) |*handler| {
            if (handler.endDocument) |f| f(handler);
        }
    }

    /// Parse from file
    pub fn parseFile(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        try self.parse(content);
    }
};

// ============================================================================
// Factory Functions
// ============================================================================

/// Default parser list
pub const default_parser_list = [_][]const u8{
    "xml.sax.expatreader",
};

/// Create a SAX parser
/// CPython: def make_parser(parser_list=[])
pub fn make_parser(allocator: std.mem.Allocator) XMLReader {
    return XMLReader.init(allocator);
}

/// Parse XML file with handler
/// CPython: def parse(source, handler, errorHandler=None)
pub fn parseXmlFile(allocator: std.mem.Allocator, filename: []const u8, handler: ContentHandler) !void {
    var reader = make_parser(allocator);
    reader.setContentHandler(handler);
    try reader.parseFile(filename);
}

/// Parse XML string with handler
/// CPython: def parseString(string, handler, errorHandler=None)
pub fn parseString(allocator: std.mem.Allocator, xml_string: []const u8, handler: ContentHandler) !void {
    var reader = make_parser(allocator);
    reader.setContentHandler(handler);
    try reader.parse(xml_string);
}

// ============================================================================
// Tests
// ============================================================================

test "XMLReader" {
    const allocator = std.testing.allocator;
    var reader = make_parser(allocator);

    try reader.parse("<root><child/></root>");
}

test "ContentHandler" {
    var handler = ContentHandler{};
    handler.setDocumentLocator(&Locator{});
}

test "Locator" {
    var loc = Locator{};
    loc.line_number = 5;
    try std.testing.expectEqual(@as(usize, 5), loc.getLineNumber());
}
