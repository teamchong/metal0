/// _markupbase - Shared Base for SGML/HTML/XML Parsers
/// Mirrors cpython/Lib/_markupbase.py
///
/// Base class for SGML-like parsers used by html.parser and xml.
/// Provides core parsing functionality for DOCTYPE declarations,
/// processing instructions, CDATA, and entity references.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Parser State
// ============================================================================

/// Parser state enumeration
pub const ParserState = enum {
    data, // Normal content
    tag_open, // Just saw <
    end_tag_open, // Just saw </
    tag_name, // Reading tag name
    attribute_name, // Reading attribute name
    before_attribute_value, // After =
    attribute_value_quoted, // In "..." or '...'
    attribute_value_unquoted, // In value without quotes
    self_closing, // Just saw /
    bogus_comment, // In <!-- or similar
    markup_declaration, // In <! declaration
    cdata, // In <![CDATA[...]]>
    doctype, // In <!DOCTYPE...>
    processing_instruction, // In <?...?>
};

// ============================================================================
// Parse Errors
// ============================================================================

/// Parse error
pub const ParseError = struct {
    message: []const u8,
    line: usize,
    column: usize,
    offset: usize,

    pub fn format(self: *const ParseError, allocator: Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s} at line {d}, column {d}", .{
            self.message,
            self.line,
            self.column,
        });
    }
};

// ============================================================================
// ParserBase
// ============================================================================

