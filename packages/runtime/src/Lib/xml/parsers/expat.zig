//! xml.parsers.expat - Expat XML parser bindings
//! Reference: cpython/Lib/xml/parsers/expat.py
//!
//! This module provides the Python interface to the Expat XML parser.
//! In the Zig/AOT implementation, we provide a pure Zig parser.

const std = @import("std");
const parser_mod = @import("../parser.zig");

// ============================================================================
// Constants
// ============================================================================

/// Expat version
pub const version_info = .{ 2, 5, 0 };
pub const EXPAT_VERSION = "expat_2.5.0";

/// XML parser error codes
pub const errors = struct {
    pub const XML_ERROR_NONE: i32 = 0;
    pub const XML_ERROR_NO_MEMORY: i32 = 1;
    pub const XML_ERROR_SYNTAX: i32 = 2;
    pub const XML_ERROR_NO_ELEMENTS: i32 = 3;
    pub const XML_ERROR_INVALID_TOKEN: i32 = 4;
    pub const XML_ERROR_UNCLOSED_TOKEN: i32 = 5;
    pub const XML_ERROR_PARTIAL_CHAR: i32 = 6;
    pub const XML_ERROR_TAG_MISMATCH: i32 = 7;
    pub const XML_ERROR_DUPLICATE_ATTRIBUTE: i32 = 8;
    pub const XML_ERROR_JUNK_AFTER_DOC_ELEMENT: i32 = 9;
    pub const XML_ERROR_PARAM_ENTITY_REF: i32 = 10;
    pub const XML_ERROR_UNDEFINED_ENTITY: i32 = 11;
    pub const XML_ERROR_RECURSIVE_ENTITY_REF: i32 = 12;
    pub const XML_ERROR_ASYNC_ENTITY: i32 = 13;
    pub const XML_ERROR_BAD_CHAR_REF: i32 = 14;
    pub const XML_ERROR_BINARY_ENTITY_REF: i32 = 15;
    pub const XML_ERROR_ATTRIBUTE_EXTERNAL_ENTITY_REF: i32 = 16;
    pub const XML_ERROR_MISPLACED_XML_PI: i32 = 17;
    pub const XML_ERROR_UNKNOWN_ENCODING: i32 = 18;
    pub const XML_ERROR_INCORRECT_ENCODING: i32 = 19;
    pub const XML_ERROR_UNCLOSED_CDATA_SECTION: i32 = 20;
    pub const XML_ERROR_EXTERNAL_ENTITY_HANDLING: i32 = 21;
    pub const XML_ERROR_NOT_STANDALONE: i32 = 22;
    pub const XML_ERROR_UNEXPECTED_STATE: i32 = 23;
    pub const XML_ERROR_ENTITY_DECLARED_IN_PE: i32 = 24;
    pub const XML_ERROR_FEATURE_REQUIRES_XML_DTD: i32 = 25;
    pub const XML_ERROR_CANT_CHANGE_FEATURE_ONCE_PARSING: i32 = 26;
    pub const XML_ERROR_UNBOUND_PREFIX: i32 = 27;
    pub const XML_ERROR_UNDECLARING_PREFIX: i32 = 28;
    pub const XML_ERROR_INCOMPLETE_PE: i32 = 29;
    pub const XML_ERROR_XML_DECL: i32 = 30;
    pub const XML_ERROR_TEXT_DECL: i32 = 31;
    pub const XML_ERROR_PUBLICID: i32 = 32;
    pub const XML_ERROR_SUSPENDED: i32 = 33;
    pub const XML_ERROR_NOT_SUSPENDED: i32 = 34;
    pub const XML_ERROR_ABORTED: i32 = 35;
    pub const XML_ERROR_FINISHED: i32 = 36;
    pub const XML_ERROR_SUSPEND_PE: i32 = 37;
    pub const XML_ERROR_RESERVED_PREFIX_XML: i32 = 38;
    pub const XML_ERROR_RESERVED_PREFIX_XMLNS: i32 = 39;
    pub const XML_ERROR_RESERVED_NAMESPACE_URI: i32 = 40;
};

