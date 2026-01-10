//! xml.dom.xmlbuilder - DOM Level 3 Load/Save
//! Reference: cpython/Lib/xml/dom/xmlbuilder.py
//!
//! This module provides DOM Level 3 Load and Save interfaces.
//! Note: This is largely unimplemented in CPython as well.

const std = @import("std");
const dom = @import("../dom.zig");

// ============================================================================
// Options
// ============================================================================

/// Options class for DOM Load/Save
/// CPython: class Options
pub const Options = struct {
    const Self = @This();

    // Feature settings
    namespaces: bool = true,
    namespace_declarations: bool = true,
    validation: bool = false,
    external_general_entities: bool = true,
    external_parameter_entities: bool = true,
    validate_if_schema: bool = false,
    validate: bool = false,
    datatype_normalization: bool = false,
    normalize_characters: bool = false,
    check_character_normalization: bool = false,
    entities: bool = true,
    whitespace_in_element_content: bool = true,
    cdata_sections: bool = true,
    comments: bool = true,
    charset_overrides_xml_encoding: bool = true,
    infoset: bool = false,
    supported_mediatypes_only: bool = false,
};

// ============================================================================
// DOMImplementationLS
// ============================================================================

/// DOM Level 3 Load/Save implementation
/// CPython: class DOMImplementationLS
pub const DOMImplementationLS = struct {
    const Self = @This();

    /// Mode constants
    pub const MODE_SYNCHRONOUS: u16 = 1;
    pub const MODE_ASYNCHRONOUS: u16 = 2;

    /// Create LSParser
    pub fn createLSParser(self: *const Self, mode: u16, schema_type: ?[]const u8) LSParser {
        _ = self;
        _ = schema_type;
        return LSParser.init(mode);
    }

    /// Create LSSerializer
    pub fn createLSSerializer(self: *const Self) LSSerializer {
        _ = self;
        return LSSerializer.init();
    }

    /// Create LSInput
    pub fn createLSInput(self: *const Self) LSInput {
        _ = self;
        return LSInput.init();
    }

    /// Create LSOutput
    pub fn createLSOutput(self: *const Self) LSOutput {
        _ = self;
        return LSOutput.init();
    }
};

// ============================================================================
// LSParser
// ============================================================================

/// DOM Level 3 Load parser
/// CPython: class LSParser
pub const LSParser = struct {
    const Self = @This();

    mode: u16,
    dom_config: Options,

    pub fn init(mode: u16) Self {
        return .{
            .mode = mode,
            .dom_config = .{},
        };
    }

    /// Parse a document
    pub fn parse(self: *Self, allocator: std.mem.Allocator, input: LSInput) !*dom.Document {
        _ = self;
        const minidom = @import("minidom.zig");
        if (input.string_data) |data| {
            return minidom.parseString(allocator, data);
        }
        return error.NoInputData;
    }

    /// Parse URI
    pub fn parseURI(self: *Self, allocator: std.mem.Allocator, uri: []const u8) !*dom.Document {
        _ = self;
        const minidom = @import("minidom.zig");
        return minidom.parse(allocator, uri);
    }
};

// ============================================================================
// LSSerializer
// ============================================================================

/// DOM Level 3 Save serializer
/// CPython: class LSSerializer
pub const LSSerializer = struct {
    const Self = @This();

    dom_config: Options,
    new_line: []const u8,

    pub fn init() Self {
        return .{
            .dom_config = .{},
            .new_line = "\n",
        };
    }

    /// Write to string
    pub fn writeToString(self: *Self, allocator: std.mem.Allocator, node: *dom.Node) ![]u8 {
        _ = self;
        const minidom = @import("minidom.zig");
        return minidom.toxml(allocator, node);
    }

    /// Write to URI (file)
    pub fn writeToURI(self: *Self, node: *dom.Node, uri: []const u8) !bool {
        _ = self;
        const file = try std.fs.cwd().createFile(uri, .{});
        defer file.close();

        const allocator = std.heap.page_allocator;
        const minidom = @import("minidom.zig");
        const xml = try minidom.toxml(allocator, node);
        defer allocator.free(xml);

        try file.writeAll(xml);
        return true;
    }
};

// ============================================================================
// LSInput
// ============================================================================

/// DOM Level 3 Load input source
/// CPython: class LSInput
pub const LSInput = struct {
    const Self = @This();

    character_stream: ?*anyopaque,
    byte_stream: ?*anyopaque,
    string_data: ?[]const u8,
    system_id: ?[]const u8,
    public_id: ?[]const u8,
    base_uri: ?[]const u8,
    encoding: ?[]const u8,
    certified_text: bool,

    pub fn init() Self {
        return .{
            .character_stream = null,
            .byte_stream = null,
            .string_data = null,
            .system_id = null,
            .public_id = null,
            .base_uri = null,
            .encoding = null,
            .certified_text = false,
        };
    }
};

// ============================================================================
// LSOutput
// ============================================================================

/// DOM Level 3 Save output target
/// CPython: class LSOutput
pub const LSOutput = struct {
    const Self = @This();

    character_stream: ?*anyopaque,
    byte_stream: ?*anyopaque,
    system_id: ?[]const u8,
    encoding: ?[]const u8,

    pub fn init() Self {
        return .{
            .character_stream = null,
            .byte_stream = null,
            .system_id = null,
            .encoding = null,
        };
    }
};

// ============================================================================
// DocumentLS
// ============================================================================

/// Document with Load/Save extensions
/// CPython: class DocumentLS
pub const DocumentLS = struct {
    /// Async loading flag
    pub var async_loading: bool = false;

    /// Abort loading
    pub fn abort() void {
        // Not implemented
    }

    /// Load from URI
    pub fn load(allocator: std.mem.Allocator, uri: []const u8) !*dom.Document {
        const minidom = @import("minidom.zig");
        return minidom.parse(allocator, uri);
    }

    /// Load from XML string
    pub fn loadXML(allocator: std.mem.Allocator, source: []const u8) !*dom.Document {
        const minidom = @import("minidom.zig");
        return minidom.parseString(allocator, source);
    }

    /// Save to string
    pub fn saveXML(allocator: std.mem.Allocator, node: *dom.Node) ![]u8 {
        const minidom = @import("minidom.zig");
        return minidom.toxml(allocator, node);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LSInput" {
    const input = LSInput.init();
    try std.testing.expect(input.string_data == null);
}

test "LSSerializer" {
    const allocator = std.testing.allocator;
    var doc = dom.Document.init(allocator);
    defer doc.deinit();

    const elem = try doc.createElement("root");
    defer {
        elem.deinit();
        allocator.destroy(elem);
    }

    var serializer = LSSerializer.init();
    const xml = try serializer.writeToString(allocator, elem);
    defer allocator.free(xml);

    try std.testing.expect(std.mem.indexOf(u8, xml, "root") != null);
}