/// Base parser for SGML/HTML/XML
pub const ParserBase = struct {
    const Self = @This();

    /// Raw data being parsed
    rawdata: []const u8 = "",
    /// Current position in rawdata
    lineno: usize = 1,
    /// Current line number
    offset: usize = 0,
    /// Allocator
    allocator: Allocator,
    /// Last error
    last_error: ?ParseError = null,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Feed data to the parser
    pub fn feed(self: *Self, data: []const u8) void {
        self.rawdata = data;
        self.offset = 0;
    }

    /// Reset the parser
    pub fn parserReset(self: *Self) void {
        self.rawdata = "";
        self.lineno = 1;
        self.offset = 0;
        self.last_error = null;
    }

    /// Get current position
    pub fn getPos(self: *const Self) struct { lineno: usize, offset: usize } {
        return .{ .lineno = self.lineno, .offset = self.offset };
    }

    /// Set error
    pub fn setError(self: *Self, message: []const u8) void {
        self.last_error = .{
            .message = message,
            .line = self.lineno,
            .column = 0,
            .offset = self.offset,
        };
    }

    /// Update line count
    pub fn updateLineNumber(self: *Self, data: []const u8) void {
        for (data) |c| {
            if (c == '\n') {
                self.lineno += 1;
            }
        }
    }

    // ========================================================================
    // Declaration Parsing
    // ========================================================================

    /// Parse a declaration (DOCTYPE, ENTITY, etc.)
    pub fn parseDeclaration(self: *Self, data: []const u8) ?struct { decl_type: []const u8, content: []const u8, end: usize } {
        if (data.len < 2 or data[0] != '<' or data[1] != '!') return null;

        var i: usize = 2;

        // Check for DOCTYPE
        if (startsWithIgnoreCase(data[i..], "DOCTYPE")) {
            i += 7;
            const start = i;
            // Find end of DOCTYPE
            while (i < data.len and data[i] != '>') {
                i += 1;
            }
            if (i < data.len) {
                self.updateLineNumber(data[0..i]);
                return .{
                    .decl_type = "DOCTYPE",
                    .content = std.mem.trim(u8, data[start..i], " \t\r\n"),
                    .end = i + 1,
                };
            }
        }

        // Check for ENTITY
        if (startsWithIgnoreCase(data[i..], "ENTITY")) {
            i += 6;
            const start = i;
            while (i < data.len and data[i] != '>') {
                i += 1;
            }
            if (i < data.len) {
                self.updateLineNumber(data[0..i]);
                return .{
                    .decl_type = "ENTITY",
                    .content = std.mem.trim(u8, data[start..i], " \t\r\n"),
                    .end = i + 1,
                };
            }
        }

        return null;
    }

    /// Parse a comment <!-- ... -->
    pub fn parseComment(self: *Self, data: []const u8) ?struct { comment: []const u8, end: usize } {
        if (data.len < 4) return null;
        if (!std.mem.startsWith(u8, data, "<!--")) return null;

        // Find -->
        if (std.mem.indexOf(u8, data[4..], "-->")) |idx| {
            self.updateLineNumber(data[0 .. idx + 7]);
            return .{
                .comment = data[4 .. 4 + idx],
                .end = idx + 7,
            };
        }

        return null;
    }

    /// Parse CDATA section <![CDATA[...]]>
    pub fn parseCDATA(self: *Self, data: []const u8) ?struct { content: []const u8, end: usize } {
        if (!std.mem.startsWith(u8, data, "<![CDATA[")) return null;

        // Find ]]>
        if (std.mem.indexOf(u8, data[9..], "]]>")) |idx| {
            self.updateLineNumber(data[0 .. idx + 12]);
            return .{
                .content = data[9 .. 9 + idx],
                .end = idx + 12,
            };
        }

        return null;
    }

    /// Parse processing instruction <?...?>
    pub fn parsePI(self: *Self, data: []const u8) ?struct { target: []const u8, data_content: []const u8, end: usize } {
        if (data.len < 4 or data[0] != '<' or data[1] != '?') return null;

        var i: usize = 2;

        // Skip whitespace
        while (i < data.len and isWhitespace(data[i])) {
            i += 1;
        }

        // Read target name
        const target_start = i;
        while (i < data.len and !isWhitespace(data[i]) and data[i] != '?' and data[i] != '>') {
            i += 1;
        }
        const target = data[target_start..i];

        // Skip whitespace
        while (i < data.len and isWhitespace(data[i])) {
            i += 1;
        }

        // Read data until ?>
        const data_start = i;
        while (i + 1 < data.len) {
            if (data[i] == '?' and data[i + 1] == '>') {
                self.updateLineNumber(data[0 .. i + 2]);
                return .{
                    .target = target,
                    .data_content = data[data_start..i],
                    .end = i + 2,
                };
            }
            i += 1;
        }

        return null;
    }

    /// Parse a marked section <![...[ ... ]]>
    pub fn parseMarkedSection(self: *Self, data: []const u8) ?struct { section_type: []const u8, content: []const u8, end: usize } {
        if (data.len < 6 or !std.mem.startsWith(u8, data, "<![")) return null;

        var i: usize = 3;

        // Read section type (CDATA, INCLUDE, IGNORE, etc.)
        const type_start = i;
        while (i < data.len and data[i] != '[' and data[i] != '>') {
            i += 1;
        }
        const section_type = std.mem.trim(u8, data[type_start..i], " \t\r\n");

        if (i >= data.len or data[i] != '[') return null;
        i += 1;

        const content_start = i;

        // Find ]]>
        while (i + 2 < data.len) {
            if (data[i] == ']' and data[i + 1] == ']' and data[i + 2] == '>') {
                self.updateLineNumber(data[0 .. i + 3]);
                return .{
                    .section_type = section_type,
                    .content = data[content_start..i],
                    .end = i + 3,
                };
            }
            i += 1;
        }

        return null;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if character is whitespace
pub fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

/// Check if string starts with pattern (case insensitive)
pub fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;

    for (needle, 0..) |c, i| {
        const h = haystack[i];
        const n = c;
        if (std.ascii.toLower(h) != std.ascii.toLower(n)) return false;
    }
    return true;
}

/// Check if character is a name start character
pub fn isNameStartChar(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c == ':';
}

/// Check if character is a name character
pub fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == ':' or c == '-' or c == '.';
}