/// Model constants
pub const model = struct {
    pub const XML_CTYPE_EMPTY: i32 = 1;
    pub const XML_CTYPE_ANY: i32 = 2;
    pub const XML_CTYPE_MIXED: i32 = 3;
    pub const XML_CTYPE_NAME: i32 = 4;
    pub const XML_CTYPE_CHOICE: i32 = 5;
    pub const XML_CTYPE_SEQ: i32 = 6;

    pub const XML_CQUANT_NONE: i32 = 0;
    pub const XML_CQUANT_OPT: i32 = 1;
    pub const XML_CQUANT_REP: i32 = 2;
    pub const XML_CQUANT_PLUS: i32 = 3;
};

// ============================================================================
// ExpatError
// ============================================================================

/// Expat error exception
/// CPython: ExpatError
pub const ExpatError = struct {
    code: i32,
    message: []const u8,
    lineno: usize,
    offset: usize,

    pub fn init(code: i32, message: []const u8) ExpatError {
        return .{
            .code = code,
            .message = message,
            .lineno = 0,
            .offset = 0,
        };
    }
};

/// Error alias
pub const error_type = ExpatError;

// ============================================================================
// XMLParserType
// ============================================================================

/// Expat XML parser
/// CPython: xmlparser
pub const XMLParserType = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    encoding: ?[]const u8,
    namespace_separator: ?u8,
    buffer: std.ArrayList(u8),
    error_code: i32,
    error_lineno: usize,
    error_offset: usize,

    // Handlers
    StartElementHandler: ?*const fn ([]const u8, anytype) void = null,
    EndElementHandler: ?*const fn ([]const u8) void = null,
    CharacterDataHandler: ?*const fn ([]const u8) void = null,
    ProcessingInstructionHandler: ?*const fn ([]const u8, []const u8) void = null,
    CommentHandler: ?*const fn ([]const u8) void = null,
    StartCdataSectionHandler: ?*const fn () void = null,
    EndCdataSectionHandler: ?*const fn () void = null,
    DefaultHandler: ?*const fn ([]const u8) void = null,
    DefaultHandlerExpand: ?*const fn ([]const u8) void = null,
    XmlDeclHandler: ?*const fn (?[]const u8, ?[]const u8, i32) void = null,
    StartDoctypeDeclHandler: ?*const fn ([]const u8, ?[]const u8, ?[]const u8, bool) void = null,
    EndDoctypeDeclHandler: ?*const fn () void = null,
    StartNamespaceDeclHandler: ?*const fn ([]const u8, ?[]const u8) void = null,
    EndNamespaceDeclHandler: ?*const fn ([]const u8) void = null,

    // State
    buffer_text: bool = false,
    buffer_used: usize = 0,
    ordered_attributes: bool = false,
    specified_attributes: bool = false,

    pub fn init(allocator: std.mem.Allocator, encoding: ?[]const u8, namespace_separator: ?u8) Self {
        return .{
            .allocator = allocator,
            .encoding = encoding,
            .namespace_separator = namespace_separator,
            .buffer = .{},
            .error_code = errors.XML_ERROR_NONE,
            .error_lineno = 0,
            .error_offset = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Parse XML data
    pub fn Parse(self: *Self, data: []const u8, is_final: bool) !bool {
        _ = is_final;

        // Parse using our Zig parser
        const root = parser_mod.parseXML(self.allocator, data) catch |err| {
            self.error_code = switch (err) {
                error.ParseError => errors.XML_ERROR_SYNTAX,
                else => errors.XML_ERROR_SYNTAX,
            };
            return false;
        };
        defer {
            root.deinit();
            self.allocator.destroy(root);
        }

        // Call handlers
        try self.processElement(root);

        return true;
    }

    /// Parse from file
    pub fn ParseFile(self: *Self, filename: []const u8) !bool {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        return self.Parse(content, true);
    }

    /// Process element recursively
    fn processElement(self: *Self, elem: anytype) !void {
        if (self.StartElementHandler) |handler| {
            handler(elem.tag, null);
        }

        if (elem.text) |text| {
            if (self.CharacterDataHandler) |handler| {
                handler(text);
            }
        }

        for (elem.children.items) |child| {
            try self.processElement(child);

            if (child.tail) |tail| {
                if (self.CharacterDataHandler) |handler| {
                    handler(tail);
                }
            }
        }

        if (self.EndElementHandler) |handler| {
            handler(elem.tag);
        }
    }

    /// Get error code
    pub fn GetErrorCode(self: *const Self) i32 {
        return self.error_code;
    }

    /// Get current line number
    pub fn GetCurrentLineNumber(self: *const Self) usize {
        return self.error_lineno;
    }

    /// Get current column number
    pub fn GetCurrentColumnNumber(self: *const Self) usize {
        return self.error_offset;
    }

    /// Get current byte index
    pub fn GetCurrentByteIndex(self: *const Self) usize {
        return self.error_offset;
    }

    /// Set base for relative URIs
    pub fn SetBase(self: *Self, base: []const u8) void {
        _ = self;
        _ = base;
    }

    /// Get base
    pub fn GetBase(self: *const Self) ?[]const u8 {
        _ = self;
        return null;
    }

    /// Set parameter entity parsing
    pub fn SetParamEntityParsing(self: *Self, flag: i32) void {
        _ = self;
        _ = flag;
    }

    /// Use foreign DTD
    pub fn UseForeignDTD(self: *Self, flag: bool) void {
        _ = self;
        _ = flag;
    }
};

// ============================================================================
// Factory Functions
// ============================================================================

/// Create parser
/// CPython: def ParserCreate(encoding=None, namespace_separator=None)
pub fn ParserCreate(allocator: std.mem.Allocator, encoding: ?[]const u8, namespace_separator: ?u8) XMLParserType {
    return XMLParserType.init(allocator, encoding, namespace_separator);
}

/// Get error string
/// CPython: def ErrorString(errno)
pub fn ErrorString(errno: i32) []const u8 {
    return switch (errno) {
        errors.XML_ERROR_NONE => "no error",
        errors.XML_ERROR_NO_MEMORY => "out of memory",
        errors.XML_ERROR_SYNTAX => "syntax error",
        errors.XML_ERROR_NO_ELEMENTS => "no element found",
        errors.XML_ERROR_INVALID_TOKEN => "not well-formed (invalid token)",
        errors.XML_ERROR_UNCLOSED_TOKEN => "unclosed token",
        errors.XML_ERROR_TAG_MISMATCH => "mismatched tag",
        errors.XML_ERROR_DUPLICATE_ATTRIBUTE => "duplicate attribute",
        errors.XML_ERROR_UNDEFINED_ENTITY => "undefined entity",
        else => "unknown error",
    };
}

// ============================================================================
// Module-level attributes
// ============================================================================

/// Native encoding
pub const native_encoding = "UTF-8";

/// XML parser features
pub const XML_PARAM_ENTITY_PARSING_NEVER: i32 = 0;
pub const XML_PARAM_ENTITY_PARSING_UNLESS_STANDALONE: i32 = 1;
pub const XML_PARAM_ENTITY_PARSING_ALWAYS: i32 = 2;

// ============================================================================
// Tests
// ============================================================================

test "ParserCreate" {
    const allocator = std.testing.allocator;
    var parser = ParserCreate(allocator, null, null);
    defer parser.deinit();
}

test "Parse" {
    const allocator = std.testing.allocator;
    var parser = ParserCreate(allocator, null, null);
    defer parser.deinit();

    const result = try parser.Parse("<root><child/></root>", true);
    try std.testing.expect(result);
}

test "ErrorString" {
    try std.testing.expectEqualStrings("no error", ErrorString(errors.XML_ERROR_NONE));
    try std.testing.expectEqualStrings("syntax error", ErrorString(errors.XML_ERROR_SYNTAX));
}