/// Parse a name from data
pub fn parseName(data: []const u8) ?[]const u8 {
    if (data.len == 0 or !isNameStartChar(data[0])) return null;

    var i: usize = 1;
    while (i < data.len and isNameChar(data[i])) {
        i += 1;
    }
    return data[0..i];
}

/// Unescape HTML entities in text
pub fn unescapeEntities(allocator: Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;

    while (i < text.len) {
        if (text[i] == '&') {
            // Look for entity
            var j = i + 1;
            while (j < text.len and text[j] != ';' and j - i < 10) {
                j += 1;
            }

            if (j < text.len and text[j] == ';') {
                const entity = text[i + 1 .. j];
                if (resolveEntity(entity)) |resolved| {
                    try result.appendSlice(resolved);
                    i = j + 1;
                    continue;
                }
            }
        }

        try result.append(text[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

/// Resolve common HTML entities
pub fn resolveEntity(entity: []const u8) ?[]const u8 {
    const map = std.StaticStringMap([]const u8).initComptime(.{
        .{ "lt", "<" },
        .{ "gt", ">" },
        .{ "amp", "&" },
        .{ "quot", "\"" },
        .{ "apos", "'" },
        .{ "nbsp", "\u{00A0}" },
        .{ "copy", "\u{00A9}" },
        .{ "reg", "\u{00AE}" },
    });
    return map.get(entity);
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _markupbase module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "is whitespace" {
    try std.testing.expect(isWhitespace(' '));
    try std.testing.expect(isWhitespace('\t'));
    try std.testing.expect(isWhitespace('\n'));
    try std.testing.expect(!isWhitespace('a'));
}

test "starts with ignore case" {
    try std.testing.expect(startsWithIgnoreCase("DOCTYPE html", "doctype"));
    try std.testing.expect(startsWithIgnoreCase("DOCTYPE html", "DOCTYPE"));
    try std.testing.expect(!startsWithIgnoreCase("ENTITY", "DOCTYPE"));
}

test "is name char" {
    try std.testing.expect(isNameStartChar('a'));
    try std.testing.expect(isNameStartChar('_'));
    try std.testing.expect(!isNameStartChar('1'));

    try std.testing.expect(isNameChar('a'));
    try std.testing.expect(isNameChar('1'));
    try std.testing.expect(isNameChar('-'));
    try std.testing.expect(!isNameChar(' '));
}

test "parse name" {
    try std.testing.expectEqualStrings("div", parseName("div class=\"foo\"").?);
    try std.testing.expectEqualStrings("my-element", parseName("my-element>").?);
    try std.testing.expect(parseName("123") == null);
}

test "resolve entity" {
    try std.testing.expectEqualStrings("<", resolveEntity("lt").?);
    try std.testing.expectEqualStrings(">", resolveEntity("gt").?);
    try std.testing.expectEqualStrings("&", resolveEntity("amp").?);
    try std.testing.expect(resolveEntity("unknown") == null);
}

test "unescape entities" {
    const allocator = std.testing.allocator;
    const result = try unescapeEntities(allocator, "Hello &amp; World &lt;3");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello & World <3", result);
}

test "parse comment" {
    const allocator = std.testing.allocator;
    var parser = ParserBase.init(allocator);
    defer parser.deinit();

    const result = parser.parseComment("<!-- This is a comment -->");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings(" This is a comment ", result.?.comment);
    try std.testing.expectEqual(@as(usize, 26), result.?.end);
}

test "parse cdata" {
    const allocator = std.testing.allocator;
    var parser = ParserBase.init(allocator);
    defer parser.deinit();

    const result = parser.parseCDATA("<![CDATA[Hello World]]>");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("Hello World", result.?.content);
}

test "parse pi" {
    const allocator = std.testing.allocator;
    var parser = ParserBase.init(allocator);
    defer parser.deinit();

    const result = parser.parsePI("<?xml version=\"1.0\"?>");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("xml", result.?.target);
}
